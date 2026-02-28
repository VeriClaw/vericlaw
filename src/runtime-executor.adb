package body Runtime.Executor with SPARK_Mode is
   use type Channels.Security.Allowlist_Decision;
   use type Security.Policy.Egress_Decision;

   function Limits_Policy_Decision (Config : Limits) return Limits_Decision is
   begin
      if Config.Max_Seconds > 300 then
         return Limits_Deny_Seconds_Too_High;
      elsif Config.Max_Memory_MB > 1024 then
         return Limits_Deny_Memory_Too_High;
      elsif Config.Max_Processes > 16 then
         return Limits_Deny_Processes_Too_High;
      else
         return Limits_Allow_Strict;
      end if;
   end Limits_Policy_Decision;

   function Limits_Are_Strict (Config : Limits) return Boolean is
   begin
      return Limits_Policy_Decision (Config) = Limits_Allow_Strict;
   end Limits_Are_Strict;

   function Select_Sandbox_Backend
     (Requested_Backend : Sandbox_Backend_Label;
      Availability      : Sandbox_Backend_Availability)
      return Sandbox_Backend_Label is
   begin
      if not Availability.Availability_Known then
         return Sandbox_Backend_Unknown;
      elsif Requested_Backend = Sandbox_Backend_Auto then
         if Availability.Landlock_Available then
            return Sandbox_Backend_Landlock;
         elsif Availability.Seccomp_Available then
            return Sandbox_Backend_Seccomp;
         elsif Availability.Firejail_Available then
            return Sandbox_Backend_Firejail;
         else
            return Sandbox_Backend_None;
         end if;
      elsif Requested_Backend = Sandbox_Backend_Firejail then
         if Availability.Firejail_Available then
            return Sandbox_Backend_Firejail;
         end if;
         return Sandbox_Backend_Unknown;
      elsif Requested_Backend = Sandbox_Backend_Landlock then
         if Availability.Landlock_Available then
            return Sandbox_Backend_Landlock;
         end if;
         return Sandbox_Backend_Unknown;
      elsif Requested_Backend = Sandbox_Backend_Seccomp then
         if Availability.Seccomp_Available then
            return Sandbox_Backend_Seccomp;
         end if;
         return Sandbox_Backend_Unknown;
      elsif Requested_Backend = Sandbox_Backend_None then
         return Sandbox_Backend_None;
      else
         return Sandbox_Backend_Unknown;
      end if;
   end Select_Sandbox_Backend;

   function Sandbox_Backend_Policy_Decision
     (Requested_Backend : Sandbox_Backend_Label;
      Availability      : Sandbox_Backend_Availability)
      return Sandbox_Backend_Decision is
      Selected_Backend : constant Sandbox_Backend_Label :=
        Select_Sandbox_Backend (Requested_Backend, Availability);
   begin
      case Selected_Backend is
         when Sandbox_Backend_Firejail =>
            return Sandbox_Backend_Allow_Firejail;
         when Sandbox_Backend_Landlock =>
            return Sandbox_Backend_Allow_Landlock;
         when Sandbox_Backend_Seccomp =>
            return Sandbox_Backend_Allow_Seccomp;
         when Sandbox_Backend_None =>
            return Sandbox_Backend_Deny_None;
         when Sandbox_Backend_Auto | Sandbox_Backend_Unknown =>
            return Sandbox_Backend_Deny_Unknown;
      end case;
   end Sandbox_Backend_Policy_Decision;

   function Sandbox_Backend_Valid
     (Requested_Backend : Sandbox_Backend_Label;
      Availability      : Sandbox_Backend_Availability) return Boolean is
   begin
      return Sandbox_Backend_Policy_Decision
        (Requested_Backend, Availability) in
          Sandbox_Backend_Allow_Firejail
          | Sandbox_Backend_Allow_Landlock
          | Sandbox_Backend_Allow_Seccomp;
   end Sandbox_Backend_Valid;

   function Evaluate_Sandbox_Run_Admission
      (Mode              : Sandbox_Security_Mode;
       Requested_Backend : Sandbox_Backend_Label;
       Availability      : Sandbox_Backend_Availability)
       return Sandbox_Run_Admission_Result is
      Selected_Backend : constant Sandbox_Backend_Label :=
        Select_Sandbox_Backend (Requested_Backend, Availability);
      Decision : Sandbox_Run_Decision;
   begin
      if Mode = Sandbox_Mode_Unknown then
         Decision := Sandbox_Run_Deny_Unknown_Mode;
      elsif Mode = Sandbox_Mode_Unsafe then
         Decision := Sandbox_Run_Deny_Unsafe_Mode;
      elsif Selected_Backend not in
          Sandbox_Backend_Firejail
          | Sandbox_Backend_Landlock
          | Sandbox_Backend_Seccomp
      then
         Decision := Sandbox_Run_Deny_Invalid_Backend;
      elsif Mode = Sandbox_Mode_Strict
        and then Selected_Backend = Sandbox_Backend_Firejail
      then
         Decision := Sandbox_Run_Deny_Firejail_Not_Allowed;
      else
         Decision := Sandbox_Run_Allow;
      end if;

      return
        (Allowed          => Decision = Sandbox_Run_Allow,
         Selected_Backend => Selected_Backend,
         Decision         => Decision);
   end Evaluate_Sandbox_Run_Admission;

   function Sandbox_Run_Policy_Decision
     (Mode              : Sandbox_Security_Mode;
      Requested_Backend : Sandbox_Backend_Label;
      Availability      : Sandbox_Backend_Availability)
      return Sandbox_Run_Decision is
   begin
      return Evaluate_Sandbox_Run_Admission
        (Mode              => Mode,
         Requested_Backend => Requested_Backend,
         Availability      => Availability).Decision;
   end Sandbox_Run_Policy_Decision;

   function Can_Run_With_Sandbox
      (Mode              : Sandbox_Security_Mode;
       Requested_Backend : Sandbox_Backend_Label;
       Availability      : Sandbox_Backend_Availability) return Boolean is
   begin
      return Evaluate_Sandbox_Run_Admission
        (Mode              => Mode,
         Requested_Backend => Requested_Backend,
         Availability      => Availability).Allowed;
   end Can_Run_With_Sandbox;

   function Runtime_Path_Policy_Decision
     (Path_Has_Traversal      : Boolean;
      Targets_Forbidden_Path  : Boolean;
      Restrict_To_Workspace   : Boolean;
      Is_Subpath_Of_Workspace : Boolean) return Runtime_Path_Decision is
   begin
      if Path_Has_Traversal then
         return Runtime_Path_Deny_Path_Traversal;
      elsif Targets_Forbidden_Path then
         return Runtime_Path_Deny_Forbidden_Path;
      end if;

      case Security.Policy.Workspace_Scope_Decision
          (Restrict_To_Workspace => Restrict_To_Workspace,
           Is_Subpath            => Is_Subpath_Of_Workspace)
      is
         when Security.Policy.Workspace_Deny_Outside_Root =>
            return Runtime_Path_Deny_Outside_Workspace_Root;
         when Security.Policy.Workspace_Allow =>
            return Runtime_Path_Allow;
      end case;
   end Runtime_Path_Policy_Decision;

   function Evaluate_Runtime_URL_Admission
     (Egress_Enabled        : Boolean;
      URL_SSRF_Suspected    : Boolean;
      Targets_Private_Net   : Boolean;
      Targets_Local_Network : Boolean) return Runtime_URL_Admission_Result is
      Egress_Decision : constant Security.Policy.Egress_Decision :=
        Security.Policy.Outbound_Egress_Decision
          (Egress_Enabled        => Egress_Enabled,
           Targets_Private_Net   => Targets_Private_Net,
           Targets_Local_Network => Targets_Local_Network);
      Decision : Runtime_URL_Decision;
   begin
      if Egress_Decision = Security.Policy.Egress_Deny_Disabled then
         Decision := Runtime_URL_Deny_Egress_Disabled;
      elsif URL_SSRF_Suspected then
         Decision := Runtime_URL_Deny_SSRF;
      elsif Egress_Decision = Security.Policy.Egress_Deny_Private_Network then
         Decision := Runtime_URL_Deny_Private_Network;
      elsif Egress_Decision = Security.Policy.Egress_Deny_Local_Network then
         Decision := Runtime_URL_Deny_Local_Network;
      else
         Decision := Runtime_URL_Allow;
      end if;

      return
        (Allowed  => Decision = Runtime_URL_Allow,
         Decision => Decision);
   end Evaluate_Runtime_URL_Admission;

   function Runtime_URL_Policy_Decision
      (Egress_Enabled        : Boolean;
       URL_SSRF_Suspected    : Boolean;
       Targets_Private_Net   : Boolean;
       Targets_Local_Network : Boolean) return Runtime_URL_Decision is
   begin
      return Evaluate_Runtime_URL_Admission
        (Egress_Enabled        => Egress_Enabled,
         URL_SSRF_Suspected    => URL_SSRF_Suspected,
         Targets_Private_Net   => Targets_Private_Net,
         Targets_Local_Network => Targets_Local_Network).Decision;
   end Runtime_URL_Policy_Decision;

   function Runtime_Channel_Allowlist_Policy_Decision
     (Channel              : Channels.Security.Channel_Kind;
      Allowlist_Configured : Boolean;
      Allowlist_Enforced   : Boolean;
      Allowlist_Size       : Natural;
      Candidate_Matches    : Boolean) return Runtime_Allowlist_Decision is
   begin
      if Allowlist_Configured and then not Allowlist_Enforced then
         return Runtime_Allowlist_Deny_Not_Enforced;
      elsif not Allowlist_Enforced then
         return Runtime_Allowlist_Allow;
      end if;

      case Channels.Security.Allowlist_Policy_Decision
          (Channel           => Channel,
           Allowlist_Size    => Allowlist_Size,
           Candidate_Matches => Candidate_Matches)
      is
         when Channels.Security.Allowlist_Allow =>
            return Runtime_Allowlist_Allow;
         when Channels.Security.Allowlist_Deny_Empty_Allowlist =>
            return Runtime_Allowlist_Deny_Empty_Allowlist;
         when Channels.Security.Allowlist_Deny_Not_Allowlisted =>
            return Runtime_Allowlist_Deny_Not_Allowlisted;
      end case;
   end Runtime_Channel_Allowlist_Policy_Decision;

   function Runtime_Admission_Policy_Decision
     (Channel                 : Channels.Security.Channel_Kind;
      Allowlist_Configured    : Boolean;
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
      Targets_Local_Network   : Boolean) return Runtime_Admission_Decision is
      Allowlist_Decision : constant Runtime_Allowlist_Decision :=
        Runtime_Channel_Allowlist_Policy_Decision
          (Channel              => Channel,
           Allowlist_Configured => Allowlist_Configured,
           Allowlist_Enforced   => Allowlist_Enforced,
           Allowlist_Size       => Allowlist_Size,
           Candidate_Matches    => Candidate_Matches);
      Path_Decision : constant Runtime_Path_Decision :=
        Runtime_Path_Policy_Decision
          (Path_Has_Traversal      => Path_Has_Traversal,
           Targets_Forbidden_Path  => Targets_Forbidden_Path,
           Restrict_To_Workspace   => Restrict_To_Workspace,
           Is_Subpath_Of_Workspace => Is_Subpath_Of_Workspace);
      URL_Result : constant Runtime_URL_Admission_Result :=
        Evaluate_Runtime_URL_Admission
          (Egress_Enabled        => Egress_Enabled,
           URL_SSRF_Suspected    => URL_SSRF_Suspected,
           Targets_Private_Net   => Targets_Private_Net,
           Targets_Local_Network => Targets_Local_Network);
   begin
      case Allowlist_Decision is
         when Runtime_Allowlist_Deny_Not_Enforced =>
            return Runtime_Admission_Deny_Allowlist_Not_Enforced;
         when Runtime_Allowlist_Deny_Empty_Allowlist =>
            return Runtime_Admission_Deny_Channel_Empty_Allowlist;
         when Runtime_Allowlist_Deny_Not_Allowlisted =>
            return Runtime_Admission_Deny_Channel_Not_Allowlisted;
         when Runtime_Allowlist_Allow =>
            null;
      end case;

      case Path_Decision is
         when Runtime_Path_Deny_Path_Traversal =>
            return Runtime_Admission_Deny_Path_Traversal;
         when Runtime_Path_Deny_Forbidden_Path =>
            return Runtime_Admission_Deny_Forbidden_Path;
         when Runtime_Path_Deny_Outside_Workspace_Root =>
            return Runtime_Admission_Deny_Outside_Workspace_Root;
         when Runtime_Path_Allow =>
            null;
      end case;

      case URL_Result.Decision is
         when Runtime_URL_Deny_Egress_Disabled =>
            return Runtime_Admission_Deny_URL_Egress_Disabled;
         when Runtime_URL_Deny_SSRF =>
            return Runtime_Admission_Deny_URL_SSRF;
         when Runtime_URL_Deny_Private_Network =>
            return Runtime_Admission_Deny_URL_Private_Network;
         when Runtime_URL_Deny_Local_Network =>
            return Runtime_Admission_Deny_URL_Local_Network;
         when Runtime_URL_Allow =>
            return Runtime_Admission_Allow;
      end case;
   end Runtime_Admission_Policy_Decision;

   function Runtime_Admission_Allowed
      (Channel                 : Channels.Security.Channel_Kind;
       Allowlist_Configured    : Boolean;
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
      Targets_Local_Network   : Boolean) return Boolean is
   begin
      return Runtime_Admission_Policy_Decision
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
           Runtime_Admission_Allow;
   end Runtime_Admission_Allowed;

   function Plugin_Load_Policy_Decision
     (Manifest : Plugins.Capabilities.Capability_Manifest)
      return Plugin_Load_Decision is
   begin
      case Plugins.Capabilities.Signature_Policy_Decision
          (Manifest.Signature)
      is
         when Plugins.Capabilities.Signature_Deny_Unsigned =>
            return Plugin_Load_Deny_Unsigned_Manifest;
         when Plugins.Capabilities.Signature_Deny_Untrusted_Key =>
            return Plugin_Load_Deny_Untrusted_Key;
         when Plugins.Capabilities.Signature_Allow =>
            return Plugin_Load_Allow;
      end case;
   end Plugin_Load_Policy_Decision;

   function Plugin_Load_Allowed
     (Manifest : Plugins.Capabilities.Capability_Manifest) return Boolean is
   begin
      return Plugin_Load_Policy_Decision (Manifest) = Plugin_Load_Allow;
   end Plugin_Load_Allowed;

   function Plugin_Tool_Runtime_Decision
      (Manifest       : Plugins.Capabilities.Capability_Manifest;
       Requested_Tool : Plugins.Capabilities.Tool_Kind;
       Operator_Consent : Plugins.Capabilities.Operator_Permission_State)
      return Plugin_Runtime_Decision is
       Tool_Result : constant Plugins.Capabilities.Tool_Access_Result :=
         Plugins.Capabilities.Authorize_Tool_Access
           (Manifest       => Manifest,
            Requested_Tool => Requested_Tool);
   begin
      case Tool_Result.Decision is
          when Plugins.Capabilities.Tool_Access_Deny_Unsigned_Manifest =>
             return Plugin_Runtime_Deny_Unsigned_Manifest;
          when Plugins.Capabilities.Tool_Access_Deny_Untrusted_Key =>
             return Plugin_Runtime_Deny_Untrusted_Key;
          when Plugins.Capabilities.Tool_Access_Deny_Tool_Not_Granted =>
             return Plugin_Runtime_Deny_Tool_Not_Granted;
          when Plugins.Capabilities.Tool_Access_Allow =>
             case Plugins.Capabilities.Operator_Consent_Policy_Decision
                 (Requested_Tool   => Requested_Tool,
                  Operator_Consent => Operator_Consent)
             is
                when Plugins.Capabilities.Operator_Consent_Allow_Not_Required
                  | Plugins.Capabilities.Operator_Consent_Allow_Approved =>
                   return Plugin_Runtime_Allow;
                when Plugins.Capabilities.Operator_Consent_Deny_Missing =>
                   return Plugin_Runtime_Deny_Operator_Consent_Required;
                when Plugins.Capabilities.Operator_Consent_Deny_Explicit =>
                   return Plugin_Runtime_Deny_Operator_Consent_Denied;
             end case;
      end case;
   end Plugin_Tool_Runtime_Decision;

   function Plugin_Tool_Runtime_Decision
     (Manifest       : Plugins.Capabilities.Capability_Manifest;
      Requested_Tool : Plugins.Capabilities.Tool_Kind)
      return Plugin_Runtime_Decision is
   begin
      return Plugin_Tool_Runtime_Decision
        (Manifest         => Manifest,
         Requested_Tool   => Requested_Tool,
         Operator_Consent => Plugins.Capabilities.Operator_Consent_Missing);
   end Plugin_Tool_Runtime_Decision;

   function Plugin_Tool_Runtime_Allowed
     (Manifest         : Plugins.Capabilities.Capability_Manifest;
      Requested_Tool   : Plugins.Capabilities.Tool_Kind;
      Operator_Consent : Plugins.Capabilities.Operator_Permission_State)
      return Boolean is
   begin
      return Plugin_Tool_Runtime_Decision
        (Manifest         => Manifest,
         Requested_Tool   => Requested_Tool,
         Operator_Consent => Operator_Consent) = Plugin_Runtime_Allow;
   end Plugin_Tool_Runtime_Allowed;

   function Plugin_Tool_Runtime_Allowed
      (Manifest       : Plugins.Capabilities.Capability_Manifest;
       Requested_Tool : Plugins.Capabilities.Tool_Kind) return Boolean is
   begin
      return Plugin_Tool_Runtime_Decision
        (Manifest         => Manifest,
         Requested_Tool   => Requested_Tool,
         Operator_Consent => Plugins.Capabilities.Operator_Consent_Missing) =
           Plugin_Runtime_Allow;
   end Plugin_Tool_Runtime_Allowed;

   function Error_For_Decision (Decision : Run_Decision) return Run_Error is
   begin
      case Decision is
         when Run_Allow =>
            return No_Error;
         when Run_Deny_Insecure_Limits =>
            return Insecure_Limits;
         when Run_Deny_Seconds_Exceeded =>
            return Seconds_Exceeded;
         when Run_Deny_Memory_Exceeded =>
            return Memory_Exceeded;
         when Run_Deny_Processes_Exceeded =>
            return Processes_Exceeded;
      end case;
   end Error_For_Decision;

   function Run_Policy_Decision
     (Config               : Limits;
      Requested_Seconds    : Positive;
      Requested_Memory_MB  : Positive;
      Requested_Processes  : Positive) return Run_Decision is
   begin
      if not Limits_Are_Strict (Config) then
         return Run_Deny_Insecure_Limits;
      elsif Requested_Seconds > Config.Max_Seconds then
         return Run_Deny_Seconds_Exceeded;
      elsif Requested_Memory_MB > Config.Max_Memory_MB then
         return Run_Deny_Memory_Exceeded;
      elsif Requested_Processes > Config.Max_Processes then
         return Run_Deny_Processes_Exceeded;
      else
         return Run_Allow;
      end if;
   end Run_Policy_Decision;

   function Supervised_Run_Policy_Decision
     (Config               : Limits;
      Requested_Seconds    : Positive;
      Requested_Memory_MB  : Positive;
      Requested_Processes  : Positive;
      Budget_Available     : Boolean;
      Budget_Remaining     : Natural;
      Actions_Requested    : Positive;
      Cooldown_Active      : Boolean;
      Supervisor_Approved  : Boolean) return Supervised_Run_Decision is
      Autonomy_Decision : constant Security.Policy.Autonomy_Guardrail_Decision :=
        Security.Policy.Autonomy_Guardrail_Policy_Decision
          (Budget_Available    => Budget_Available,
           Budget_Remaining    => Budget_Remaining,
           Actions_Requested   => Actions_Requested,
           Cooldown_Active     => Cooldown_Active,
           Supervisor_Approved => Supervisor_Approved);
   begin
      if Run_Policy_Decision
          (Config              => Config,
           Requested_Seconds   => Requested_Seconds,
           Requested_Memory_MB => Requested_Memory_MB,
           Requested_Processes => Requested_Processes) /= Run_Allow
      then
         return Supervised_Run_Deny_Runtime_Limits;
      end if;

      case Autonomy_Decision is
         when Security.Policy.Autonomy_Allow =>
            return Supervised_Run_Allow;
         when Security.Policy.Autonomy_Deny_Budget_Unavailable =>
            return Supervised_Run_Deny_Budget_Unavailable;
         when Security.Policy.Autonomy_Deny_Budget_Exhausted =>
            return Supervised_Run_Deny_Budget_Exhausted;
         when Security.Policy.Autonomy_Deny_Cooldown_Active =>
            return Supervised_Run_Deny_Cooldown_Active;
          when Security.Policy.Autonomy_Deny_Supervisor_Approval_Required =>
            return Supervised_Run_Deny_Supervisor_Approval_Required;
      end case;
   end Supervised_Run_Policy_Decision;

   function Evaluate_Supervised_Action
     (Config               : Limits;
      Requested_Seconds    : Positive;
      Requested_Memory_MB  : Positive;
      Requested_Processes  : Positive;
      Budget_Available     : Boolean;
      Budget_Remaining     : Natural;
      Actions_Requested    : Positive;
      Cooldown_Active      : Boolean;
      Supervisor_Approved  : Boolean) return Supervised_Action_Result is
      Decision : constant Supervised_Run_Decision :=
        Supervised_Run_Policy_Decision
          (Config              => Config,
           Requested_Seconds   => Requested_Seconds,
           Requested_Memory_MB => Requested_Memory_MB,
           Requested_Processes => Requested_Processes,
           Budget_Available    => Budget_Available,
           Budget_Remaining    => Budget_Remaining,
           Actions_Requested   => Actions_Requested,
           Cooldown_Active     => Cooldown_Active,
           Supervisor_Approved => Supervisor_Approved);
   begin
      return
        (Allowed  => Decision = Supervised_Run_Allow,
         Decision => Decision);
   end Evaluate_Supervised_Action;

   function Can_Run_Supervised
     (Config               : Limits;
      Requested_Seconds    : Positive;
      Requested_Memory_MB  : Positive;
      Requested_Processes  : Positive;
      Budget_Available     : Boolean;
      Budget_Remaining     : Natural;
      Actions_Requested    : Positive;
      Cooldown_Active      : Boolean;
      Supervisor_Approved  : Boolean) return Boolean is
   begin
      return Evaluate_Supervised_Action
         (Config              => Config,
          Requested_Seconds   => Requested_Seconds,
          Requested_Memory_MB => Requested_Memory_MB,
          Requested_Processes => Requested_Processes,
          Budget_Available    => Budget_Available,
          Budget_Remaining    => Budget_Remaining,
          Actions_Requested   => Actions_Requested,
          Cooldown_Active     => Cooldown_Active,
          Supervisor_Approved => Supervisor_Approved).Allowed;
   end Can_Run_Supervised;

   function Can_Run
     (Config               : Limits;
      Requested_Seconds    : Positive;
      Requested_Memory_MB  : Positive;
      Requested_Processes  : Positive) return Boolean is
   begin
      return Run_Policy_Decision
        (Config              => Config,
         Requested_Seconds   => Requested_Seconds,
         Requested_Memory_MB => Requested_Memory_MB,
         Requested_Processes => Requested_Processes) = Run_Allow;
   end Can_Run;
end Runtime.Executor;
