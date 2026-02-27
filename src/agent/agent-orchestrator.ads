--  Multi-agent orchestration: delegate tasks to role-specialized sub-agents.
--  Depth-bounded to prevent unbounded recursion.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Config.Schema;

package Agent.Orchestrator
  with SPARK_Mode => Off
is

   Max_Delegation_Depth   : constant := 3;
   Max_Concurrent_Agents  : constant := 4;

   type Agent_Role is (Researcher, Coder, Reviewer, General);

   type Delegation_Request is record
      Role         : Agent_Role := General;
      Task_Prompt  : Unbounded_String;
      Parent_Depth : Natural := 0;
      Timeout_Sec  : Positive := 120;
   end record;

   type Delegation_Result is record
      Success : Boolean := False;
      Output  : Unbounded_String;
      Error   : Unbounded_String;
   end record;

   function Delegate
     (Req : Delegation_Request;
      Cfg : Config.Schema.Agent_Config) return Delegation_Result;
   --  Spawns a sub-agent with constrained permissions.
   --  Returns when sub-agent completes or times out.

   function Can_Delegate (Current_Depth : Natural) return Boolean;
   --  Returns True if Current_Depth < Max_Delegation_Depth.

   --  Role templates provide default system prompts for each role.
   function Role_System_Prompt (R : Agent_Role) return String;

end Agent.Orchestrator;
