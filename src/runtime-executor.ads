with Channels.Security;
with Plugins.Capabilities;
with Security.Policy;

package Runtime.Executor with SPARK_Mode is
   use type Security.Policy.Autonomy_Guardrail_Decision;
   use type Plugins.Capabilities.Signature_Decision;
   use type Plugins.Capabilities.Tool_Access_Decision;
   use type Plugins.Capabilities.Operator_Consent_Decision;

   type Limits is record
      Max_Seconds   : Positive := 30;
      Max_Memory_MB : Positive := 256;
      Max_Processes : Positive := 4;
   end record;

   type Limits_Decision is
     (Limits_Allow_Strict,
      Limits_Deny_Seconds_Too_High,
      Limits_Deny_Memory_Too_High,
      Limits_Deny_Processes_Too_High);

   function Limits_Policy_Decision (Config : Limits) return Limits_Decision
   with
     Post =>
       (if Config.Max_Seconds > 300 then
           Limits_Policy_Decision'Result = Limits_Deny_Seconds_Too_High
        elsif Config.Max_Memory_MB > 1024 then
           Limits_Policy_Decision'Result = Limits_Deny_Memory_Too_High
        elsif Config.Max_Processes > 16 then
           Limits_Policy_Decision'Result = Limits_Deny_Processes_Too_High
        else
           Limits_Policy_Decision'Result = Limits_Allow_Strict);

   function Limits_Are_Strict (Config : Limits) return Boolean
   with
     Post =>
       Limits_Are_Strict'Result =
         (Limits_Policy_Decision (Config) = Limits_Allow_Strict);

   type Sandbox_Backend_Label is
     (Sandbox_Backend_Auto,
      Sandbox_Backend_Firejail,
      Sandbox_Backend_Landlock,
      Sandbox_Backend_Seccomp,
      Sandbox_Backend_None,
      Sandbox_Backend_Unknown);

   type Sandbox_Backend_Availability is record
      Availability_Known : Boolean := False;
      Firejail_Available : Boolean := False;
      Landlock_Available : Boolean := False;
      Seccomp_Available  : Boolean := False;
   end record;

   function Select_Sandbox_Backend
     (Requested_Backend : Sandbox_Backend_Label;
      Availability      : Sandbox_Backend_Availability)
      return Sandbox_Backend_Label
   with
     Post =>
       (if not Availability.Availability_Known then
           Select_Sandbox_Backend'Result = Sandbox_Backend_Unknown
        elsif Requested_Backend = Sandbox_Backend_Auto then
           (if Availability.Landlock_Available then
               Select_Sandbox_Backend'Result = Sandbox_Backend_Landlock
            elsif Availability.Seccomp_Available then
               Select_Sandbox_Backend'Result = Sandbox_Backend_Seccomp
            elsif Availability.Firejail_Available then
               Select_Sandbox_Backend'Result = Sandbox_Backend_Firejail
            else
               Select_Sandbox_Backend'Result = Sandbox_Backend_None)
        elsif Requested_Backend = Sandbox_Backend_Firejail then
           (if Availability.Firejail_Available then
               Select_Sandbox_Backend'Result = Sandbox_Backend_Firejail
            else
               Select_Sandbox_Backend'Result = Sandbox_Backend_Unknown)
        elsif Requested_Backend = Sandbox_Backend_Landlock then
           (if Availability.Landlock_Available then
               Select_Sandbox_Backend'Result = Sandbox_Backend_Landlock
            else
               Select_Sandbox_Backend'Result = Sandbox_Backend_Unknown)
        elsif Requested_Backend = Sandbox_Backend_Seccomp then
           (if Availability.Seccomp_Available then
               Select_Sandbox_Backend'Result = Sandbox_Backend_Seccomp
            else
               Select_Sandbox_Backend'Result = Sandbox_Backend_Unknown)
        elsif Requested_Backend = Sandbox_Backend_None then
           Select_Sandbox_Backend'Result = Sandbox_Backend_None
        else
           Select_Sandbox_Backend'Result = Sandbox_Backend_Unknown);

   type Sandbox_Backend_Decision is
     (Sandbox_Backend_Allow_Firejail,
      Sandbox_Backend_Allow_Landlock,
      Sandbox_Backend_Allow_Seccomp,
      Sandbox_Backend_Deny_None,
      Sandbox_Backend_Deny_Unknown);

   function Sandbox_Backend_Policy_Decision
     (Requested_Backend : Sandbox_Backend_Label;
      Availability      : Sandbox_Backend_Availability)
      return Sandbox_Backend_Decision
   with
     Post =>
       (if Select_Sandbox_Backend (Requested_Backend, Availability) =
             Sandbox_Backend_Firejail
        then
           Sandbox_Backend_Policy_Decision'Result =
             Sandbox_Backend_Allow_Firejail
        elsif Select_Sandbox_Backend (Requested_Backend, Availability) =
             Sandbox_Backend_Landlock
        then
           Sandbox_Backend_Policy_Decision'Result =
             Sandbox_Backend_Allow_Landlock
        elsif Select_Sandbox_Backend (Requested_Backend, Availability) =
             Sandbox_Backend_Seccomp
        then
           Sandbox_Backend_Policy_Decision'Result =
             Sandbox_Backend_Allow_Seccomp
        elsif Select_Sandbox_Backend (Requested_Backend, Availability) =
             Sandbox_Backend_None
        then
           Sandbox_Backend_Policy_Decision'Result =
             Sandbox_Backend_Deny_None
        else
           Sandbox_Backend_Policy_Decision'Result =
             Sandbox_Backend_Deny_Unknown);

   function Sandbox_Backend_Valid
     (Requested_Backend : Sandbox_Backend_Label;
      Availability      : Sandbox_Backend_Availability) return Boolean
   with
     Post =>
       Sandbox_Backend_Valid'Result =
         (Sandbox_Backend_Policy_Decision
            (Requested_Backend, Availability) in
              Sandbox_Backend_Allow_Firejail
              | Sandbox_Backend_Allow_Landlock
              | Sandbox_Backend_Allow_Seccomp);

   type Sandbox_Security_Mode is
     (Sandbox_Mode_Strict,
      Sandbox_Mode_Compatible,
      Sandbox_Mode_Unsafe,
      Sandbox_Mode_Unknown);

   type Sandbox_Run_Decision is
     (Sandbox_Run_Allow,
      Sandbox_Run_Deny_Unknown_Mode,
      Sandbox_Run_Deny_Unsafe_Mode,
      Sandbox_Run_Deny_Invalid_Backend,
      Sandbox_Run_Deny_Firejail_Not_Allowed);

   type Sandbox_Run_Admission_Result is record
      Allowed          : Boolean := False;
      Selected_Backend : Sandbox_Backend_Label := Sandbox_Backend_Unknown;
      Decision         : Sandbox_Run_Decision := Sandbox_Run_Deny_Invalid_Backend;
   end record;

   function Evaluate_Sandbox_Run_Admission
     (Mode              : Sandbox_Security_Mode;
      Requested_Backend : Sandbox_Backend_Label;
      Availability      : Sandbox_Backend_Availability)
      return Sandbox_Run_Admission_Result
   with
     Post =>
       (Evaluate_Sandbox_Run_Admission'Result.Selected_Backend =
          Select_Sandbox_Backend (Requested_Backend, Availability))
       and then
       (if Evaluate_Sandbox_Run_Admission'Result.Allowed then
           Evaluate_Sandbox_Run_Admission'Result.Decision = Sandbox_Run_Allow
        else
           Evaluate_Sandbox_Run_Admission'Result.Decision /= Sandbox_Run_Allow);

   function Sandbox_Run_Policy_Decision
     (Mode              : Sandbox_Security_Mode;
      Requested_Backend : Sandbox_Backend_Label;
      Availability      : Sandbox_Backend_Availability)
      return Sandbox_Run_Decision
   with
     Post =>
       (if Mode = Sandbox_Mode_Unknown then
           Sandbox_Run_Policy_Decision'Result =
             Sandbox_Run_Deny_Unknown_Mode
        elsif Mode = Sandbox_Mode_Unsafe then
           Sandbox_Run_Policy_Decision'Result =
             Sandbox_Run_Deny_Unsafe_Mode
        elsif not Sandbox_Backend_Valid (Requested_Backend, Availability) then
           Sandbox_Run_Policy_Decision'Result =
             Sandbox_Run_Deny_Invalid_Backend
        elsif Mode = Sandbox_Mode_Strict
          and then
            Select_Sandbox_Backend (Requested_Backend, Availability) =
              Sandbox_Backend_Firejail
        then
           Sandbox_Run_Policy_Decision'Result =
             Sandbox_Run_Deny_Firejail_Not_Allowed
        else
           Sandbox_Run_Policy_Decision'Result = Sandbox_Run_Allow);

   function Can_Run_With_Sandbox
     (Mode              : Sandbox_Security_Mode;
      Requested_Backend : Sandbox_Backend_Label;
      Availability      : Sandbox_Backend_Availability) return Boolean
   with
     Post =>
       Can_Run_With_Sandbox'Result =
         (Sandbox_Run_Policy_Decision
            (Mode, Requested_Backend, Availability) = Sandbox_Run_Allow);

   type Runtime_Path_Decision is
     (Runtime_Path_Allow,
      Runtime_Path_Deny_Path_Traversal,
      Runtime_Path_Deny_Forbidden_Path,
      Runtime_Path_Deny_Outside_Workspace_Root);

   function Runtime_Path_Policy_Decision
     (Path_Has_Traversal      : Boolean;
      Targets_Forbidden_Path  : Boolean;
      Restrict_To_Workspace   : Boolean;
      Is_Subpath_Of_Workspace : Boolean) return Runtime_Path_Decision
   with
     Post =>
       (if Path_Has_Traversal then
           Runtime_Path_Policy_Decision'Result =
             Runtime_Path_Deny_Path_Traversal
        elsif Targets_Forbidden_Path then
           Runtime_Path_Policy_Decision'Result =
             Runtime_Path_Deny_Forbidden_Path
        elsif Restrict_To_Workspace and then not Is_Subpath_Of_Workspace then
           Runtime_Path_Policy_Decision'Result =
             Runtime_Path_Deny_Outside_Workspace_Root
        else
           Runtime_Path_Policy_Decision'Result = Runtime_Path_Allow);

   type Runtime_URL_Decision is
     (Runtime_URL_Allow,
      Runtime_URL_Deny_Egress_Disabled,
      Runtime_URL_Deny_SSRF,
      Runtime_URL_Deny_Private_Network,
      Runtime_URL_Deny_Local_Network);

   type Runtime_URL_Admission_Result is record
      Allowed  : Boolean := False;
      Decision : Runtime_URL_Decision := Runtime_URL_Deny_Egress_Disabled;
   end record;

   function Evaluate_Runtime_URL_Admission
     (Egress_Enabled        : Boolean;
      URL_SSRF_Suspected    : Boolean;
      Targets_Private_Net   : Boolean;
      Targets_Local_Network : Boolean) return Runtime_URL_Admission_Result
   with
     Post =>
       (if Evaluate_Runtime_URL_Admission'Result.Allowed then
           Evaluate_Runtime_URL_Admission'Result.Decision = Runtime_URL_Allow
        else
           Evaluate_Runtime_URL_Admission'Result.Decision /= Runtime_URL_Allow);

   function Runtime_URL_Policy_Decision
     (Egress_Enabled        : Boolean;
      URL_SSRF_Suspected    : Boolean;
      Targets_Private_Net   : Boolean;
      Targets_Local_Network : Boolean) return Runtime_URL_Decision
   with
     Post =>
       (if not Egress_Enabled then
           Runtime_URL_Policy_Decision'Result =
             Runtime_URL_Deny_Egress_Disabled
        elsif URL_SSRF_Suspected then
           Runtime_URL_Policy_Decision'Result = Runtime_URL_Deny_SSRF
        elsif Targets_Private_Net then
           Runtime_URL_Policy_Decision'Result =
             Runtime_URL_Deny_Private_Network
        elsif Targets_Local_Network then
           Runtime_URL_Policy_Decision'Result = Runtime_URL_Deny_Local_Network
        else
           Runtime_URL_Policy_Decision'Result = Runtime_URL_Allow);

   type Runtime_Allowlist_Decision is
     (Runtime_Allowlist_Allow,
      Runtime_Allowlist_Deny_Not_Enforced,
      Runtime_Allowlist_Deny_Empty_Allowlist,
      Runtime_Allowlist_Deny_Not_Allowlisted);

   function Runtime_Channel_Allowlist_Policy_Decision
     (Channel              : Channels.Security.Channel_Kind;
      Allowlist_Configured : Boolean;
      Allowlist_Enforced   : Boolean;
      Allowlist_Size       : Natural;
      Candidate_Matches    : Boolean) return Runtime_Allowlist_Decision
   with
     Post =>
       (if Allowlist_Configured and then not Allowlist_Enforced then
           Runtime_Channel_Allowlist_Policy_Decision'Result =
             Runtime_Allowlist_Deny_Not_Enforced
        elsif not Allowlist_Enforced then
           Runtime_Channel_Allowlist_Policy_Decision'Result =
             Runtime_Allowlist_Allow
        elsif Allowlist_Size = 0 then
           Runtime_Channel_Allowlist_Policy_Decision'Result =
             Runtime_Allowlist_Deny_Empty_Allowlist
        elsif Candidate_Matches then
           Runtime_Channel_Allowlist_Policy_Decision'Result =
             Runtime_Allowlist_Allow
        else
           Runtime_Channel_Allowlist_Policy_Decision'Result =
             Runtime_Allowlist_Deny_Not_Allowlisted);

   type Runtime_Admission_Decision is
     (Runtime_Admission_Allow,
      Runtime_Admission_Deny_Allowlist_Not_Enforced,
      Runtime_Admission_Deny_Channel_Empty_Allowlist,
      Runtime_Admission_Deny_Channel_Not_Allowlisted,
      Runtime_Admission_Deny_Path_Traversal,
      Runtime_Admission_Deny_Forbidden_Path,
      Runtime_Admission_Deny_Outside_Workspace_Root,
      Runtime_Admission_Deny_URL_Egress_Disabled,
      Runtime_Admission_Deny_URL_SSRF,
      Runtime_Admission_Deny_URL_Private_Network,
      Runtime_Admission_Deny_URL_Local_Network);

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
      Targets_Local_Network   : Boolean) return Runtime_Admission_Decision
   with
     Post =>
       (if Runtime_Channel_Allowlist_Policy_Decision
             (Channel              => Channel,
              Allowlist_Configured => Allowlist_Configured,
              Allowlist_Enforced   => Allowlist_Enforced,
              Allowlist_Size       => Allowlist_Size,
              Candidate_Matches    => Candidate_Matches) =
             Runtime_Allowlist_Deny_Not_Enforced
        then
           Runtime_Admission_Policy_Decision'Result =
             Runtime_Admission_Deny_Allowlist_Not_Enforced
        elsif Runtime_Channel_Allowlist_Policy_Decision
            (Channel              => Channel,
             Allowlist_Configured => Allowlist_Configured,
             Allowlist_Enforced   => Allowlist_Enforced,
             Allowlist_Size       => Allowlist_Size,
             Candidate_Matches    => Candidate_Matches) =
              Runtime_Allowlist_Deny_Empty_Allowlist
        then
           Runtime_Admission_Policy_Decision'Result =
             Runtime_Admission_Deny_Channel_Empty_Allowlist
        elsif Runtime_Channel_Allowlist_Policy_Decision
            (Channel              => Channel,
             Allowlist_Configured => Allowlist_Configured,
             Allowlist_Enforced   => Allowlist_Enforced,
             Allowlist_Size       => Allowlist_Size,
             Candidate_Matches    => Candidate_Matches) =
              Runtime_Allowlist_Deny_Not_Allowlisted
        then
           Runtime_Admission_Policy_Decision'Result =
             Runtime_Admission_Deny_Channel_Not_Allowlisted
        elsif Runtime_Path_Policy_Decision
            (Path_Has_Traversal      => Path_Has_Traversal,
             Targets_Forbidden_Path  => Targets_Forbidden_Path,
             Restrict_To_Workspace   => Restrict_To_Workspace,
             Is_Subpath_Of_Workspace => Is_Subpath_Of_Workspace) =
              Runtime_Path_Deny_Path_Traversal
        then
           Runtime_Admission_Policy_Decision'Result =
             Runtime_Admission_Deny_Path_Traversal
        elsif Runtime_Path_Policy_Decision
            (Path_Has_Traversal      => Path_Has_Traversal,
             Targets_Forbidden_Path  => Targets_Forbidden_Path,
             Restrict_To_Workspace   => Restrict_To_Workspace,
             Is_Subpath_Of_Workspace => Is_Subpath_Of_Workspace) =
              Runtime_Path_Deny_Forbidden_Path
        then
           Runtime_Admission_Policy_Decision'Result =
             Runtime_Admission_Deny_Forbidden_Path
        elsif Runtime_Path_Policy_Decision
            (Path_Has_Traversal      => Path_Has_Traversal,
             Targets_Forbidden_Path  => Targets_Forbidden_Path,
             Restrict_To_Workspace   => Restrict_To_Workspace,
             Is_Subpath_Of_Workspace => Is_Subpath_Of_Workspace) =
              Runtime_Path_Deny_Outside_Workspace_Root
        then
           Runtime_Admission_Policy_Decision'Result =
             Runtime_Admission_Deny_Outside_Workspace_Root
        elsif Runtime_URL_Policy_Decision
            (Egress_Enabled        => Egress_Enabled,
             URL_SSRF_Suspected    => URL_SSRF_Suspected,
             Targets_Private_Net   => Targets_Private_Net,
             Targets_Local_Network => Targets_Local_Network) =
              Runtime_URL_Deny_Egress_Disabled
        then
           Runtime_Admission_Policy_Decision'Result =
             Runtime_Admission_Deny_URL_Egress_Disabled
        elsif Runtime_URL_Policy_Decision
            (Egress_Enabled        => Egress_Enabled,
             URL_SSRF_Suspected    => URL_SSRF_Suspected,
             Targets_Private_Net   => Targets_Private_Net,
             Targets_Local_Network => Targets_Local_Network) =
              Runtime_URL_Deny_SSRF
        then
           Runtime_Admission_Policy_Decision'Result =
             Runtime_Admission_Deny_URL_SSRF
        elsif Runtime_URL_Policy_Decision
            (Egress_Enabled        => Egress_Enabled,
             URL_SSRF_Suspected    => URL_SSRF_Suspected,
             Targets_Private_Net   => Targets_Private_Net,
             Targets_Local_Network => Targets_Local_Network) =
              Runtime_URL_Deny_Private_Network
        then
           Runtime_Admission_Policy_Decision'Result =
             Runtime_Admission_Deny_URL_Private_Network
        elsif Runtime_URL_Policy_Decision
            (Egress_Enabled        => Egress_Enabled,
             URL_SSRF_Suspected    => URL_SSRF_Suspected,
             Targets_Private_Net   => Targets_Private_Net,
             Targets_Local_Network => Targets_Local_Network) =
              Runtime_URL_Deny_Local_Network
        then
           Runtime_Admission_Policy_Decision'Result =
             Runtime_Admission_Deny_URL_Local_Network
        else
           Runtime_Admission_Policy_Decision'Result =
             Runtime_Admission_Allow);

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
      Targets_Local_Network   : Boolean) return Boolean
   with
      Post =>
        Runtime_Admission_Allowed'Result =
          (Runtime_Admission_Policy_Decision
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
               Runtime_Admission_Allow);

   type Plugin_Load_Decision is
     (Plugin_Load_Allow,
      Plugin_Load_Deny_Unsigned_Manifest,
      Plugin_Load_Deny_Untrusted_Key);

   function Plugin_Load_Policy_Decision
     (Manifest : Plugins.Capabilities.Capability_Manifest)
      return Plugin_Load_Decision
   with
     Post =>
       (if Plugins.Capabilities.Signature_Policy_Decision
             (Manifest.Signature) =
               Plugins.Capabilities.Signature_Deny_Unsigned
        then
           Plugin_Load_Policy_Decision'Result =
             Plugin_Load_Deny_Unsigned_Manifest
        elsif Plugins.Capabilities.Signature_Policy_Decision
            (Manifest.Signature) =
              Plugins.Capabilities.Signature_Deny_Untrusted_Key
        then
           Plugin_Load_Policy_Decision'Result = Plugin_Load_Deny_Untrusted_Key
        else
           Plugin_Load_Policy_Decision'Result = Plugin_Load_Allow);

   function Plugin_Load_Allowed
     (Manifest : Plugins.Capabilities.Capability_Manifest) return Boolean
   with
     Post =>
       Plugin_Load_Allowed'Result =
         (Plugin_Load_Policy_Decision (Manifest) = Plugin_Load_Allow);

   type Plugin_Runtime_Decision is
      (Plugin_Runtime_Allow,
       Plugin_Runtime_Deny_Unsigned_Manifest,
       Plugin_Runtime_Deny_Untrusted_Key,
       Plugin_Runtime_Deny_Tool_Not_Granted,
       Plugin_Runtime_Deny_Operator_Consent_Required,
       Plugin_Runtime_Deny_Operator_Consent_Denied);

   function Plugin_Tool_Runtime_Decision
      (Manifest       : Plugins.Capabilities.Capability_Manifest;
       Requested_Tool : Plugins.Capabilities.Tool_Kind;
       Operator_Consent : Plugins.Capabilities.Operator_Permission_State)
      return Plugin_Runtime_Decision
   with
      Post =>
        (if Plugins.Capabilities.Authorize_Tool_Access
             (Manifest       => Manifest,
              Requested_Tool => Requested_Tool).Decision =
               Plugins.Capabilities.Tool_Access_Deny_Unsigned_Manifest
        then
           Plugin_Tool_Runtime_Decision'Result =
             Plugin_Runtime_Deny_Unsigned_Manifest
        elsif Plugins.Capabilities.Authorize_Tool_Access
            (Manifest       => Manifest,
             Requested_Tool => Requested_Tool).Decision =
               Plugins.Capabilities.Tool_Access_Deny_Untrusted_Key
        then
           Plugin_Tool_Runtime_Decision'Result =
             Plugin_Runtime_Deny_Untrusted_Key
         elsif Plugins.Capabilities.Authorize_Tool_Access
             (Manifest       => Manifest,
              Requested_Tool => Requested_Tool).Decision =
                Plugins.Capabilities.Tool_Access_Deny_Tool_Not_Granted
         then
            Plugin_Tool_Runtime_Decision'Result =
              Plugin_Runtime_Deny_Tool_Not_Granted
         elsif Plugins.Capabilities.Operator_Consent_Policy_Decision
             (Requested_Tool   => Requested_Tool,
              Operator_Consent => Operator_Consent) =
               Plugins.Capabilities.Operator_Consent_Deny_Missing
         then
            Plugin_Tool_Runtime_Decision'Result =
              Plugin_Runtime_Deny_Operator_Consent_Required
         elsif Plugins.Capabilities.Operator_Consent_Policy_Decision
             (Requested_Tool   => Requested_Tool,
              Operator_Consent => Operator_Consent) =
               Plugins.Capabilities.Operator_Consent_Deny_Explicit
         then
            Plugin_Tool_Runtime_Decision'Result =
              Plugin_Runtime_Deny_Operator_Consent_Denied
         else
            Plugin_Tool_Runtime_Decision'Result = Plugin_Runtime_Allow);

   function Plugin_Tool_Runtime_Decision
     (Manifest       : Plugins.Capabilities.Capability_Manifest;
      Requested_Tool : Plugins.Capabilities.Tool_Kind)
      return Plugin_Runtime_Decision
   with
     Post =>
       Plugin_Tool_Runtime_Decision'Result =
         Plugin_Tool_Runtime_Decision
           (Manifest         => Manifest,
            Requested_Tool   => Requested_Tool,
            Operator_Consent => Plugins.Capabilities.Operator_Consent_Missing);

   function Plugin_Tool_Runtime_Allowed
     (Manifest         : Plugins.Capabilities.Capability_Manifest;
      Requested_Tool   : Plugins.Capabilities.Tool_Kind;
      Operator_Consent : Plugins.Capabilities.Operator_Permission_State)
      return Boolean
   with
     Post =>
       Plugin_Tool_Runtime_Allowed'Result =
         (Plugin_Tool_Runtime_Decision
            (Manifest         => Manifest,
             Requested_Tool   => Requested_Tool,
             Operator_Consent => Operator_Consent) = Plugin_Runtime_Allow);

   function Plugin_Tool_Runtime_Allowed
      (Manifest       : Plugins.Capabilities.Capability_Manifest;
       Requested_Tool : Plugins.Capabilities.Tool_Kind) return Boolean
    with
      Post =>
        Plugin_Tool_Runtime_Allowed'Result =
          (Plugin_Tool_Runtime_Decision
             (Manifest         => Manifest,
              Requested_Tool   => Requested_Tool,
              Operator_Consent =>
                Plugins.Capabilities.Operator_Consent_Missing) =
               Plugin_Runtime_Allow);

   type Run_Decision is
     (Run_Allow,
      Run_Deny_Insecure_Limits,
      Run_Deny_Seconds_Exceeded,
      Run_Deny_Memory_Exceeded,
      Run_Deny_Processes_Exceeded);

   type Supervised_Run_Decision is
     (Supervised_Run_Allow,
      Supervised_Run_Deny_Runtime_Limits,
      Supervised_Run_Deny_Budget_Unavailable,
      Supervised_Run_Deny_Budget_Exhausted,
      Supervised_Run_Deny_Cooldown_Active,
      Supervised_Run_Deny_Supervisor_Approval_Required);

   type Supervised_Action_Result is record
      Allowed  : Boolean := False;
      Decision : Supervised_Run_Decision := Supervised_Run_Deny_Runtime_Limits;
   end record;

   type Run_Error is
     (No_Error,
      Insecure_Limits,
      Seconds_Exceeded,
      Memory_Exceeded,
      Processes_Exceeded);

   function Error_For_Decision (Decision : Run_Decision) return Run_Error
   with
     Post =>
       (if Decision = Run_Allow then
           Error_For_Decision'Result = No_Error
        elsif Decision = Run_Deny_Insecure_Limits then
           Error_For_Decision'Result = Insecure_Limits
        elsif Decision = Run_Deny_Seconds_Exceeded then
           Error_For_Decision'Result = Seconds_Exceeded
        elsif Decision = Run_Deny_Memory_Exceeded then
           Error_For_Decision'Result = Memory_Exceeded
        else
           Error_For_Decision'Result = Processes_Exceeded);

   function Run_Policy_Decision
     (Config               : Limits;
      Requested_Seconds    : Positive;
      Requested_Memory_MB  : Positive;
      Requested_Processes  : Positive) return Run_Decision
   with
     Post =>
       (if not Limits_Are_Strict (Config) then
           Run_Policy_Decision'Result = Run_Deny_Insecure_Limits
        elsif Requested_Seconds > Config.Max_Seconds then
           Run_Policy_Decision'Result = Run_Deny_Seconds_Exceeded
        elsif Requested_Memory_MB > Config.Max_Memory_MB then
           Run_Policy_Decision'Result = Run_Deny_Memory_Exceeded
         elsif Requested_Processes > Config.Max_Processes then
            Run_Policy_Decision'Result = Run_Deny_Processes_Exceeded
         else
            Run_Policy_Decision'Result = Run_Allow);

   function Supervised_Run_Policy_Decision
      (Config               : Limits;
       Requested_Seconds    : Positive;
       Requested_Memory_MB  : Positive;
       Requested_Processes  : Positive;
      Budget_Available     : Boolean;
      Budget_Remaining     : Natural;
      Actions_Requested    : Positive;
      Cooldown_Active      : Boolean;
      Supervisor_Approved  : Boolean) return Supervised_Run_Decision
   with
     Post =>
       (if Run_Policy_Decision
             (Config              => Config,
              Requested_Seconds   => Requested_Seconds,
              Requested_Memory_MB => Requested_Memory_MB,
              Requested_Processes => Requested_Processes) /= Run_Allow
        then
           Supervised_Run_Policy_Decision'Result =
             Supervised_Run_Deny_Runtime_Limits
        elsif Security.Policy.Autonomy_Guardrail_Policy_Decision
            (Budget_Available    => Budget_Available,
             Budget_Remaining    => Budget_Remaining,
             Actions_Requested   => Actions_Requested,
             Cooldown_Active     => Cooldown_Active,
             Supervisor_Approved => Supervisor_Approved) =
             Security.Policy.Autonomy_Deny_Budget_Unavailable
        then
           Supervised_Run_Policy_Decision'Result =
             Supervised_Run_Deny_Budget_Unavailable
        elsif Security.Policy.Autonomy_Guardrail_Policy_Decision
            (Budget_Available    => Budget_Available,
             Budget_Remaining    => Budget_Remaining,
             Actions_Requested   => Actions_Requested,
             Cooldown_Active     => Cooldown_Active,
             Supervisor_Approved => Supervisor_Approved) =
             Security.Policy.Autonomy_Deny_Budget_Exhausted
        then
           Supervised_Run_Policy_Decision'Result =
             Supervised_Run_Deny_Budget_Exhausted
        elsif Security.Policy.Autonomy_Guardrail_Policy_Decision
            (Budget_Available    => Budget_Available,
             Budget_Remaining    => Budget_Remaining,
             Actions_Requested   => Actions_Requested,
             Cooldown_Active     => Cooldown_Active,
             Supervisor_Approved => Supervisor_Approved) =
             Security.Policy.Autonomy_Deny_Cooldown_Active
        then
           Supervised_Run_Policy_Decision'Result =
             Supervised_Run_Deny_Cooldown_Active
        elsif Security.Policy.Autonomy_Guardrail_Policy_Decision
            (Budget_Available    => Budget_Available,
             Budget_Remaining    => Budget_Remaining,
             Actions_Requested   => Actions_Requested,
             Cooldown_Active     => Cooldown_Active,
             Supervisor_Approved => Supervisor_Approved) =
             Security.Policy.Autonomy_Deny_Supervisor_Approval_Required
        then
           Supervised_Run_Policy_Decision'Result =
             Supervised_Run_Deny_Supervisor_Approval_Required
         else
            Supervised_Run_Policy_Decision'Result = Supervised_Run_Allow);

   function Evaluate_Supervised_Action
     (Config               : Limits;
      Requested_Seconds    : Positive;
      Requested_Memory_MB  : Positive;
      Requested_Processes  : Positive;
      Budget_Available     : Boolean;
      Budget_Remaining     : Natural;
      Actions_Requested    : Positive;
      Cooldown_Active      : Boolean;
      Supervisor_Approved  : Boolean) return Supervised_Action_Result
   with
     Post =>
       (if Evaluate_Supervised_Action'Result.Allowed then
           Evaluate_Supervised_Action'Result.Decision = Supervised_Run_Allow
        else
           Evaluate_Supervised_Action'Result.Decision /= Supervised_Run_Allow);

   function Can_Run_Supervised
      (Config               : Limits;
       Requested_Seconds    : Positive;
      Requested_Memory_MB  : Positive;
      Requested_Processes  : Positive;
      Budget_Available     : Boolean;
      Budget_Remaining     : Natural;
      Actions_Requested    : Positive;
      Cooldown_Active      : Boolean;
      Supervisor_Approved  : Boolean) return Boolean
   with
     Post =>
       Can_Run_Supervised'Result =
         (Supervised_Run_Policy_Decision
            (Config              => Config,
             Requested_Seconds   => Requested_Seconds,
             Requested_Memory_MB => Requested_Memory_MB,
             Requested_Processes => Requested_Processes,
             Budget_Available    => Budget_Available,
             Budget_Remaining    => Budget_Remaining,
             Actions_Requested   => Actions_Requested,
             Cooldown_Active     => Cooldown_Active,
             Supervisor_Approved => Supervisor_Approved) =
            Supervised_Run_Allow);

   function Can_Run
     (Config               : Limits;
      Requested_Seconds    : Positive;
      Requested_Memory_MB  : Positive;
      Requested_Processes  : Positive) return Boolean
   with
     Post =>
       Can_Run'Result =
         (Run_Policy_Decision
            (Config              => Config,
             Requested_Seconds   => Requested_Seconds,
             Requested_Memory_MB => Requested_Memory_MB,
             Requested_Processes => Requested_Processes) = Run_Allow);
end Runtime.Executor;
