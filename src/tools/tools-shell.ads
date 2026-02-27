--  Shell execution tool.
--  Calls runtime-executor policy checks before spawning any subprocess.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

pragma SPARK_Mode (Off);
package Tools.Shell is

   type Shell_Result is record
      Exit_Code : Integer := -1;
      Stdout    : Unbounded_String;
      Stderr    : Unbounded_String;
      Truncated : Boolean := False;
   end record;

   --  Run a shell command in the given working directory.
   --  Max_Output_Bytes: hard cap on combined stdout+stderr captured.
   --  Timeout_Seconds: kill process after this many seconds.
   function Run
     (Command          : String;
      Working_Dir      : String;
      Timeout_Seconds  : Positive := 30;
      Max_Output_Bytes : Positive := 16_384) return Shell_Result;

end Tools.Shell;
