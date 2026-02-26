--  Core agent reasoning loop.
--  Orchestrates: context → provider → tool dispatch → response.
--  This module is provider-agnostic and channel-agnostic.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Agent.Context;
with Agent.Tools;
with Config.Schema;
with Memory.SQLite;

package Agent.Loop_Pkg is

   --  A reply to be sent back to the channel.
   type Agent_Reply is record
      Success  : Boolean := False;
      Content  : Unbounded_String;
      Error    : Unbounded_String;
   end record;

   --  Send a user message to the agent and get a reply.
   --  Conv is updated in-place with the new messages.
   --  Mem is used to persist + recall context.
   --  Provider_Cfg is used to select and call the LLM.
   function Process_Message
     (User_Input    : String;
      Conv          : in out Agent.Context.Conversation;
      Cfg           : Config.Schema.Agent_Config;
      Mem           : Memory.SQLite.Memory_Handle) return Agent_Reply;

   Max_Tool_Rounds : constant := 10;  -- max agentic loops before forced stop

end Agent.Loop_Pkg;
