--  MCP tool executor.
--  Fetches available tools from the mcp-bridge sidecar and dispatches calls.
--  The bridge URL is configured via tools.mcp_bridge_url in config.json.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Providers.Interface_Pkg; use Providers.Interface_Pkg;

package Tools.MCP
  with SPARK_Mode => Off
is

   Max_MCP_Tools : constant := 50;

   type MCP_Tool is record
      Name        : Unbounded_String;
      Description : Unbounded_String;
      Input_Schema : Unbounded_String;  -- raw JSON schema string
   end record;

   type MCP_Tool_Array is array (Positive range <>) of MCP_Tool;

   --  Fetches the tool list from the bridge and populates Tools/Count.
   --  On any error, Count is set to 0 (never raises).
   procedure Fetch_Tools
     (Bridge_URL : String;
      Tools      : out MCP_Tool_Array;
      Count      : out Natural);

   --  Execute a named MCP tool via the bridge.
   --  Name must be in mcp__server__tool format.
   --  Returns tool result text, or empty string on error.
   function Execute
     (Bridge_URL : String;
      Name       : String;
      Args_JSON  : String) return String;

   --  Append fetched MCP tools to an existing schema array.
   procedure Append_Schemas
     (MCP_Tools  : MCP_Tool_Array;
      Count      : Natural;
      Schemas    : in out Tool_Schema_Array;
      Num        : in out Natural);

end Tools.MCP;
