with Gateway.Provider.Credentials;

package Security.Policy with SPARK_Mode is
   use type Gateway.Provider.Credentials.Credential_Decision;
   type Command_Decision is (Allow, Deny);

   type Command_Policy_Decision is
     (Command_Allow_Allowlisted,
      Command_Deny_Empty_Allowlist,
      Command_Deny_Not_Allowlisted);

   function Allowlist_Policy_Decision
     (Allowlist_Size    : Natural;
      Candidate_Matches : Boolean) return Command_Policy_Decision
   with
     Post =>
       (if Allowlist_Size = 0 then
           Allowlist_Policy_Decision'Result = Command_Deny_Empty_Allowlist
        elsif Candidate_Matches then
           Allowlist_Policy_Decision'Result = Command_Allow_Allowlisted
        else
           Allowlist_Policy_Decision'Result = Command_Deny_Not_Allowlisted);

   function Allowlist_Decision
     (Allowlist_Size    : Natural;
      Candidate_Matches : Boolean) return Command_Decision
   with
     Post =>
       (if Allowlist_Policy_Decision (Allowlist_Size, Candidate_Matches) =
             Command_Allow_Allowlisted then
           Allowlist_Decision'Result = Allow
        else
           Allowlist_Decision'Result = Deny);

   type Workspace_Decision is
     (Workspace_Allow,
      Workspace_Deny_Outside_Root);

   function Workspace_Scope_Decision
     (Restrict_To_Workspace : Boolean;
      Is_Subpath            : Boolean) return Workspace_Decision
   with
     Post =>
       (if Restrict_To_Workspace and then not Is_Subpath then
           Workspace_Scope_Decision'Result = Workspace_Deny_Outside_Root
        else
           Workspace_Scope_Decision'Result = Workspace_Allow);

   function Workspace_Path_Allowed
     (Restrict_To_Workspace : Boolean;
      Is_Subpath            : Boolean) return Boolean
   with
     Post =>
       Workspace_Path_Allowed'Result =
         (Workspace_Scope_Decision (Restrict_To_Workspace, Is_Subpath) =
            Workspace_Allow);

   type Egress_Decision is
     (Egress_Allow,
      Egress_Deny_Disabled,
      Egress_Deny_Private_Network,
      Egress_Deny_Local_Network);

   function Outbound_Egress_Decision
     (Egress_Enabled        : Boolean;
      Targets_Private_Net   : Boolean;
      Targets_Local_Network : Boolean) return Egress_Decision
   with
     Post =>
       (if not Egress_Enabled then
           Outbound_Egress_Decision'Result = Egress_Deny_Disabled
        elsif Targets_Private_Net then
           Outbound_Egress_Decision'Result = Egress_Deny_Private_Network
        elsif Targets_Local_Network then
           Outbound_Egress_Decision'Result = Egress_Deny_Local_Network
        else
           Outbound_Egress_Decision'Result = Egress_Allow);

   function Outbound_Egress_Allowed
      (Egress_Enabled        : Boolean;
       Targets_Private_Net   : Boolean;
       Targets_Local_Network : Boolean) return Boolean
   with
     Post =>
        Outbound_Egress_Allowed'Result =
          (Outbound_Egress_Decision
             (Egress_Enabled        => Egress_Enabled,
              Targets_Private_Net   => Targets_Private_Net,
              Targets_Local_Network => Targets_Local_Network) = Egress_Allow);

   type Autonomy_Guardrail_Decision is
     (Autonomy_Allow,
      Autonomy_Deny_Budget_Unavailable,
      Autonomy_Deny_Budget_Exhausted,
      Autonomy_Deny_Cooldown_Active,
      Autonomy_Deny_Supervisor_Approval_Required);

   function Autonomy_Guardrail_Policy_Decision
     (Budget_Available    : Boolean;
      Budget_Remaining    : Natural;
      Actions_Requested   : Positive;
      Cooldown_Active     : Boolean;
      Supervisor_Approved : Boolean) return Autonomy_Guardrail_Decision
   with
     Post =>
       (if not Budget_Available then
           Autonomy_Guardrail_Policy_Decision'Result =
             Autonomy_Deny_Budget_Unavailable
        elsif Actions_Requested > Budget_Remaining then
           Autonomy_Guardrail_Policy_Decision'Result =
             Autonomy_Deny_Budget_Exhausted
        elsif Cooldown_Active then
           Autonomy_Guardrail_Policy_Decision'Result =
             Autonomy_Deny_Cooldown_Active
        elsif not Supervisor_Approved then
           Autonomy_Guardrail_Policy_Decision'Result =
             Autonomy_Deny_Supervisor_Approval_Required
        else
           Autonomy_Guardrail_Policy_Decision'Result = Autonomy_Allow);

   function Autonomy_Guardrail_Allows
     (Budget_Available    : Boolean;
      Budget_Remaining    : Natural;
      Actions_Requested   : Positive;
      Cooldown_Active     : Boolean;
      Supervisor_Approved : Boolean) return Boolean
   with
     Post =>
       Autonomy_Guardrail_Allows'Result =
         (Autonomy_Guardrail_Policy_Decision
            (Budget_Available    => Budget_Available,
             Budget_Remaining    => Budget_Remaining,
             Actions_Requested   => Actions_Requested,
             Cooldown_Active     => Cooldown_Active,
             Supervisor_Approved => Supervisor_Approved) = Autonomy_Allow);

   type Secret_Match_Decision is
     (Secret_Match_Allow,
      Secret_Match_Deny_Host_Mismatch,
      Secret_Match_Deny_Pattern_Mismatch,
      Secret_Match_Deny_Host_And_Pattern_Mismatch);

   function Secret_Match_Policy_Decision
     (Host_Matches    : Boolean;
      Pattern_Matches : Boolean) return Secret_Match_Decision
   with
     Post =>
       (if not Host_Matches and then not Pattern_Matches then
           Secret_Match_Policy_Decision'Result =
             Secret_Match_Deny_Host_And_Pattern_Mismatch
        elsif not Host_Matches then
           Secret_Match_Policy_Decision'Result =
             Secret_Match_Deny_Host_Mismatch
        elsif not Pattern_Matches then
           Secret_Match_Policy_Decision'Result =
             Secret_Match_Deny_Pattern_Mismatch
        else
           Secret_Match_Policy_Decision'Result = Secret_Match_Allow);

   type Secret_Injection_Decision is
     (Secret_Injection_Allow,
      Secret_Injection_Deny_Missing_Token,
      Secret_Injection_Deny_Provider_Mismatch,
      Secret_Injection_Deny_Cross_Provider_Fallback,
      Secret_Injection_Deny_Host_Mismatch,
      Secret_Injection_Deny_Pattern_Mismatch,
      Secret_Injection_Deny_Host_And_Pattern_Mismatch);

   function Secret_Injection_Policy_Decision
     (Credential_Scope : Gateway.Provider.Credentials.Credential_Decision;
      Host_Matches     : Boolean;
      Pattern_Matches  : Boolean) return Secret_Injection_Decision
   with
     Post =>
       (if Credential_Scope =
            Gateway.Provider.Credentials.Credential_Deny_Missing_Token then
           Secret_Injection_Policy_Decision'Result =
             Secret_Injection_Deny_Missing_Token
        elsif Credential_Scope =
            Gateway.Provider.Credentials.Credential_Deny_Provider_Mismatch then
           Secret_Injection_Policy_Decision'Result =
             Secret_Injection_Deny_Provider_Mismatch
        elsif Credential_Scope =
          Gateway.Provider.Credentials.Credential_Deny_Cross_Provider_Fallback
        then
           Secret_Injection_Policy_Decision'Result =
             Secret_Injection_Deny_Cross_Provider_Fallback
        elsif not Host_Matches and then not Pattern_Matches then
           Secret_Injection_Policy_Decision'Result =
             Secret_Injection_Deny_Host_And_Pattern_Mismatch
        elsif not Host_Matches then
           Secret_Injection_Policy_Decision'Result =
             Secret_Injection_Deny_Host_Mismatch
        elsif not Pattern_Matches then
           Secret_Injection_Policy_Decision'Result =
             Secret_Injection_Deny_Pattern_Mismatch
        else
           Secret_Injection_Policy_Decision'Result = Secret_Injection_Allow);

   function Secret_Injection_Allowed
     (Credential_Scope : Gateway.Provider.Credentials.Credential_Decision;
      Host_Matches     : Boolean;
      Pattern_Matches  : Boolean) return Boolean
   with
     Post =>
       Secret_Injection_Allowed'Result =
         (Secret_Injection_Policy_Decision
            (Credential_Scope => Credential_Scope,
             Host_Matches     => Host_Matches,
             Pattern_Matches  => Pattern_Matches) =
              Secret_Injection_Allow);
end Security.Policy;
