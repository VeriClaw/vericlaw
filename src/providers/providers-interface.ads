--  Abstract provider interface.
--  All LLM providers implement this contract so the agent loop is
--  provider-agnostic.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Agent.Context;

package Providers.Interface_Pkg is

   type Tool_Call is record
      ID        : Unbounded_String;  -- provider-assigned call ID
      Name      : Unbounded_String;  -- tool function name
      Arguments : Unbounded_String;  -- JSON string of arguments
   end record;

   Max_Tool_Calls : constant := 16;
   type Tool_Call_Array is array (Positive range <>) of Tool_Call;

   type Provider_Response is record
      Success        : Boolean := False;
      Content        : Unbounded_String;       -- assistant text
      Tool_Calls     : Tool_Call_Array (1 .. Max_Tool_Calls);
      Num_Tool_Calls : Natural := 0;
      Stop_Reason    : Unbounded_String;       -- "stop", "tool_calls", etc.
      Error          : Unbounded_String;
      Input_Tokens   : Natural := 0;
      Output_Tokens  : Natural := 0;
   end record;

   --  Tool schema passed to the provider so it knows available tools.
   type Tool_Schema is record
      Name        : Unbounded_String;
      Description : Unbounded_String;
      Parameters  : Unbounded_String;  -- JSON Schema string for parameters
   end record;

   Max_Tool_Schemas : constant := 32;
   type Tool_Schema_Array is array (Positive range <>) of Tool_Schema;

   --  Send a conversation to the provider and return its response.
   --  Implementors override this.
   type Provider_Type is abstract tagged null record;

   function Chat
     (Provider  : in out Provider_Type;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response is abstract;

   function Name (Provider : Provider_Type) return String is abstract;

end Providers.Interface_Pkg;
