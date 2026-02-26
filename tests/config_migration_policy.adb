with Security.Defaults;
with Security.Migration;

procedure Config_Migration_Policy is
   use Security.Migration;

   Hardened_Input : constant External_Config_Pattern :=
     (Gateway_Host  => Host_Local_Only,
      Public_Bind   => Public_Bind_Disabled,
      Pairing       => Pairing_Required,
      Allowlist     => Allowlist_Required,
      Workspace     => Workspace_Restricted,
      Observability => Observability_None);

   Unsafe_Input : constant External_Config_Pattern :=
     (Gateway_Host  => Host_Public_Wildcard,
      Public_Bind   => Public_Bind_Enabled,
      Pairing       => Pairing_Disabled,
      Allowlist     => Allowlist_Disabled,
      Workspace     => Workspace_Unrestricted,
      Observability => Observability_Remote_Exporter);

   Ambiguous_Input : constant External_Config_Pattern := (others => <>);

   Report : Migration_Report;
begin
   Report := Migrate (Hardened_Input);
   pragma Assert
     (Report.Config.Gateway_Bind_Host = Security.Defaults.Gateway_Bind_Host);
   pragma Assert
     (Report.Config.Allow_Public_Bind =
        Security.Defaults.Allow_Public_Bind_Default);
   pragma Assert
     (Report.Config.Require_Pairing = Security.Defaults.Require_Pairing_Default);
   pragma Assert (Report.Config.Empty_Allowlist_Denies_All);
   pragma Assert
     (Report.Config.Restrict_Tool_To_Workspace =
        Security.Defaults.Workspace_Only_Default);
   pragma Assert
     (Report.Config.Observability_Backend =
        Security.Defaults.Observability_Backend_Default);

   pragma Assert (Report.Gateway_Host_Decision = Mapped_Secure_Input);
   pragma Assert (Report.Public_Bind_Decision = Mapped_Secure_Input);
   pragma Assert (Report.Pairing_Decision = Mapped_Secure_Input);
   pragma Assert (Report.Allowlist_Decision = Mapped_Secure_Input);
   pragma Assert (Report.Workspace_Decision = Mapped_Secure_Input);
   pragma Assert (Report.Observability_Decision = Mapped_Secure_Input);

   Report := Migrate (Unsafe_Input);
   pragma Assert
     (Report.Config.Gateway_Bind_Host = Security.Defaults.Gateway_Bind_Host);
   pragma Assert
     (Report.Config.Allow_Public_Bind =
        Security.Defaults.Allow_Public_Bind_Default);
   pragma Assert
     (Report.Config.Require_Pairing = Security.Defaults.Require_Pairing_Default);
   pragma Assert (Report.Config.Empty_Allowlist_Denies_All);
   pragma Assert
     (Report.Config.Restrict_Tool_To_Workspace =
        Security.Defaults.Workspace_Only_Default);
   pragma Assert
     (Report.Config.Observability_Backend =
        Security.Defaults.Observability_Backend_Default);

   pragma Assert (Report.Gateway_Host_Decision = Forced_Secure_Default);
   pragma Assert (Report.Public_Bind_Decision = Forced_Secure_Default);
   pragma Assert (Report.Pairing_Decision = Forced_Secure_Default);
   pragma Assert (Report.Allowlist_Decision = Forced_Secure_Default);
   pragma Assert (Report.Workspace_Decision = Forced_Secure_Default);
   pragma Assert (Report.Observability_Decision = Forced_Secure_Default);

   Report := Migrate (Ambiguous_Input);
   pragma Assert (Report.Gateway_Host_Decision = Forced_Secure_Default);
   pragma Assert (Report.Public_Bind_Decision = Forced_Secure_Default);
   pragma Assert (Report.Pairing_Decision = Forced_Secure_Default);
   pragma Assert (Report.Allowlist_Decision = Forced_Secure_Default);
   pragma Assert (Report.Workspace_Decision = Forced_Secure_Default);
   pragma Assert (Report.Observability_Decision = Forced_Secure_Default);

   pragma Assert
     (Migrate_Gateway_Bind_Host (Host_Private_Interface) =
        Security.Defaults.Gateway_Bind_Host);
   pragma Assert
     (Migrate_Allow_Public_Bind (Public_Bind_Enabled) =
        Security.Defaults.Allow_Public_Bind_Default);
   pragma Assert
     (Migrate_Require_Pairing (Pairing_Disabled) =
        Security.Defaults.Require_Pairing_Default);
   pragma Assert (Migrate_Empty_Allowlist_Denies_All (Allowlist_Disabled));
   pragma Assert
     (Migrate_Workspace_Restriction (Workspace_Unrestricted) =
        Security.Defaults.Workspace_Only_Default);
   pragma Assert
     (Migrate_Observability_Backend (Observability_Remote_Exporter) =
        Security.Defaults.Observability_Backend_Default);
end Config_Migration_Policy;
