with Channels.Security;
with Gateway.Provider.Credentials;
with Gateway.Provider.Registry;
with Gateway.Provider.Routing;
with Runtime.Executor;
with Security.Audit;
with Security.Defaults;
with Security.Migration;

procedure Competitive_V2_Security_Regression_Fuzz_Suite is
   use type Channels.Security.Channel_Request_Decision;
   use type Gateway.Provider.Credentials.Credential_Decision;
   use type Gateway.Provider.Registry.Provider_Id;
   use type Gateway.Provider.Routing.Route_Decision;
   use type Gateway.Provider.Routing.Provider_Request_Decision;
   use type Runtime.Executor.Runtime_Admission_Decision;
   use type Security.Audit.Append_Decision;
   use type Security.Audit.Retention_Decision;
   use type Security.Migration.External_Gateway_Host_Pattern;
   use type Security.Migration.External_Public_Bind_Pattern;
   use type Security.Migration.External_Pairing_Pattern;
   use type Security.Migration.External_Allowlist_Pattern;
   use type Security.Migration.External_Workspace_Pattern;
   use type Security.Migration.External_Observability_Pattern;
   use type Security.Migration.Migration_Decision;
   use type Security.Migration.Gateway_Host_String;
   use type Security.Migration.Observability_Backend_String;

   subtype Small_Boundary is Natural range 0 .. 2;
   subtype Request_Boundary is Natural range 0 .. 3;

   type Sample_List is array (Positive range <>) of Natural;
   Weight_Samples : constant Sample_List := (0, 1, 50, 99, 100, 101);
   Slot_Samples : constant Sample_List := (0, 1, 49, 50, 98, 99, 100);

   Fully_Enabled_Config : constant Gateway.Provider.Registry.Registry_Config :=
     (Primary_Configured   => True,
      Primary_Enabled      => True,
      Failover_Configured  => True,
      Failover_Enabled     => True,
      Long_Tail_Configured => True,
      Long_Tail_Enabled    => True);

   Primary_Down_Config : constant Gateway.Provider.Registry.Registry_Config :=
     (Primary_Configured   => True,
      Primary_Enabled      => False,
      Failover_Configured  => True,
      Failover_Enabled     => True,
      Long_Tail_Configured => True,
      Long_Tail_Enabled    => True);

   Failover_Down_Config : constant Gateway.Provider.Registry.Registry_Config :=
     (Primary_Configured   => True,
      Primary_Enabled      => True,
      Failover_Configured  => True,
      Failover_Enabled     => False,
      Long_Tail_Configured => True,
      Long_Tail_Enabled    => True);

   Long_Tail_Only_Config : constant Gateway.Provider.Registry.Registry_Config :=
     (Primary_Configured   => True,
      Primary_Enabled      => False,
      Failover_Configured  => True,
      Failover_Enabled     => False,
      Long_Tail_Configured => True,
      Long_Tail_Enabled    => True);

   function Expected_Channel_Request_Decision
     (Allowlist_Size          : Natural;
      Candidate_Matches       : Boolean;
      Limiter_Configured      : Boolean;
      Requests_In_Window      : Natural;
      Max_Requests            : Natural;
      Idempotency_Key_Present : Boolean;
      Seen_Before             : Boolean)
      return Channels.Security.Channel_Request_Decision is
   begin
      if Allowlist_Size = 0 or else not Candidate_Matches then
         return Channels.Security.Channel_Request_Deny_Allowlist;
      elsif not Limiter_Configured or else Requests_In_Window > Max_Requests then
         return Channels.Security.Channel_Request_Deny_Rate_Limit;
      elsif not Idempotency_Key_Present or else Seen_Before then
         return Channels.Security.Channel_Request_Deny_Replay;
      end if;

      return Channels.Security.Channel_Request_Allow;
   end Expected_Channel_Request_Decision;

   function Expected_Runtime_Admission_Decision
     (Allowlist_Configured    : Boolean;
      Allowlist_Enforced      : Boolean;
      Allowlist_Size          : Natural;
      Candidate_Matches       : Boolean;
      Path_Has_Traversal      : Boolean;
      Targets_Forbidden_Path  : Boolean;
      Restrict_To_Workspace   : Boolean;
      Is_Subpath_Of_Workspace : Boolean;
      Egress_Enabled          : Boolean;
      URL_SSRF_Suspected      : Boolean;
      Targets_Private_Net     : Boolean;
      Targets_Local_Network   : Boolean)
      return Runtime.Executor.Runtime_Admission_Decision is
   begin
      if Allowlist_Configured and then not Allowlist_Enforced then
         return Runtime.Executor.Runtime_Admission_Deny_Allowlist_Not_Enforced;
      elsif Allowlist_Enforced and then Allowlist_Size = 0 then
         return Runtime.Executor.Runtime_Admission_Deny_Channel_Empty_Allowlist;
      elsif Allowlist_Enforced and then not Candidate_Matches then
         return Runtime.Executor.Runtime_Admission_Deny_Channel_Not_Allowlisted;
      elsif Path_Has_Traversal then
         return Runtime.Executor.Runtime_Admission_Deny_Path_Traversal;
      elsif Targets_Forbidden_Path then
         return Runtime.Executor.Runtime_Admission_Deny_Forbidden_Path;
      elsif Restrict_To_Workspace and then not Is_Subpath_Of_Workspace then
         return Runtime.Executor.Runtime_Admission_Deny_Outside_Workspace_Root;
      elsif not Egress_Enabled then
         return Runtime.Executor.Runtime_Admission_Deny_URL_Egress_Disabled;
      elsif URL_SSRF_Suspected then
         return Runtime.Executor.Runtime_Admission_Deny_URL_SSRF;
      elsif Targets_Private_Net then
         return Runtime.Executor.Runtime_Admission_Deny_URL_Private_Network;
      elsif Targets_Local_Network then
         return Runtime.Executor.Runtime_Admission_Deny_URL_Local_Network;
      end if;

      return Runtime.Executor.Runtime_Admission_Allow;
   end Expected_Runtime_Admission_Decision;

   function Expected_Credential_Decision
     (Token_Present      : Boolean;
      Provider_Matches   : Boolean;
      Is_Fallback        : Boolean)
      return Gateway.Provider.Credentials.Credential_Decision is
   begin
      if not Token_Present then
         return Gateway.Provider.Credentials.Credential_Deny_Missing_Token;
      elsif not Provider_Matches and then Is_Fallback then
         return
           Gateway.Provider.Credentials.Credential_Deny_Cross_Provider_Fallback;
      elsif not Provider_Matches then
         return Gateway.Provider.Credentials.Credential_Deny_Provider_Mismatch;
      end if;

      return Gateway.Provider.Credentials.Credential_Allow;
   end Expected_Credential_Decision;

   function Expected_Append_Decision
     (Subject_Set              : Boolean;
      Classification_Set       : Boolean;
      Redaction_Metadata_Flag  : Boolean;
      Includes_Secret_Material : Boolean;
      Includes_Token_Material  : Boolean) return Security.Audit.Append_Decision is
      Metadata_Valid : constant Boolean :=
        Subject_Set and then Classification_Set and then Redaction_Metadata_Flag;
   begin
      if not Metadata_Valid then
         return Security.Audit.Append_Deny_Invalid_Redaction_Metadata;
      elsif Includes_Secret_Material then
         return Security.Audit.Append_Deny_Unredacted_Secret_Material;
      elsif Includes_Token_Material then
         return Security.Audit.Append_Deny_Unredacted_Token_Material;
      end if;

      return Security.Audit.Append_Allow;
   end Expected_Append_Decision;

   function Expected_Retention_Decision
     (Current_Entries    : Natural;
      Max_Entries        : Natural;
      Oldest_Age_Seconds : Natural;
      Max_Age_Seconds    : Natural) return Security.Audit.Retention_Decision is
      Needs_Entry_Prune : constant Boolean := Current_Entries >= Max_Entries;
      Needs_Age_Prune : constant Boolean :=
        Current_Entries > 0 and then Oldest_Age_Seconds > Max_Age_Seconds;
   begin
      if Max_Entries = 0 or else Max_Age_Seconds = 0 then
         return Security.Audit.Retention_Deny_Invalid_Limits;
      elsif Needs_Entry_Prune and then Needs_Age_Prune then
         return Security.Audit.Retention_Drop_Oldest_Max_Entries_And_Age;
      elsif Needs_Entry_Prune then
         return Security.Audit.Retention_Drop_Oldest_Max_Entries;
      elsif Needs_Age_Prune then
         return Security.Audit.Retention_Drop_Oldest_Max_Age;
      end if;

      return Security.Audit.Retention_Keep;
   end Expected_Retention_Decision;

   function Expected_Weighted_Decision
     (Primary_Enabled    : Boolean;
      Failover_Enabled   : Boolean;
      Long_Tail_Enabled  : Boolean;
      Primary_Weight     : Natural;
      Deterministic_Slot : Natural) return Gateway.Provider.Routing.Route_Decision is
   begin
      if Primary_Weight > 100 or else Deterministic_Slot > 99 then
         return Gateway.Provider.Routing.Route_Error_Invalid_Weight;
      elsif Deterministic_Slot < Primary_Weight then
         if Primary_Enabled then
            return Gateway.Provider.Routing.Route_Allow_Weighted_Primary;
         elsif Failover_Enabled then
            return Gateway.Provider.Routing.Route_Allow_Failover;
         elsif Long_Tail_Enabled then
            return Gateway.Provider.Routing.Route_Allow_Long_Tail;
         end if;
      else
         if Failover_Enabled then
            return Gateway.Provider.Routing.Route_Allow_Weighted_Failover;
         elsif Primary_Enabled then
            return Gateway.Provider.Routing.Route_Allow_Primary;
         elsif Long_Tail_Enabled then
            return Gateway.Provider.Routing.Route_Allow_Long_Tail;
         end if;
      end if;

      return Gateway.Provider.Routing.Route_Deny_No_Provider;
   end Expected_Weighted_Decision;

   function Route_Allows
     (Decision : Gateway.Provider.Routing.Route_Decision) return Boolean is
   begin
      return Decision in
        Gateway.Provider.Routing.Route_Allow_Primary
        | Gateway.Provider.Routing.Route_Allow_Failover
        | Gateway.Provider.Routing.Route_Allow_Long_Tail
        | Gateway.Provider.Routing.Route_Allow_Weighted_Primary
        | Gateway.Provider.Routing.Route_Allow_Weighted_Failover;
   end Route_Allows;

   function Expected_Migration_Decision
     (Maps_Directly : Boolean) return Security.Migration.Migration_Decision is
   begin
      if Maps_Directly then
         return Security.Migration.Mapped_Secure_Input;
      end if;
      return Security.Migration.Forced_Secure_Default;
   end Expected_Migration_Decision;

   procedure Assert_Weighted_Routing
     (Config            : Gateway.Provider.Registry.Registry_Config;
      Primary_Enabled   : Boolean;
      Failover_Enabled  : Boolean;
      Long_Tail_Enabled : Boolean) is
      Route : Gateway.Provider.Routing.Route_Result;
      Expected_Decision : Gateway.Provider.Routing.Route_Decision;
   begin
      for Weight_Index in Weight_Samples'Range loop
         for Slot_Index in Slot_Samples'Range loop
            Route :=
              Gateway.Provider.Routing.Weighted_Decision
                (Config             => Config,
                 Primary_Weight     => Weight_Samples (Weight_Index),
                 Deterministic_Slot => Slot_Samples (Slot_Index));
            Expected_Decision :=
              Expected_Weighted_Decision
                (Primary_Enabled    => Primary_Enabled,
                 Failover_Enabled   => Failover_Enabled,
                 Long_Tail_Enabled  => Long_Tail_Enabled,
                 Primary_Weight     => Weight_Samples (Weight_Index),
                 Deterministic_Slot => Slot_Samples (Slot_Index));

            pragma Assert (Route.Decision = Expected_Decision);
            pragma Assert (Route.Allowed = Route_Allows (Expected_Decision));
            if Route.Decision in
                Gateway.Provider.Routing.Route_Allow_Failover
                | Gateway.Provider.Routing.Route_Allow_Long_Tail
            then
               pragma Assert (Gateway.Provider.Routing.Route_Uses_Fallback (Route));
            else
               pragma Assert
                 (not Gateway.Provider.Routing.Route_Uses_Fallback (Route));
            end if;
         end loop;
      end loop;
   end Assert_Weighted_Routing;

   Admission_Decision : Runtime.Executor.Runtime_Admission_Decision;
   Channel_Result : Channels.Security.Channel_Request_Result;
   Credential_Decision : Gateway.Provider.Credentials.Credential_Decision;
   Request_Result : Gateway.Provider.Routing.Provider_Request_Result;
   Append_Decision : Security.Audit.Append_Decision;
   Retention_Decision : Security.Audit.Retention_Decision;
   Payload : Security.Audit.Redacted_Payload;
   Report : Security.Migration.Migration_Report;
begin
   for Channel in Channels.Security.Channel_Kind loop
      for Allowlist_Configured in Boolean loop
         for Allowlist_Enforced in Boolean loop
            for Allowlist_Size in Small_Boundary loop
               for Candidate_Matches in Boolean loop
                  for Path_Has_Traversal in Boolean loop
                     for Targets_Forbidden_Path in Boolean loop
                        for Restrict_To_Workspace in Boolean loop
                           for Is_Subpath_Of_Workspace in Boolean loop
                              for Egress_Enabled in Boolean loop
                                 for URL_SSRF_Suspected in Boolean loop
                                    for Targets_Private_Net in Boolean loop
                                       for Targets_Local_Network in Boolean loop
                                          Admission_Decision :=
                                            Runtime.Executor.Runtime_Admission_Policy_Decision
                                              (Channel                 => Channel,
                                               Allowlist_Configured    => Allowlist_Configured,
                                               Allowlist_Enforced      => Allowlist_Enforced,
                                               Allowlist_Size          => Allowlist_Size,
                                               Candidate_Matches       => Candidate_Matches,
                                               Path_Has_Traversal      => Path_Has_Traversal,
                                               Targets_Forbidden_Path  => Targets_Forbidden_Path,
                                               Restrict_To_Workspace   => Restrict_To_Workspace,
                                               Is_Subpath_Of_Workspace => Is_Subpath_Of_Workspace,
                                               Egress_Enabled          => Egress_Enabled,
                                               URL_SSRF_Suspected      => URL_SSRF_Suspected,
                                               Targets_Private_Net     => Targets_Private_Net,
                                               Targets_Local_Network   => Targets_Local_Network);
                                          pragma Assert
                                            (Admission_Decision =
                                               Expected_Runtime_Admission_Decision
                                                 (Allowlist_Configured    => Allowlist_Configured,
                                                  Allowlist_Enforced      => Allowlist_Enforced,
                                                  Allowlist_Size          => Allowlist_Size,
                                                  Candidate_Matches       => Candidate_Matches,
                                                  Path_Has_Traversal      => Path_Has_Traversal,
                                                  Targets_Forbidden_Path  => Targets_Forbidden_Path,
                                                  Restrict_To_Workspace   => Restrict_To_Workspace,
                                                  Is_Subpath_Of_Workspace => Is_Subpath_Of_Workspace,
                                                  Egress_Enabled          => Egress_Enabled,
                                                  URL_SSRF_Suspected      => URL_SSRF_Suspected,
                                                  Targets_Private_Net     => Targets_Private_Net,
                                                  Targets_Local_Network   => Targets_Local_Network));
                                          pragma Assert
                                            (Runtime.Executor.Runtime_Admission_Allowed
                                               (Channel                 => Channel,
                                                Allowlist_Configured    => Allowlist_Configured,
                                                Allowlist_Enforced      => Allowlist_Enforced,
                                                Allowlist_Size          => Allowlist_Size,
                                                Candidate_Matches       => Candidate_Matches,
                                                Path_Has_Traversal      => Path_Has_Traversal,
                                                Targets_Forbidden_Path  => Targets_Forbidden_Path,
                                                Restrict_To_Workspace   => Restrict_To_Workspace,
                                                Is_Subpath_Of_Workspace => Is_Subpath_Of_Workspace,
                                                Egress_Enabled          => Egress_Enabled,
                                                URL_SSRF_Suspected      => URL_SSRF_Suspected,
                                                Targets_Private_Net     => Targets_Private_Net,
                                                Targets_Local_Network   => Targets_Local_Network) =
                                               (Admission_Decision =
                                                  Runtime.Executor.Runtime_Admission_Allow));
                                       end loop;
                                    end loop;
                                 end loop;
                              end loop;
                           end loop;
                        end loop;
                     end loop;
                  end loop;
               end loop;
            end loop;
         end loop;
      end loop;
   end loop;

   for Channel in Channels.Security.Channel_Kind loop
      for Allowlist_Size in Small_Boundary loop
         for Candidate_Matches in Boolean loop
            for Limiter_Configured in Boolean loop
               for Requests_In_Window in Request_Boundary loop
                  for Max_Requests in Small_Boundary loop
                     for Idempotency_Key_Present in Boolean loop
                        for Seen_Before in Boolean loop
                           Channel_Result :=
                             Channels.Security.Evaluate_Channel_Request
                               (Channel                 => Channel,
                                Allowlist_Size          => Allowlist_Size,
                                Candidate_Matches       => Candidate_Matches,
                                Limiter_Configured      => Limiter_Configured,
                                Requests_In_Window      => Requests_In_Window,
                                Max_Requests            => Max_Requests,
                                Idempotency_Key_Present => Idempotency_Key_Present,
                                Seen_Before             => Seen_Before);
                           pragma Assert
                             (Channel_Result.Decision =
                                Expected_Channel_Request_Decision
                                  (Allowlist_Size          => Allowlist_Size,
                                   Candidate_Matches       => Candidate_Matches,
                                   Limiter_Configured      => Limiter_Configured,
                                   Requests_In_Window      => Requests_In_Window,
                                   Max_Requests            => Max_Requests,
                                   Idempotency_Key_Present => Idempotency_Key_Present,
                                   Seen_Before             => Seen_Before));
                           pragma Assert
                             (Channel_Result.Allowed =
                                (Channel_Result.Decision =
                                   Channels.Security.Channel_Request_Allow));
                        end loop;
                     end loop;
                  end loop;
               end loop;
            end loop;
         end loop;
      end loop;
   end loop;

   for Token_Present in Boolean loop
      for Token_Provider in Gateway.Provider.Registry.Provider_Id loop
         for Requested_Provider in Gateway.Provider.Registry.Provider_Id loop
            for Is_Fallback in Boolean loop
               Credential_Decision :=
                 Gateway.Provider.Credentials.Access_Decision
                   (Token              =>
                      Gateway.Provider.Credentials.Bind_Token
                        (Provider      => Token_Provider,
                         Token_Present => Token_Present),
                    Requested_Provider => Requested_Provider,
                    Is_Fallback        => Is_Fallback);
               pragma Assert
                 (Credential_Decision =
                    Expected_Credential_Decision
                      (Token_Present    => Token_Present,
                       Provider_Matches => Token_Provider = Requested_Provider,
                       Is_Fallback      => Is_Fallback));
               pragma Assert
                 (Gateway.Provider.Credentials.Token_Authorizes
                    (Token              =>
                       Gateway.Provider.Credentials.Bind_Token
                         (Provider      => Token_Provider,
                          Token_Present => Token_Present),
                     Requested_Provider => Requested_Provider,
                     Is_Fallback        => Is_Fallback) =
                    (Credential_Decision =
                       Gateway.Provider.Credentials.Credential_Allow));
            end loop;
         end loop;
      end loop;
   end loop;

   Assert_Weighted_Routing
     (Config            => Fully_Enabled_Config,
      Primary_Enabled   => True,
      Failover_Enabled  => True,
      Long_Tail_Enabled => True);
   Assert_Weighted_Routing
     (Config            => Primary_Down_Config,
      Primary_Enabled   => False,
      Failover_Enabled  => True,
      Long_Tail_Enabled => True);
   Assert_Weighted_Routing
     (Config            => Failover_Down_Config,
      Primary_Enabled   => True,
      Failover_Enabled  => False,
      Long_Tail_Enabled => True);
   Assert_Weighted_Routing
     (Config            => Long_Tail_Only_Config,
      Primary_Enabled   => False,
      Failover_Enabled  => False,
      Long_Tail_Enabled => True);

   Request_Result :=
     Gateway.Provider.Routing.Weighted_Request_Decision
       (Config             => Fully_Enabled_Config,
        Token              =>
          Gateway.Provider.Credentials.Bind_Token
            (Provider      => Gateway.Provider.Registry.Primary_Provider,
             Token_Present => True),
        Primary_Weight     => 101,
        Deterministic_Slot => 0);
   pragma Assert (not Gateway.Provider.Routing.Request_Authorized (Request_Result));
   pragma Assert
     (Request_Result.Decision =
        Gateway.Provider.Routing.Provider_Request_Deny_Invalid_Weight);

   Request_Result :=
     Gateway.Provider.Routing.Scoped_Request_Decision
       (Route =>
          (Allowed  => True,
           Provider => Gateway.Provider.Registry.Failover_Provider,
           Decision => Gateway.Provider.Routing.Route_Allow_Failover),
        Token =>
          Gateway.Provider.Credentials.Bind_Token
            (Provider      => Gateway.Provider.Registry.Primary_Provider,
             Token_Present => True));
   pragma Assert (not Gateway.Provider.Routing.Request_Authorized (Request_Result));
   pragma Assert
     (Request_Result.Decision =
        Gateway.Provider.Routing.Provider_Request_Deny_Cross_Provider_Fallback);

   Request_Result :=
     Gateway.Provider.Routing.Scoped_Request_Decision
       (Route =>
          (Allowed  => True,
           Provider => Gateway.Provider.Registry.Failover_Provider,
           Decision => Gateway.Provider.Routing.Route_Allow_Weighted_Failover),
        Token =>
          Gateway.Provider.Credentials.Bind_Token
            (Provider      => Gateway.Provider.Registry.Primary_Provider,
             Token_Present => True));
   pragma Assert (not Gateway.Provider.Routing.Request_Authorized (Request_Result));
   pragma Assert
     (Request_Result.Decision =
        Gateway.Provider.Routing.Provider_Request_Deny_Provider_Mismatch);

   for Kind in Security.Audit.Event_Kind loop
      for Subject_Set in Boolean loop
         for Classification_Set in Boolean loop
            for Redaction_Metadata_Flag in Boolean loop
               for Includes_Secret_Material in Boolean loop
                  for Includes_Token_Material in Boolean loop
                     Payload :=
                       (Subject_Set              => Subject_Set,
                        Classification_Set       => Classification_Set,
                        Redaction_Metadata_Valid => Redaction_Metadata_Flag,
                        Includes_Secret_Material => Includes_Secret_Material,
                        Includes_Token_Material  => Includes_Token_Material);
                     Append_Decision :=
                       Security.Audit.Append_Policy_Decision
                         (Kind    => Kind,
                          Payload => Payload);
                     pragma Assert
                       (Append_Decision =
                          Expected_Append_Decision
                            (Subject_Set              => Subject_Set,
                             Classification_Set       => Classification_Set,
                             Redaction_Metadata_Flag  => Redaction_Metadata_Flag,
                             Includes_Secret_Material => Includes_Secret_Material,
                             Includes_Token_Material  => Includes_Token_Material));
                     pragma Assert
                       (Security.Audit.Append_Allowed
                          (Kind    => Kind,
                           Payload => Payload) =
                          (Append_Decision = Security.Audit.Append_Allow));
                     pragma Assert
                       (Security.Audit.Payload_Is_Redacted (Payload) =
                          (Subject_Set
                           and then Classification_Set
                           and then Redaction_Metadata_Flag
                           and then not Includes_Secret_Material
                           and then not Includes_Token_Material));
                  end loop;
               end loop;
            end loop;
         end loop;
      end loop;
   end loop;

   for Current_Entries in Request_Boundary loop
      for Max_Entries in Small_Boundary loop
         for Oldest_Age_Seconds in Request_Boundary loop
            for Max_Age_Seconds in Small_Boundary loop
               Retention_Decision :=
                 Security.Audit.Retention_Policy_Decision
                   (Current_Entries    => Current_Entries,
                    Max_Entries        => Max_Entries,
                    Oldest_Age_Seconds => Oldest_Age_Seconds,
                    Max_Age_Seconds    => Max_Age_Seconds);
               pragma Assert
                 (Retention_Decision =
                    Expected_Retention_Decision
                      (Current_Entries    => Current_Entries,
                       Max_Entries        => Max_Entries,
                       Oldest_Age_Seconds => Oldest_Age_Seconds,
                       Max_Age_Seconds    => Max_Age_Seconds));
               pragma Assert
                 (Security.Audit.Retention_Allows_Append
                    (Current_Entries    => Current_Entries,
                     Max_Entries        => Max_Entries,
                     Oldest_Age_Seconds => Oldest_Age_Seconds,
                     Max_Age_Seconds    => Max_Age_Seconds) =
                    (Retention_Decision /=
                       Security.Audit.Retention_Deny_Invalid_Limits));
            end loop;
         end loop;
      end loop;
   end loop;

   for Gateway_Host in Security.Migration.External_Gateway_Host_Pattern loop
      for Public_Bind in Security.Migration.External_Public_Bind_Pattern loop
         for Pairing in Security.Migration.External_Pairing_Pattern loop
            for Allowlist in Security.Migration.External_Allowlist_Pattern loop
               for Workspace in Security.Migration.External_Workspace_Pattern loop
                  for Observability in
                    Security.Migration.External_Observability_Pattern
                  loop
                     Report :=
                       Security.Migration.Migrate
                         (Input =>
                            (Gateway_Host  => Gateway_Host,
                             Public_Bind   => Public_Bind,
                             Pairing       => Pairing,
                             Allowlist     => Allowlist,
                             Workspace     => Workspace,
                             Observability => Observability));
                     pragma Assert
                       (Report.Config.Gateway_Bind_Host =
                          Security.Defaults.Gateway_Bind_Host);
                     pragma Assert
                       (Report.Config.Allow_Public_Bind =
                          Security.Defaults.Allow_Public_Bind_Default);
                     pragma Assert
                       (Report.Config.Require_Pairing =
                          Security.Defaults.Require_Pairing_Default);
                     pragma Assert (Report.Config.Empty_Allowlist_Denies_All);
                     pragma Assert
                       (Report.Config.Restrict_Tool_To_Workspace =
                          Security.Defaults.Workspace_Only_Default);
                     pragma Assert
                       (Report.Config.Observability_Backend =
                          Security.Defaults.Observability_Backend_Default);

                     pragma Assert
                       (Report.Gateway_Host_Decision =
                          Expected_Migration_Decision
                            (Gateway_Host = Security.Migration.Host_Local_Only));
                     pragma Assert
                       (Report.Public_Bind_Decision =
                          Expected_Migration_Decision
                            (Public_Bind =
                               Security.Migration.Public_Bind_Disabled));
                     pragma Assert
                       (Report.Pairing_Decision =
                          Expected_Migration_Decision
                            (Pairing = Security.Migration.Pairing_Required));
                     pragma Assert
                       (Report.Allowlist_Decision =
                          Expected_Migration_Decision
                            (Allowlist = Security.Migration.Allowlist_Required));
                     pragma Assert
                       (Report.Workspace_Decision =
                          Expected_Migration_Decision
                            (Workspace =
                               Security.Migration.Workspace_Restricted));
                     pragma Assert
                       (Report.Observability_Decision =
                          Expected_Migration_Decision
                            (Observability =
                               Security.Migration.Observability_None));
                  end loop;
               end loop;
            end loop;
         end loop;
      end loop;
   end loop;
end Competitive_V2_Security_Regression_Fuzz_Suite;
