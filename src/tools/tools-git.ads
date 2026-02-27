--  Git operations tool.
--  Actions are validated against an allowlist before execution.
--  Shells out to the system git binary via Tools.Shell.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Tools.Git is

   type Git_Result is record
      Success   : Boolean := False;
      Output    : Unbounded_String;
      Error     : Unbounded_String;
      Exit_Code : Integer := -1;
   end record;

   --  Execute a git action in the given repository directory.
   --  Action must be one of: status log diff add commit push pull branch checkout
   --  Args is appended verbatim (validated action prevents injection).
   --  Repo_Path is the working directory; defaults to "." when empty.
   function Execute
     (Action    : String;
      Args      : String := "";
      Repo_Path : String := "") return Git_Result;

end Tools.Git;
