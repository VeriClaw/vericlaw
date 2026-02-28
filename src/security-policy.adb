with Gateway.Provider.Credentials;

package body Security.Policy with SPARK_Mode is
   use type Gateway.Provider.Credentials.Credential_Decision;
   function Allowlist_Policy_Decision
     (Allowlist_Size    : Natural;
      Candidate_Matches : Boolean) return Command_Policy_Decision is
   begin
      if Allowlist_Size = 0 then
         return Command_Deny_Empty_Allowlist;
      elsif Candidate_Matches then
         return Command_Allow_Allowlisted;
      else
         return Command_Deny_Not_Allowlisted;
      end if;
   end Allowlist_Policy_Decision;

   function Allowlist_Decision
     (Allowlist_Size    : Natural;
      Candidate_Matches : Boolean) return Command_Decision is
   begin
      if Allowlist_Policy_Decision (Allowlist_Size, Candidate_Matches) =
           Command_Allow_Allowlisted
      then
         return Allow;
      end if;
      return Deny;
   end Allowlist_Decision;

   function Workspace_Scope_Decision
     (Restrict_To_Workspace : Boolean;
      Is_Subpath            : Boolean) return Workspace_Decision is
   begin
      if Restrict_To_Workspace and then not Is_Subpath then
         return Workspace_Deny_Outside_Root;
      end if;
      return Workspace_Allow;
   end Workspace_Scope_Decision;

   function Workspace_Path_Allowed
     (Restrict_To_Workspace : Boolean;
      Is_Subpath            : Boolean) return Boolean is
   begin
      return Workspace_Scope_Decision (Restrict_To_Workspace, Is_Subpath) =
        Workspace_Allow;
   end Workspace_Path_Allowed;

   function Outbound_Egress_Decision
     (Egress_Enabled        : Boolean;
      Targets_Private_Net   : Boolean;
      Targets_Local_Network : Boolean) return Egress_Decision is
   begin
      if not Egress_Enabled then
         return Egress_Deny_Disabled;
      elsif Targets_Private_Net then
         return Egress_Deny_Private_Network;
      elsif Targets_Local_Network then
         return Egress_Deny_Local_Network;
      else
         return Egress_Allow;
      end if;
   end Outbound_Egress_Decision;

   function Outbound_Egress_Allowed
      (Egress_Enabled        : Boolean;
       Targets_Private_Net   : Boolean;
       Targets_Local_Network : Boolean) return Boolean is
   begin
      return
        Outbound_Egress_Decision
          (Egress_Enabled        => Egress_Enabled,
           Targets_Private_Net   => Targets_Private_Net,
           Targets_Local_Network => Targets_Local_Network) = Egress_Allow;
   end Outbound_Egress_Allowed;

   function Autonomy_Guardrail_Policy_Decision
     (Budget_Available    : Boolean;
      Budget_Remaining    : Natural;
      Actions_Requested   : Positive;
      Cooldown_Active     : Boolean;
      Supervisor_Approved : Boolean) return Autonomy_Guardrail_Decision is
   begin
      if not Budget_Available then
         return Autonomy_Deny_Budget_Unavailable;
      elsif Actions_Requested > Budget_Remaining then
         return Autonomy_Deny_Budget_Exhausted;
      elsif Cooldown_Active then
         return Autonomy_Deny_Cooldown_Active;
      elsif not Supervisor_Approved then
         return Autonomy_Deny_Supervisor_Approval_Required;
      end if;
      return Autonomy_Allow;
   end Autonomy_Guardrail_Policy_Decision;

   function Autonomy_Guardrail_Allows
     (Budget_Available    : Boolean;
      Budget_Remaining    : Natural;
      Actions_Requested   : Positive;
      Cooldown_Active     : Boolean;
      Supervisor_Approved : Boolean) return Boolean is
   begin
      return Autonomy_Guardrail_Policy_Decision
        (Budget_Available    => Budget_Available,
         Budget_Remaining    => Budget_Remaining,
         Actions_Requested   => Actions_Requested,
         Cooldown_Active     => Cooldown_Active,
         Supervisor_Approved => Supervisor_Approved) = Autonomy_Allow;
   end Autonomy_Guardrail_Allows;

   function Secret_Match_Policy_Decision
      (Host_Matches    : Boolean;
       Pattern_Matches : Boolean) return Secret_Match_Decision is
   begin
      if not Host_Matches and then not Pattern_Matches then
         return Secret_Match_Deny_Host_And_Pattern_Mismatch;
      elsif not Host_Matches then
         return Secret_Match_Deny_Host_Mismatch;
      elsif not Pattern_Matches then
         return Secret_Match_Deny_Pattern_Mismatch;
      end if;
      return Secret_Match_Allow;
   end Secret_Match_Policy_Decision;

   function Secret_Injection_Policy_Decision
     (Credential_Scope : Gateway.Provider.Credentials.Credential_Decision;
      Host_Matches     : Boolean;
      Pattern_Matches  : Boolean) return Secret_Injection_Decision is
      Match_Decision : constant Secret_Match_Decision :=
        Secret_Match_Policy_Decision
          (Host_Matches    => Host_Matches,
           Pattern_Matches => Pattern_Matches);
   begin
      if Credential_Scope =
          Gateway.Provider.Credentials.Credential_Deny_Missing_Token
      then
         return Secret_Injection_Deny_Missing_Token;
      elsif Credential_Scope =
          Gateway.Provider.Credentials.Credential_Deny_Provider_Mismatch
      then
         return Secret_Injection_Deny_Provider_Mismatch;
      elsif Credential_Scope =
          Gateway.Provider.Credentials.Credential_Deny_Cross_Provider_Fallback
      then
         return Secret_Injection_Deny_Cross_Provider_Fallback;
      end if;

      case Match_Decision is
         when Secret_Match_Allow =>
            return Secret_Injection_Allow;
         when Secret_Match_Deny_Host_Mismatch =>
            return Secret_Injection_Deny_Host_Mismatch;
         when Secret_Match_Deny_Pattern_Mismatch =>
            return Secret_Injection_Deny_Pattern_Mismatch;
         when Secret_Match_Deny_Host_And_Pattern_Mismatch =>
            return Secret_Injection_Deny_Host_And_Pattern_Mismatch;
      end case;
   end Secret_Injection_Policy_Decision;

   function Secret_Injection_Allowed
     (Credential_Scope : Gateway.Provider.Credentials.Credential_Decision;
      Host_Matches     : Boolean;
      Pattern_Matches  : Boolean) return Boolean is
   begin
      return Secret_Injection_Policy_Decision
        (Credential_Scope => Credential_Scope,
         Host_Matches     => Host_Matches,
         Pattern_Matches  => Pattern_Matches) = Secret_Injection_Allow;
   end Secret_Injection_Allowed;
end Security.Policy;
