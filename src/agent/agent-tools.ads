--  Tool dispatch and registry.
--  Every tool invocation is gated through Security.Policy before execution.
--  Tool schemas are exposed to LLM providers so they know what's available.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Providers.Interface_Pkg; use Providers.Interface_Pkg;
with Config.Schema;            use Config.Schema;

package Agent.Tools is

   type Tool_Result is record
      Success : Boolean := False;
      Output  : Unbounded_String;
      Error   : Unbounded_String;
   end record;

   --  Dispatch a tool call.  Returns an error result if the tool is not
   --  enabled in config or if security policy denies the call.
   function Dispatch
     (Name      : String;
      Args_JSON : String;
      Cfg       : Tool_Config;
      Workspace : String) return Tool_Result;

   --  Build the tool schema array to pass to providers.
   procedure Build_Schemas
     (Cfg       : Tool_Config;
      Schemas   : out Tool_Schema_Array;
      Num       : out Natural);

private

   Max_Output_Chars : constant := 16_384;  -- truncate tool output at 16 KB

end Agent.Tools;
