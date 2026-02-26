--  Config loader: reads ~/.quasar/config.json and populates Agent_Config.
--  Also supports QUASAR_CONFIG env-var override for the file path.
--  Format mirrors NullClaw's snake_case convention for easy migration.

with Config.Schema;    use Config.Schema;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Config.Loader is

   Default_Config_Dir  : constant String := ".quasar";
   Default_Config_File : constant String := "config.json";

   type Load_Result is record
      Success : Boolean := False;
      Config  : Agent_Config;
      Error   : Unbounded_String;
   end record;

   --  Load config from disk. Path resolution order:
   --  1. QUASAR_CONFIG environment variable (full path)
   --  2. ~/.quasar/config.json
   function Load return Load_Result;

   --  Load from an explicit file path (useful for testing).
   function Load_From (Path : String) return Load_Result;

   --  Write a starter config.json if none exists.
   procedure Write_Default_Config (Path : String);

end Config.Loader;
