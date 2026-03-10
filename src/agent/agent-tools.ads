--  Tool dispatch and registry.
--  Every tool invocation is gated through Security.Policy before execution.
--  Tool schemas are exposed to LLM providers so they know what's available.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Providers.Interface_Pkg; use Providers.Interface_Pkg;
with Config.Schema;            use Config.Schema;
with Memory.SQLite;

package Agent.Tools
  with SPARK_Mode => Off
is

   type Tool_Result is record
      Success : Boolean := False;
      Output  : Unbounded_String;
      Error   : Unbounded_String;
   end record;

   --  Complete set of tool name prefixes the dispatcher recognises.
   --  Any Name not in this set (and not starting with "mcp__") is rejected.
   --  Defined here for documentation and used in Is_Allowed_Tool_Name below.
   subtype Tool_Name_String is String;
   Known_Tool_Names : constant array (1 .. 8) of access constant String :=
      (new String'("shell"),
       new String'("file_read"),
       new String'("file_write"),
       new String'("file_list"),
      new String'("cron_add"),
      new String'("cron_list"),
      new String'("cron_remove"),
       new String'("delegate"));

   --  Return True if Name is a known built-in tool name OR starts with "mcp__".
   --  Enforced via Pre on Dispatch; also callable for proactive validation.
   function Is_Allowed_Tool_Name (Name : String) return Boolean;

   --  Dispatch a tool call.  Returns an error result if the tool is not
   --  enabled in config or if security policy denies the call.
   --  Pre: Name must be a known tool name or an MCP tool (prefix "mcp__").
   --  This is checked at runtime with -gnata; violation raises Assertion_Error.
   function Dispatch
     (Name      : String;
      Args_JSON : String;
      Cfg       : Agent_Config;
      Mem       : Memory.SQLite.Memory_Handle;
      Workspace : String) return Tool_Result
   with Pre => Is_Allowed_Tool_Name (Name);

   --  Safe dispatch: check allowlist then call Dispatch. Returns an error
   --  result (Success => False) for unknown tools instead of raising.
   --  Use this at call sites that cannot propagate Assertion_Error.
   function Safe_Dispatch
     (Name      : String;
      Args_JSON : String;
      Cfg       : Agent_Config;
      Mem       : Memory.SQLite.Memory_Handle;
      Workspace : String) return Tool_Result;

   --  Build the tool schema array to pass to providers.
   procedure Build_Schemas
     (Cfg       : Tool_Config;
      Schemas   : out Tool_Schema_Array;
      Num       : out Natural);

private

   Max_Output_Chars : constant := 16_384;  -- truncate tool output at 16 KB

end Agent.Tools;
