--  Plugin discovery and loading.
--  Scans a plugins directory for manifest.json files, verifies each
--  against the SPARK-proved Plugins.Capabilities policy, and registers
--  approved plugins in a bounded registry. Discovery is intentionally
--  metadata-only; entry points are catalogued but never executed here.
--
--  Plugin manifest format (manifest.json):
--    {
--      "name": "my-plugin",
--      "version": "0.1.0",
--      "entry": "plugin.sh",
--      "tools": ["file_read", "network_fetch"],
--      "signature_state": "signed_trusted_key"  -- emitted by an external verifier
--    }

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Plugins.Capabilities;

package Plugins.Loader
  with SPARK_Mode => Off
is

   Extensibility_Model : constant String := "mcp_first";
   Local_Plugin_Mode   : constant String := "manifest_discovery_only";
   Local_Load_Policy   : constant String := "signed_trusted_key_required";

   Max_Plugins : constant := 32;

   type Plugin_Status is (Plugin_Loaded, Plugin_Denied, Plugin_Error);

   type Plugin_Info is record
      Name    : Unbounded_String;
      Version : Unbounded_String;
      Entry_Point : Unbounded_String;
      Status  : Plugin_Status := Plugin_Error;
      Deny_Reason : Unbounded_String;
      Manifest : Capabilities.Capability_Manifest;
   end record;

   type Plugin_Array is array (1 .. Max_Plugins) of Plugin_Info;

   type Plugin_Registry is record
      Plugins   : Plugin_Array;
      Num_Loaded : Natural := 0;
   end record;

   --  Scan a directory for plugin manifests and load approved ones.
   --  Each subdirectory must contain a manifest.json.
   procedure Discover_And_Load
     (Dir      : String;
      Registry : out Plugin_Registry);

   --  Check if a named plugin is loaded and approved.
   function Is_Plugin_Loaded
     (Registry : Plugin_Registry;
      Name     : String) return Boolean;

   --  Get info for a named plugin.  Returns Plugin_Error status if not found.
   function Get_Plugin
     (Registry : Plugin_Registry;
      Name     : String) return Plugin_Info;

   function Resolve_Plugin_Directory (Configured_Path : String) return String;

   procedure Load_Runtime_Registry (Configured_Directory : String);

   function Runtime_Registry return Plugin_Registry;
   function Runtime_Plugin_Directory return String;

   function Loaded_Plugin_Count (Registry : Plugin_Registry) return Natural;
   function Denied_Plugin_Count (Registry : Plugin_Registry) return Natural;
   function Error_Plugin_Count (Registry : Plugin_Registry) return Natural;

   function Plugin_Status_Name (Status : Plugin_Status) return String;
   function Signature_State_Name
     (State : Capabilities.Signature_Verification_State) return String;
   function Tool_Kind_Name (Kind : Capabilities.Tool_Kind) return String;

   function Runtime_Registry_JSON return String;

end Plugins.Loader;
