with Channels.Security;
with Plugins.Capabilities;
with Runtime.Executor;

procedure Runtime_Executor_Policy is
   use Channels.Security;
   use Runtime.Executor;

   Default_Limits : constant Limits := (others => <>);
   Insecure_Seconds_Limits : constant Limits :=
     (Max_Seconds => 301, Max_Memory_MB => 256, Max_Processes => 4);
   Insecure_Memory_Limits : constant Limits :=
     (Max_Seconds => 30, Max_Memory_MB => 1025, Max_Processes => 4);
   Insecure_Process_Limits : constant Limits :=
     (Max_Seconds => 30, Max_Memory_MB => 256, Max_Processes => 17);
   Unknown_Backends : constant Sandbox_Backend_Availability :=
     (Availability_Known => False,
      Firejail_Available => False,
      Landlock_Available => False,
      Seccomp_Available  => False);
   Firejail_Only_Backends : constant Sandbox_Backend_Availability :=
     (Availability_Known => True,
      Firejail_Available => True,
      Landlock_Available => False,
      Seccomp_Available  => False);
   Landlock_Only_Backends : constant Sandbox_Backend_Availability :=
     (Availability_Known => True,
      Firejail_Available => False,
      Landlock_Available => True,
      Seccomp_Available  => False);
   Seccomp_Only_Backends : constant Sandbox_Backend_Availability :=
     (Availability_Known => True,
      Firejail_Available => False,
      Landlock_Available => False,
      Seccomp_Available  => True);
   All_Backends : constant Sandbox_Backend_Availability :=
     (Availability_Known => True,
      Firejail_Available => True,
      Landlock_Available => True,
      Seccomp_Available  => True);
   No_Backends : constant Sandbox_Backend_Availability :=
     (Availability_Known => True,
      Firejail_Available => False,
      Landlock_Available => False,
      Seccomp_Available  => False);
   Unsigned_Plugin_Manifest : constant Plugins.Capabilities.Capability_Manifest :=
     (Granted_Tools =>
        (Plugins.Capabilities.Command_Exec_Tool => True, others => False),
      Signature => Plugins.Capabilities.Manifest_Unsigned);
   Untrusted_Plugin_Manifest : constant Plugins.Capabilities.Capability_Manifest :=
     (Granted_Tools =>
        (Plugins.Capabilities.Command_Exec_Tool => True, others => False),
      Signature => Plugins.Capabilities.Manifest_Signed_Untrusted_Key);
   Trusted_Plugin_Manifest : constant Plugins.Capabilities.Capability_Manifest :=
     (Granted_Tools =>
        (Plugins.Capabilities.Command_Exec_Tool => True, others => False),
      Signature => Plugins.Capabilities.Manifest_Signed_Trusted_Key);
   Sandbox_Admission : Sandbox_Run_Admission_Result;
begin
   pragma Assert
     (Limits_Policy_Decision (Default_Limits) = Limits_Allow_Strict);
   pragma Assert (Limits_Are_Strict (Default_Limits));

   pragma Assert
     (Limits_Policy_Decision (Insecure_Seconds_Limits) =
        Limits_Deny_Seconds_Too_High);
   pragma Assert
     (Limits_Policy_Decision (Insecure_Memory_Limits) =
        Limits_Deny_Memory_Too_High);
   pragma Assert
     (Limits_Policy_Decision (Insecure_Process_Limits) =
        Limits_Deny_Processes_Too_High);

   pragma Assert
     (Run_Policy_Decision
        (Config              => Default_Limits,
         Requested_Seconds   => 30,
         Requested_Memory_MB => 256,
         Requested_Processes => 4) = Run_Allow);
   pragma Assert
     (Run_Policy_Decision
        (Config              => Insecure_Seconds_Limits,
         Requested_Seconds   => 1,
         Requested_Memory_MB => 1,
         Requested_Processes => 1) = Run_Deny_Insecure_Limits);
   pragma Assert
     (Run_Policy_Decision
        (Config              => Default_Limits,
         Requested_Seconds   => 31,
         Requested_Memory_MB => 1,
         Requested_Processes => 1) = Run_Deny_Seconds_Exceeded);
   pragma Assert
     (Run_Policy_Decision
        (Config              => Default_Limits,
         Requested_Seconds   => 1,
         Requested_Memory_MB => 257,
         Requested_Processes => 1) = Run_Deny_Memory_Exceeded);
   pragma Assert
     (Run_Policy_Decision
        (Config              => Default_Limits,
         Requested_Seconds   => 1,
         Requested_Memory_MB => 1,
         Requested_Processes => 5) = Run_Deny_Processes_Exceeded);

   pragma Assert (Error_For_Decision (Run_Allow) = No_Error);
   pragma Assert
     (Error_For_Decision (Run_Deny_Insecure_Limits) = Insecure_Limits);
   pragma Assert
     (Error_For_Decision (Run_Deny_Seconds_Exceeded) = Seconds_Exceeded);
   pragma Assert
     (Error_For_Decision (Run_Deny_Memory_Exceeded) = Memory_Exceeded);
   pragma Assert
     (Error_For_Decision (Run_Deny_Processes_Exceeded) = Processes_Exceeded);

   pragma Assert
     (Can_Run
        (Config              => Default_Limits,
         Requested_Seconds   => 30,
         Requested_Memory_MB => 256,
         Requested_Processes => 4));
   pragma Assert
     (not Can_Run
        (Config              => Default_Limits,
         Requested_Seconds   => 31,
         Requested_Memory_MB => 256,
         Requested_Processes => 4));
   pragma Assert
     (not Can_Run
        (Config              => Insecure_Seconds_Limits,
         Requested_Seconds   => 30,
         Requested_Memory_MB => 256,
         Requested_Processes => 4));

   pragma Assert
     (Select_Sandbox_Backend (Sandbox_Backend_Auto, All_Backends) =
        Sandbox_Backend_Landlock);
   pragma Assert
     (Select_Sandbox_Backend (Sandbox_Backend_Auto, Seccomp_Only_Backends) =
        Sandbox_Backend_Seccomp);
   pragma Assert
     (Select_Sandbox_Backend (Sandbox_Backend_Auto, Firejail_Only_Backends) =
        Sandbox_Backend_Firejail);
   pragma Assert
     (Select_Sandbox_Backend (Sandbox_Backend_Auto, No_Backends) =
        Sandbox_Backend_None);
   pragma Assert
     (Select_Sandbox_Backend (Sandbox_Backend_Firejail, Seccomp_Only_Backends) =
        Sandbox_Backend_Unknown);
   pragma Assert
     (Select_Sandbox_Backend (Sandbox_Backend_Auto, Unknown_Backends) =
        Sandbox_Backend_Unknown);

   pragma Assert
     (Sandbox_Backend_Policy_Decision
        (Sandbox_Backend_Auto, Landlock_Only_Backends) =
          Sandbox_Backend_Allow_Landlock);
   pragma Assert
     (Sandbox_Backend_Policy_Decision
        (Sandbox_Backend_Auto, Firejail_Only_Backends) =
          Sandbox_Backend_Allow_Firejail);
   pragma Assert
     (Sandbox_Backend_Policy_Decision
        (Sandbox_Backend_Auto, No_Backends) = Sandbox_Backend_Deny_None);
   pragma Assert
     (Sandbox_Backend_Policy_Decision
        (Sandbox_Backend_Unknown, All_Backends) = Sandbox_Backend_Deny_Unknown);

   pragma Assert
     (Sandbox_Backend_Valid (Sandbox_Backend_Auto, Landlock_Only_Backends));
   pragma Assert
     (not Sandbox_Backend_Valid (Sandbox_Backend_None, Landlock_Only_Backends));
   pragma Assert
     (not Sandbox_Backend_Valid (Sandbox_Backend_Auto, Unknown_Backends));

   pragma Assert
     (Sandbox_Run_Policy_Decision
        (Mode              => Sandbox_Mode_Strict,
         Requested_Backend => Sandbox_Backend_Auto,
         Availability      => Landlock_Only_Backends) = Sandbox_Run_Allow);
   pragma Assert
     (Sandbox_Run_Policy_Decision
        (Mode              => Sandbox_Mode_Compatible,
         Requested_Backend => Sandbox_Backend_Auto,
         Availability      => Firejail_Only_Backends) = Sandbox_Run_Allow);
   pragma Assert
     (Sandbox_Run_Policy_Decision
        (Mode              => Sandbox_Mode_Strict,
         Requested_Backend => Sandbox_Backend_Auto,
         Availability      => Firejail_Only_Backends) =
          Sandbox_Run_Deny_Firejail_Not_Allowed);
   pragma Assert
     (Sandbox_Run_Policy_Decision
        (Mode              => Sandbox_Mode_Compatible,
         Requested_Backend => Sandbox_Backend_Auto,
         Availability      => No_Backends) = Sandbox_Run_Deny_Invalid_Backend);
   pragma Assert
     (Sandbox_Run_Policy_Decision
        (Mode              => Sandbox_Mode_Unsafe,
         Requested_Backend => Sandbox_Backend_Auto,
         Availability      => Landlock_Only_Backends) =
          Sandbox_Run_Deny_Unsafe_Mode);
   pragma Assert
     (Sandbox_Run_Policy_Decision
        (Mode              => Sandbox_Mode_Unknown,
         Requested_Backend => Sandbox_Backend_Auto,
         Availability      => Landlock_Only_Backends) =
           Sandbox_Run_Deny_Unknown_Mode);
   Sandbox_Admission :=
     Evaluate_Sandbox_Run_Admission
       (Mode              => Sandbox_Mode_Strict,
        Requested_Backend => Sandbox_Backend_Auto,
        Availability      => Landlock_Only_Backends);
   pragma Assert
     (Sandbox_Admission.Allowed
      and then Sandbox_Admission.Selected_Backend = Sandbox_Backend_Landlock
      and then Sandbox_Admission.Decision = Sandbox_Run_Allow);
   Sandbox_Admission :=
     Evaluate_Sandbox_Run_Admission
       (Mode              => Sandbox_Mode_Strict,
        Requested_Backend => Sandbox_Backend_Auto,
        Availability      => Firejail_Only_Backends);
   pragma Assert
     ((not Sandbox_Admission.Allowed)
      and then Sandbox_Admission.Selected_Backend = Sandbox_Backend_Firejail
      and then
        Sandbox_Admission.Decision = Sandbox_Run_Deny_Firejail_Not_Allowed);
   Sandbox_Admission :=
     Evaluate_Sandbox_Run_Admission
       (Mode              => Sandbox_Mode_Strict,
        Requested_Backend => Sandbox_Backend_Firejail,
        Availability      => Seccomp_Only_Backends);
   pragma Assert
     ((not Sandbox_Admission.Allowed)
      and then Sandbox_Admission.Selected_Backend = Sandbox_Backend_Unknown
      and then Sandbox_Admission.Decision = Sandbox_Run_Deny_Invalid_Backend);
   Sandbox_Admission :=
     Evaluate_Sandbox_Run_Admission
       (Mode              => Sandbox_Mode_Strict,
        Requested_Backend => Sandbox_Backend_Auto,
        Availability      => Unknown_Backends);
   pragma Assert
     ((not Sandbox_Admission.Allowed)
      and then Sandbox_Admission.Selected_Backend = Sandbox_Backend_Unknown
      and then Sandbox_Admission.Decision = Sandbox_Run_Deny_Invalid_Backend);
   pragma Assert
     (not Can_Run_With_Sandbox
        (Mode              => Sandbox_Mode_Strict,
         Requested_Backend => Sandbox_Backend_Auto,
         Availability      => Firejail_Only_Backends));
   pragma Assert
     (Can_Run_With_Sandbox
         (Mode              => Sandbox_Mode_Strict,
          Requested_Backend => Sandbox_Backend_Auto,
          Availability      => Seccomp_Only_Backends));

   pragma Assert
     (Runtime_Path_Policy_Decision
        (Path_Has_Traversal      => True,
         Targets_Forbidden_Path  => False,
         Restrict_To_Workspace   => True,
         Is_Subpath_Of_Workspace => True) =
           Runtime_Path_Deny_Path_Traversal);
   pragma Assert
     (Runtime_Path_Policy_Decision
        (Path_Has_Traversal      => False,
         Targets_Forbidden_Path  => True,
         Restrict_To_Workspace   => True,
         Is_Subpath_Of_Workspace => True) =
           Runtime_Path_Deny_Forbidden_Path);
   pragma Assert
     (Runtime_Path_Policy_Decision
        (Path_Has_Traversal      => False,
         Targets_Forbidden_Path  => False,
         Restrict_To_Workspace   => True,
         Is_Subpath_Of_Workspace => False) =
           Runtime_Path_Deny_Outside_Workspace_Root);
   pragma Assert
     (Runtime_Path_Policy_Decision
        (Path_Has_Traversal      => False,
         Targets_Forbidden_Path  => False,
         Restrict_To_Workspace   => True,
         Is_Subpath_Of_Workspace => True) = Runtime_Path_Allow);

   pragma Assert
     (Runtime_URL_Policy_Decision
        (Egress_Enabled        => False,
         URL_SSRF_Suspected    => False,
         Targets_Private_Net   => False,
         Targets_Local_Network => False) = Runtime_URL_Deny_Egress_Disabled);
   pragma Assert
     (Runtime_URL_Policy_Decision
        (Egress_Enabled        => True,
         URL_SSRF_Suspected    => True,
         Targets_Private_Net   => False,
         Targets_Local_Network => False) = Runtime_URL_Deny_SSRF);
   pragma Assert
     (Runtime_URL_Policy_Decision
        (Egress_Enabled        => True,
         URL_SSRF_Suspected    => False,
         Targets_Private_Net   => True,
         Targets_Local_Network => False) = Runtime_URL_Deny_Private_Network);
   pragma Assert
     (Runtime_URL_Policy_Decision
        (Egress_Enabled        => True,
         URL_SSRF_Suspected    => False,
         Targets_Private_Net   => False,
         Targets_Local_Network => True) = Runtime_URL_Deny_Local_Network);
   pragma Assert
     (Runtime_URL_Policy_Decision
        (Egress_Enabled        => True,
         URL_SSRF_Suspected    => False,
         Targets_Private_Net   => False,
         Targets_Local_Network => False) = Runtime_URL_Allow);
   pragma Assert
     (Evaluate_Runtime_URL_Admission
        (Egress_Enabled        => False,
         URL_SSRF_Suspected    => False,
         Targets_Private_Net   => False,
         Targets_Local_Network => False).Decision =
            Runtime_URL_Deny_Egress_Disabled);
   pragma Assert
     (Evaluate_Runtime_URL_Admission
        (Egress_Enabled        => True,
         URL_SSRF_Suspected    => True,
         Targets_Private_Net   => False,
         Targets_Local_Network => False).Decision = Runtime_URL_Deny_SSRF);
   pragma Assert
     (Evaluate_Runtime_URL_Admission
        (Egress_Enabled        => True,
         URL_SSRF_Suspected    => False,
         Targets_Private_Net   => True,
         Targets_Local_Network => False).Decision =
            Runtime_URL_Deny_Private_Network);
   pragma Assert
     (Evaluate_Runtime_URL_Admission
        (Egress_Enabled        => True,
         URL_SSRF_Suspected    => False,
         Targets_Private_Net   => False,
         Targets_Local_Network => True).Decision = Runtime_URL_Deny_Local_Network);
   pragma Assert
     (Evaluate_Runtime_URL_Admission
        (Egress_Enabled        => True,
         URL_SSRF_Suspected    => False,
         Targets_Private_Net   => False,
         Targets_Local_Network => False).Decision = Runtime_URL_Allow);

   pragma Assert
     (Runtime_Channel_Allowlist_Policy_Decision
        (Channel              => CLI_Channel,
         Allowlist_Configured => True,
         Allowlist_Enforced   => False,
         Allowlist_Size       => 1,
         Candidate_Matches    => True) = Runtime_Allowlist_Deny_Not_Enforced);
   pragma Assert
     (Runtime_Channel_Allowlist_Policy_Decision
        (Channel              => Webhook_Channel,
         Allowlist_Configured => True,
         Allowlist_Enforced   => True,
         Allowlist_Size       => 0,
         Candidate_Matches    => True) =
           Runtime_Allowlist_Deny_Empty_Allowlist);
   pragma Assert
     (Runtime_Channel_Allowlist_Policy_Decision
        (Channel              => Chat_Channel,
         Allowlist_Configured => True,
         Allowlist_Enforced   => True,
         Allowlist_Size       => 1,
         Candidate_Matches    => False) =
           Runtime_Allowlist_Deny_Not_Allowlisted);
   pragma Assert
     (Runtime_Channel_Allowlist_Policy_Decision
        (Channel              => Chat_Channel,
         Allowlist_Configured => True,
         Allowlist_Enforced   => True,
         Allowlist_Size       => 1,
         Candidate_Matches    => True) = Runtime_Allowlist_Allow);

   pragma Assert
     (Runtime_Admission_Policy_Decision
        (Channel                 => Discord_Channel,
         Allowlist_Configured    => True,
         Allowlist_Enforced      => False,
         Allowlist_Size          => 1,
         Candidate_Matches       => True,
         Path_Has_Traversal      => False,
         Targets_Forbidden_Path  => False,
         Restrict_To_Workspace   => True,
         Is_Subpath_Of_Workspace => True,
         Egress_Enabled          => True,
         URL_SSRF_Suspected      => False,
         Targets_Private_Net     => False,
         Targets_Local_Network   => False) =
           Runtime_Admission_Deny_Allowlist_Not_Enforced);
   pragma Assert
     (Runtime_Admission_Policy_Decision
        (Channel                 => Discord_Channel,
         Allowlist_Configured    => True,
         Allowlist_Enforced      => True,
         Allowlist_Size          => 1,
         Candidate_Matches       => False,
         Path_Has_Traversal      => False,
         Targets_Forbidden_Path  => False,
         Restrict_To_Workspace   => True,
         Is_Subpath_Of_Workspace => True,
         Egress_Enabled          => True,
         URL_SSRF_Suspected      => False,
         Targets_Private_Net     => False,
         Targets_Local_Network   => False) =
           Runtime_Admission_Deny_Channel_Not_Allowlisted);
   pragma Assert
     (Runtime_Admission_Policy_Decision
        (Channel                 => Slack_Channel,
         Allowlist_Configured    => True,
         Allowlist_Enforced      => True,
         Allowlist_Size          => 1,
         Candidate_Matches       => True,
         Path_Has_Traversal      => True,
         Targets_Forbidden_Path  => False,
         Restrict_To_Workspace   => True,
         Is_Subpath_Of_Workspace => True,
         Egress_Enabled          => True,
         URL_SSRF_Suspected      => False,
         Targets_Private_Net     => False,
         Targets_Local_Network   => False) =
           Runtime_Admission_Deny_Path_Traversal);
   pragma Assert
     (Runtime_Admission_Policy_Decision
        (Channel                 => Slack_Channel,
         Allowlist_Configured    => True,
         Allowlist_Enforced      => True,
         Allowlist_Size          => 1,
         Candidate_Matches       => True,
         Path_Has_Traversal      => False,
         Targets_Forbidden_Path  => False,
         Restrict_To_Workspace   => True,
         Is_Subpath_Of_Workspace => True,
         Egress_Enabled          => True,
         URL_SSRF_Suspected      => True,
         Targets_Private_Net     => False,
         Targets_Local_Network   => False) =
            Runtime_Admission_Deny_URL_SSRF);
   pragma Assert
     (Runtime_Admission_Policy_Decision
        (Channel                 => Email_Channel,
         Allowlist_Configured    => True,
         Allowlist_Enforced      => True,
         Allowlist_Size          => 1,
         Candidate_Matches       => True,
         Path_Has_Traversal      => False,
         Targets_Forbidden_Path  => False,
         Restrict_To_Workspace   => True,
         Is_Subpath_Of_Workspace => True,
         Egress_Enabled          => False,
         URL_SSRF_Suspected      => False,
         Targets_Private_Net     => False,
         Targets_Local_Network   => False) =
           Runtime_Admission_Deny_URL_Egress_Disabled);
   pragma Assert
     (Runtime_Admission_Policy_Decision
        (Channel                 => Email_Channel,
         Allowlist_Configured    => True,
         Allowlist_Enforced      => True,
         Allowlist_Size          => 1,
         Candidate_Matches       => True,
         Path_Has_Traversal      => False,
         Targets_Forbidden_Path  => False,
         Restrict_To_Workspace   => True,
         Is_Subpath_Of_Workspace => True,
         Egress_Enabled          => True,
         URL_SSRF_Suspected      => False,
         Targets_Private_Net     => True,
         Targets_Local_Network   => False) =
           Runtime_Admission_Deny_URL_Private_Network);
   pragma Assert
     (Runtime_Admission_Policy_Decision
        (Channel                 => Email_Channel,
         Allowlist_Configured    => True,
         Allowlist_Enforced      => True,
         Allowlist_Size          => 1,
         Candidate_Matches       => True,
         Path_Has_Traversal      => False,
         Targets_Forbidden_Path  => False,
         Restrict_To_Workspace   => True,
         Is_Subpath_Of_Workspace => True,
         Egress_Enabled          => True,
         URL_SSRF_Suspected      => False,
         Targets_Private_Net     => False,
         Targets_Local_Network   => True) =
           Runtime_Admission_Deny_URL_Local_Network);
   pragma Assert
     (Runtime_Admission_Policy_Decision
        (Channel                 => Email_Channel,
         Allowlist_Configured    => True,
         Allowlist_Enforced      => True,
         Allowlist_Size          => 1,
         Candidate_Matches       => True,
         Path_Has_Traversal      => False,
         Targets_Forbidden_Path  => False,
         Restrict_To_Workspace   => True,
         Is_Subpath_Of_Workspace => True,
         Egress_Enabled          => True,
         URL_SSRF_Suspected      => False,
         Targets_Private_Net     => False,
         Targets_Local_Network   => False) = Runtime_Admission_Allow);
   pragma Assert
     (Runtime_Admission_Allowed
        (Channel                 => Email_Channel,
         Allowlist_Configured    => True,
         Allowlist_Enforced      => True,
         Allowlist_Size          => 1,
         Candidate_Matches       => True,
         Path_Has_Traversal      => False,
         Targets_Forbidden_Path  => False,
         Restrict_To_Workspace   => True,
         Is_Subpath_Of_Workspace => True,
         Egress_Enabled          => True,
         URL_SSRF_Suspected      => False,
         Targets_Private_Net     => False,
         Targets_Local_Network   => False));
   pragma Assert
     (not Runtime_Admission_Allowed
        (Channel                 => Email_Channel,
         Allowlist_Configured    => True,
         Allowlist_Enforced      => False,
         Allowlist_Size          => 1,
         Candidate_Matches       => True,
         Path_Has_Traversal      => False,
         Targets_Forbidden_Path  => False,
         Restrict_To_Workspace   => True,
         Is_Subpath_Of_Workspace => True,
         Egress_Enabled          => True,
         URL_SSRF_Suspected      => False,
         Targets_Private_Net     => False,
         Targets_Local_Network   => False));

   pragma Assert
     (Plugin_Load_Policy_Decision (Unsigned_Plugin_Manifest) =
        Plugin_Load_Deny_Unsigned_Manifest);
   pragma Assert
     (Plugin_Load_Policy_Decision (Untrusted_Plugin_Manifest) =
        Plugin_Load_Deny_Untrusted_Key);
   pragma Assert
     (not Plugin_Load_Allowed (Unsigned_Plugin_Manifest));
   pragma Assert
     (not Plugin_Load_Allowed (Untrusted_Plugin_Manifest));
   pragma Assert (Plugin_Load_Allowed (Trusted_Plugin_Manifest));

   pragma Assert
     (Plugin_Tool_Runtime_Decision
        (Manifest       => Unsigned_Plugin_Manifest,
         Requested_Tool => Plugins.Capabilities.Command_Exec_Tool) =
           Plugin_Runtime_Deny_Unsigned_Manifest);
   pragma Assert
     (Plugin_Tool_Runtime_Decision
        (Manifest       => Untrusted_Plugin_Manifest,
         Requested_Tool => Plugins.Capabilities.Command_Exec_Tool) =
           Plugin_Runtime_Deny_Untrusted_Key);
   pragma Assert
     (Plugin_Tool_Runtime_Decision
        (Manifest       => Trusted_Plugin_Manifest,
         Requested_Tool => Plugins.Capabilities.Command_Exec_Tool) =
           Plugin_Runtime_Deny_Operator_Consent_Required);
   pragma Assert
     (Plugin_Tool_Runtime_Decision
        (Manifest         => Trusted_Plugin_Manifest,
         Requested_Tool   => Plugins.Capabilities.Command_Exec_Tool,
         Operator_Consent => Plugins.Capabilities.Operator_Consent_Approved) =
           Plugin_Runtime_Allow);
   pragma Assert
     (Plugin_Tool_Runtime_Decision
        (Manifest         => Trusted_Plugin_Manifest,
         Requested_Tool   => Plugins.Capabilities.Command_Exec_Tool,
         Operator_Consent => Plugins.Capabilities.Operator_Consent_Denied) =
           Plugin_Runtime_Deny_Operator_Consent_Denied);
   pragma Assert
     (Plugin_Tool_Runtime_Decision
        (Manifest         => Trusted_Plugin_Manifest,
         Requested_Tool   => Plugins.Capabilities.Command_Exec_Tool,
         Operator_Consent => Plugins.Capabilities.Operator_Consent_Missing) =
           Plugin_Runtime_Deny_Operator_Consent_Required);
   pragma Assert
     (Plugin_Tool_Runtime_Allowed
        (Manifest         => Trusted_Plugin_Manifest,
         Requested_Tool   => Plugins.Capabilities.Command_Exec_Tool,
         Operator_Consent => Plugins.Capabilities.Operator_Consent_Approved));
   pragma Assert
     (not Plugin_Tool_Runtime_Allowed
        (Manifest         => Trusted_Plugin_Manifest,
         Requested_Tool   => Plugins.Capabilities.Command_Exec_Tool,
         Operator_Consent => Plugins.Capabilities.Operator_Consent_Denied));
   pragma Assert
      (not Plugin_Tool_Runtime_Allowed
         (Manifest       => Trusted_Plugin_Manifest,
          Requested_Tool => Plugins.Capabilities.Network_Fetch_Tool));
end Runtime_Executor_Policy;
