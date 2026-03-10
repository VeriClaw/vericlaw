--  Git operations tool implementation.
--  Delegates to Tools.Shell after validating the action name.

with Tools.Shell;

package body Tools.Git
  with SPARK_Mode => Off
is

   package Shell_Pkg renames Standard.Tools.Shell;

   function Is_Valid_Action (Action : String) return Boolean is
   begin
      return Action = "status"   or else Action = "log"      or else
             Action = "diff"     or else Action = "add"      or else
             Action = "commit"   or else Action = "push"     or else
             Action = "pull"     or else Action = "branch"   or else
             Action = "checkout";
   end Is_Valid_Action;

   --  Build the git sub-command string for the given validated action.
   function Build_Git_Cmd (Action : String; Args : String) return String is
   begin
      if Action = "status" then
         return "git status --short";
      elsif Action = "log" then
         return "git log --oneline -10";
      elsif Action = "diff" then
         return "git diff";
      elsif Action = "commit" then
         if Args'Length > 0 then
            return "git commit -m """ & Args & """";
         else
            return "git commit";
         end if;
      else
         --  add, push, pull, branch, checkout: append extra args verbatim.
         if Args'Length > 0 then
            return "git " & Action & " " & Args;
         else
            return "git " & Action;
         end if;
      end if;
   end Build_Git_Cmd;

   function Execute
     (Action    : String;
      Args      : String := "";
      Repo_Path : String := "") return Git_Result
   is
      Result : Git_Result;
   begin
      if not Is_Valid_Action (Action) then
         Set_Unbounded_String
           (Result.Error,
            "Invalid git action: """ & Action
            & """. Allowed: status log diff add commit push pull branch checkout");
         return Result;
      end if;

      declare
         Cmd : constant String := Build_Git_Cmd (Action, Args);
         WD  : constant String :=
           (if Repo_Path'Length > 0 then Repo_Path else ".");
         SR  : constant Shell_Pkg.Shell_Result := Shell_Pkg.Run (Cmd, WD);
      begin
         Result.Exit_Code := SR.Exit_Code;
         Result.Output    := SR.Stdout;
         if SR.Exit_Code = 0 then
            Result.Success := True;
         else
            Result.Error := SR.Stderr;
            if Length (Result.Error) = 0 then
               Result.Error := SR.Stdout;
            end if;
         end if;
         if SR.Truncated then
            Append (Result.Output, ASCII.LF & "[Output truncated]");
         end if;
      end;
      return Result;
   end Execute;

end Tools.Git;
