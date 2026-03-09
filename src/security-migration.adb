
package body Security.Migration with SPARK_Mode is
   function Migrate_Gateway_Bind_Host
     (Pattern : External_Gateway_Host_Pattern) return Gateway_Host_String is
   begin
      case Pattern is
         when Host_Local_Only | Host_Public_Wildcard | Host_Private_Interface |
           Host_Ambiguous =>
            return Security.Defaults.Gateway_Bind_Host;
      end case;
   end Migrate_Gateway_Bind_Host;

   function Migrate_Allow_Public_Bind
     (Pattern : External_Public_Bind_Pattern) return Boolean is
   begin
      case Pattern is
         when Public_Bind_Disabled | Public_Bind_Enabled |
           Public_Bind_Ambiguous =>
            return Security.Defaults.Allow_Public_Bind_Default;
      end case;
   end Migrate_Allow_Public_Bind;

   function Migrate_Require_Pairing
     (Pattern : External_Pairing_Pattern) return Boolean is
   begin
      case Pattern is
         when Pairing_Required | Pairing_Disabled | Pairing_Ambiguous =>
            return Security.Defaults.Require_Pairing_Default;
      end case;
   end Migrate_Require_Pairing;

   function Migrate_Empty_Allowlist_Denies_All
     (Pattern : External_Allowlist_Pattern) return Boolean is
   begin
      case Pattern is
         when Allowlist_Required | Allowlist_Disabled | Allowlist_Ambiguous =>
            return True;
      end case;
   end Migrate_Empty_Allowlist_Denies_All;

   function Migrate_Workspace_Restriction
     (Pattern : External_Workspace_Pattern) return Boolean is
   begin
      case Pattern is
         when Workspace_Restricted | Workspace_Unrestricted |
           Workspace_Ambiguous =>
            return Security.Defaults.Workspace_Only_Default;
      end case;
   end Migrate_Workspace_Restriction;

   function Migrate_Observability_Backend
     (Pattern : External_Observability_Pattern)
      return Observability_Backend_String is
   begin
      case Pattern is
         when Observability_None | Observability_Remote_Exporter |
           Observability_Ambiguous =>
            return Security.Defaults.Observability_Backend_Default;
      end case;
   end Migrate_Observability_Backend;

   function Gateway_Host_Migration_Decision
     (Pattern : External_Gateway_Host_Pattern) return Migration_Decision is
   begin
      case Pattern is
         when Host_Local_Only =>
            return Mapped_Secure_Input;
         when Host_Public_Wildcard | Host_Private_Interface | Host_Ambiguous =>
            return Forced_Secure_Default;
      end case;
   end Gateway_Host_Migration_Decision;

   function Public_Bind_Migration_Decision
     (Pattern : External_Public_Bind_Pattern) return Migration_Decision is
   begin
      case Pattern is
         when Public_Bind_Disabled =>
            return Mapped_Secure_Input;
         when Public_Bind_Enabled | Public_Bind_Ambiguous =>
            return Forced_Secure_Default;
      end case;
   end Public_Bind_Migration_Decision;

   function Pairing_Migration_Decision
     (Pattern : External_Pairing_Pattern) return Migration_Decision is
   begin
      case Pattern is
         when Pairing_Required =>
            return Mapped_Secure_Input;
         when Pairing_Disabled | Pairing_Ambiguous =>
            return Forced_Secure_Default;
      end case;
   end Pairing_Migration_Decision;

   function Allowlist_Migration_Decision
     (Pattern : External_Allowlist_Pattern) return Migration_Decision is
   begin
      case Pattern is
         when Allowlist_Required =>
            return Mapped_Secure_Input;
         when Allowlist_Disabled | Allowlist_Ambiguous =>
            return Forced_Secure_Default;
      end case;
   end Allowlist_Migration_Decision;

   function Workspace_Migration_Decision
     (Pattern : External_Workspace_Pattern) return Migration_Decision is
   begin
      case Pattern is
         when Workspace_Restricted =>
            return Mapped_Secure_Input;
         when Workspace_Unrestricted | Workspace_Ambiguous =>
            return Forced_Secure_Default;
      end case;
   end Workspace_Migration_Decision;

   function Observability_Migration_Decision
     (Pattern : External_Observability_Pattern) return Migration_Decision is
   begin
      case Pattern is
         when Observability_None =>
            return Mapped_Secure_Input;
         when Observability_Remote_Exporter | Observability_Ambiguous =>
            return Forced_Secure_Default;
      end case;
   end Observability_Migration_Decision;

   function Migrate (Input : External_Config_Pattern) return Migration_Report is
   begin
      return
        (Config =>
           (Gateway_Bind_Host =>
              Migrate_Gateway_Bind_Host (Input.Gateway_Host),
            Allow_Public_Bind =>
              Migrate_Allow_Public_Bind (Input.Public_Bind),
            Require_Pairing =>
              Migrate_Require_Pairing (Input.Pairing),
            Empty_Allowlist_Denies_All =>
              Migrate_Empty_Allowlist_Denies_All (Input.Allowlist),
            Restrict_Tool_To_Workspace =>
              Migrate_Workspace_Restriction (Input.Workspace),
            Observability_Backend =>
              Migrate_Observability_Backend (Input.Observability)),
         Gateway_Host_Decision =>
           Gateway_Host_Migration_Decision (Input.Gateway_Host),
         Public_Bind_Decision =>
           Public_Bind_Migration_Decision (Input.Public_Bind),
         Pairing_Decision =>
           Pairing_Migration_Decision (Input.Pairing),
         Allowlist_Decision =>
           Allowlist_Migration_Decision (Input.Allowlist),
         Workspace_Decision =>
           Workspace_Migration_Decision (Input.Workspace),
         Observability_Decision =>
           Observability_Migration_Decision (Input.Observability));
   end Migrate;
end Security.Migration;
