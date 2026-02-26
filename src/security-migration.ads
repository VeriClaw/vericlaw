with Security.Defaults;

package Security.Migration with SPARK_Mode is
   subtype Gateway_Host_String is
     String (1 .. Security.Defaults.Gateway_Bind_Host'Length);
   subtype Observability_Backend_String is
     String (1 .. Security.Defaults.Observability_Backend_Default'Length);

   type External_Gateway_Host_Pattern is
     (Host_Local_Only,
      Host_Public_Wildcard,
      Host_Private_Interface,
      Host_Ambiguous);

   type External_Public_Bind_Pattern is
     (Public_Bind_Disabled,
      Public_Bind_Enabled,
      Public_Bind_Ambiguous);

   type External_Pairing_Pattern is
     (Pairing_Required,
      Pairing_Disabled,
      Pairing_Ambiguous);

   type External_Allowlist_Pattern is
     (Allowlist_Required,
      Allowlist_Disabled,
      Allowlist_Ambiguous);

   type External_Workspace_Pattern is
     (Workspace_Restricted,
      Workspace_Unrestricted,
      Workspace_Ambiguous);

   type External_Observability_Pattern is
     (Observability_None,
      Observability_Remote_Exporter,
      Observability_Ambiguous);

   type External_Config_Pattern is record
      Gateway_Host  : External_Gateway_Host_Pattern := Host_Ambiguous;
      Public_Bind   : External_Public_Bind_Pattern := Public_Bind_Ambiguous;
      Pairing       : External_Pairing_Pattern := Pairing_Ambiguous;
      Allowlist     : External_Allowlist_Pattern := Allowlist_Ambiguous;
      Workspace     : External_Workspace_Pattern := Workspace_Ambiguous;
      Observability : External_Observability_Pattern := Observability_Ambiguous;
   end record;

   type Migration_Decision is
     (Mapped_Secure_Input,
      Forced_Secure_Default);

   type Vericlaw_Config is record
      Gateway_Bind_Host          : Gateway_Host_String :=
        Security.Defaults.Gateway_Bind_Host;
      Allow_Public_Bind          : Boolean :=
        Security.Defaults.Allow_Public_Bind_Default;
      Require_Pairing            : Boolean :=
        Security.Defaults.Require_Pairing_Default;
      Empty_Allowlist_Denies_All : Boolean := True;
      Restrict_Tool_To_Workspace : Boolean :=
        Security.Defaults.Workspace_Only_Default;
      Observability_Backend      : Observability_Backend_String :=
        Security.Defaults.Observability_Backend_Default;
   end record;

   type Migration_Report is record
      Config                 : Vericlaw_Config := (others => <>);
      Gateway_Host_Decision  : Migration_Decision := Forced_Secure_Default;
      Public_Bind_Decision   : Migration_Decision := Forced_Secure_Default;
      Pairing_Decision       : Migration_Decision := Forced_Secure_Default;
      Allowlist_Decision     : Migration_Decision := Forced_Secure_Default;
      Workspace_Decision     : Migration_Decision := Forced_Secure_Default;
      Observability_Decision : Migration_Decision := Forced_Secure_Default;
   end record;

   function Migrate_Gateway_Bind_Host
     (Pattern : External_Gateway_Host_Pattern) return Gateway_Host_String
   with
     Post =>
       Migrate_Gateway_Bind_Host'Result = Security.Defaults.Gateway_Bind_Host;

   function Migrate_Allow_Public_Bind
     (Pattern : External_Public_Bind_Pattern) return Boolean
   with
     Post =>
       Migrate_Allow_Public_Bind'Result =
         Security.Defaults.Allow_Public_Bind_Default;

   function Migrate_Require_Pairing
     (Pattern : External_Pairing_Pattern) return Boolean
   with
     Post =>
       Migrate_Require_Pairing'Result =
         Security.Defaults.Require_Pairing_Default;

   function Migrate_Empty_Allowlist_Denies_All
     (Pattern : External_Allowlist_Pattern) return Boolean
   with
     Post => Migrate_Empty_Allowlist_Denies_All'Result;

   function Migrate_Workspace_Restriction
     (Pattern : External_Workspace_Pattern) return Boolean
   with
     Post =>
       Migrate_Workspace_Restriction'Result =
         Security.Defaults.Workspace_Only_Default;

   function Migrate_Observability_Backend
     (Pattern : External_Observability_Pattern)
      return Observability_Backend_String
   with
     Post =>
       Migrate_Observability_Backend'Result =
         Security.Defaults.Observability_Backend_Default;

   function Gateway_Host_Migration_Decision
     (Pattern : External_Gateway_Host_Pattern) return Migration_Decision;

   function Public_Bind_Migration_Decision
     (Pattern : External_Public_Bind_Pattern) return Migration_Decision;

   function Pairing_Migration_Decision
     (Pattern : External_Pairing_Pattern) return Migration_Decision;

   function Allowlist_Migration_Decision
     (Pattern : External_Allowlist_Pattern) return Migration_Decision;

   function Workspace_Migration_Decision
     (Pattern : External_Workspace_Pattern) return Migration_Decision;

   function Observability_Migration_Decision
     (Pattern : External_Observability_Pattern) return Migration_Decision;

   function Migrate (Input : External_Config_Pattern) return Migration_Report
   with
     Post =>
       (Migrate'Result.Config.Gateway_Bind_Host =
          Security.Defaults.Gateway_Bind_Host
        and then
          Migrate'Result.Config.Allow_Public_Bind =
            Security.Defaults.Allow_Public_Bind_Default
        and then
          Migrate'Result.Config.Require_Pairing =
            Security.Defaults.Require_Pairing_Default
        and then Migrate'Result.Config.Empty_Allowlist_Denies_All
        and then Migrate'Result.Config.Restrict_Tool_To_Workspace =
          Security.Defaults.Workspace_Only_Default
        and then
          Migrate'Result.Config.Observability_Backend =
            Security.Defaults.Observability_Backend_Default);
end Security.Migration;
