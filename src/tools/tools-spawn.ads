--  Spawn sub-agent tool: run a focused one-shot sub-conversation.
--  Sub-agents do not spawn further sub-agents (depth capped at 1).

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Config.Schema;

pragma SPARK_Mode (Off);
package Tools.Spawn is

   --  Maximum nesting depth; sub-agents cannot spawn more sub-agents.
   Max_Spawn_Depth : constant := 1;

   --  Run a sub-conversation with the given prompt.
   --  Model overrides the default model from Cfg when non-empty.
   --  Returns the assistant response, or an error string.
   function Run_Subagent
     (Prompt : String;
      Cfg    : Config.Schema.Agent_Config;
      Model  : String := "") return String;

end Tools.Spawn;
