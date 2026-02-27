--  Core agent reasoning loop.
--  Orchestrates: context → provider → tool dispatch → response.
--  This module is provider-agnostic and channel-agnostic.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Agent.Context;
with Config.Schema;
with Memory.SQLite;

package Agent.Loop_Pkg
  with SPARK_Mode => Off
is

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

   --  Like Process_Message but streams LLM tokens to stdout as they arrive.
   --  Tokens are printed by the provider's Chat_Streaming implementation.
   --  The returned Agent_Reply contains the complete assembled response.
   function Process_Message_Streaming
     (User_Input : String;
      Conv       : in out Agent.Context.Conversation;
      Cfg        : Config.Schema.Agent_Config;
      Mem        : Memory.SQLite.Memory_Handle) return Agent_Reply;

   --  Maximum number of LLM→tool→LLM agentic loops per request.
   --  Prevents runaway agent execution from adversarial or looping prompts.
   --  Sister project benchmarks: ZeroClaw uses 15, PicoClaw uses 8.
   Max_Tool_Rounds : constant := 10;

end Agent.Loop_Pkg;
