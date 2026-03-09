with Ada.Exceptions;     use Ada.Exceptions;
with Agent.Context;
with Agent.Loop_Pkg;
with Logging;
with Memory.SQLite;

package body Agent.Orchestrator
  with SPARK_Mode => Off
is

   --  Protected counter to track active concurrent delegations.
   protected Active_Counter is
      procedure Increment (Allowed : out Boolean);
      procedure Decrement;
   private
      Count : Natural := 0;
   end Active_Counter;

   protected body Active_Counter is
      procedure Increment (Allowed : out Boolean) is
      begin
         if Count >= Max_Concurrent_Agents then
            Allowed := False;
         else
            Count   := Count + 1;
            Allowed := True;
         end if;
      end Increment;

      procedure Decrement is
      begin
         if Count > 0 then
            Count := Count - 1;
         end if;
      end Decrement;
   end Active_Counter;

   function Can_Delegate (Current_Depth : Natural) return Boolean is
   begin
      return Current_Depth < Max_Delegation_Depth;
   end Can_Delegate;

   function Role_System_Prompt (R : Agent_Role) return String is
   begin
      case R is
         when Researcher =>
            return "You are a researcher. "
              & "Focus on gathering and synthesizing information.";
         when Coder =>
            return "You are a coder. "
              & "Focus on writing correct, concise code.";
         when Reviewer =>
            return "You are a reviewer. "
              & "Focus on finding bugs, issues, and suggesting improvements.";
         when General =>
            return "You are a general-purpose assistant. "
              & "Complete the task thoroughly and concisely.";
      end case;
   end Role_System_Prompt;

   function Delegate
     (Req : Delegation_Request;
      Cfg : Config.Schema.Agent_Config) return Delegation_Result
   is
      Result  : Delegation_Result;
      Allowed : Boolean;
   begin
      --  Depth guard.
      if not Can_Delegate (Req.Parent_Depth) then
         Set_Unbounded_String
           (Result.Error, "Maximum delegation depth reached");
         return Result;
      end if;

      --  Concurrency guard.
      Active_Counter.Increment (Allowed);
      if not Allowed then
         Set_Unbounded_String
           (Result.Error,
            "Maximum concurrent agents ("
            & Natural'Image (Max_Concurrent_Agents) & ") reached");
         return Result;
      end if;

      --  Build a restricted sub-agent config: use the role system prompt
      --  and inherit provider settings from the parent config.
      declare
         Sub_Cfg : Config.Schema.Agent_Config := Cfg;
         Conv    : Agent.Context.Conversation;
         Mem     : Memory.SQLite.Memory_Handle;
         Reply   : Agent.Loop_Pkg.Agent_Reply;
      begin
         Set_Unbounded_String
           (Sub_Cfg.System_Prompt, Role_System_Prompt (Req.Role));

         Reply := Agent.Loop_Pkg.Process_Message
           (User_Input => To_String (Req.Task_Prompt),
            Conv       => Conv,
            Cfg        => Sub_Cfg,
            Mem        => Mem);

         Active_Counter.Decrement;

         Result.Success := Reply.Success;
         if Reply.Success then
            Result.Output := Reply.Content;
         else
            Result.Error := Reply.Error;
         end if;
      end;

      return Result;

   exception
      when E : others =>
         Active_Counter.Decrement;
         Logging.Warning ("orchestrator: delegation error ("
           & Exception_Name (E) & "): " & Exception_Message (E));
         Set_Unbounded_String (Result.Error,
           "Delegation failed: " & Exception_Name (E));
         return Result;
   end Delegate;

end Agent.Orchestrator;
