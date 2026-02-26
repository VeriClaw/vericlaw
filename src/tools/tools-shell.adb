with Interfaces.C;         use Interfaces.C;
with Interfaces.C.Strings; use Interfaces.C.Strings;
with System;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Tools.Shell is

   --  POSIX thin bindings for popen / pclose.
   type FILE_Ptr is new System.Address;
   Null_FILE : constant FILE_Ptr := FILE_Ptr (System.Null_Address);

   function c_popen
     (Command : chars_ptr;
      Mode    : chars_ptr) return FILE_Ptr
   with Import, Convention => C, External_Name => "popen";

   function c_pclose (Stream : FILE_Ptr) return int
   with Import, Convention => C, External_Name => "pclose";

   function c_fgets
     (Buf    : chars_ptr;
      N      : int;
      Stream : FILE_Ptr) return chars_ptr
   with Import, Convention => C, External_Name => "fgets";

   function c_feof (Stream : FILE_Ptr) return int
   with Import, Convention => C, External_Name => "feof";

   --  We redirect stderr to stdout so both streams are captured together.
   --  The command is run as: cd <dir> && { <cmd>; } 2>&1
   function Build_Command
     (Command     : String;
      Working_Dir : String;
      Timeout_Sec : Positive) return String
   is
   begin
      return "cd " & Working_Dir
        & " && timeout " & Positive'Image (Timeout_Sec)
        & " sh -c " & ASCII.Quotation & Command & ASCII.Quotation
        & " 2>&1";
   end Build_Command;

   function Run
     (Command          : String;
      Working_Dir      : String;
      Timeout_Seconds  : Positive := 30;
      Max_Output_Bytes : Positive := 16_384) return Shell_Result
   is
      Full_Cmd   : constant String :=
        Build_Command (Command, Working_Dir, Timeout_Seconds);
      C_Cmd      : chars_ptr := New_String (Full_Cmd);
      C_Mode     : chars_ptr := New_String ("r");
      Stream     : FILE_Ptr;
      Buf_Size   : constant := 4096;
      Buf        : String (1 .. Buf_Size);
      C_Buf      : chars_ptr;
      for C_Buf'Address use Buf'Address;
      pragma Import (Ada, C_Buf);

      Output     : Unbounded_String;
      Result     : Shell_Result;
      Exit_C     : int;
   begin
      Stream := c_popen (C_Cmd, C_Mode);
      Free (C_Cmd);
      Free (C_Mode);

      if Stream = Null_FILE then
         Set_Unbounded_String (Result.Stderr, "popen failed");
         return Result;
      end if;

      while c_feof (Stream) = 0 loop
         declare
            Ret : chars_ptr;
         begin
            Ret := c_fgets (C_Buf, int (Buf_Size), Stream);
            if Ret /= Null_Ptr then
               declare
                  Line : constant String := Value (Ret);
               begin
                  if Length (Output) + Line'Length > Max_Output_Bytes then
                     Append (Output,
                       Line (1 .. Max_Output_Bytes - Length (Output)));
                     Result.Truncated := True;
                     exit;
                  end if;
                  Append (Output, Line);
               end;
            end if;
         end;
      end loop;

      Exit_C := c_pclose (Stream);
      Result.Exit_Code := Integer (Exit_C) / 256;  -- WEXITSTATUS
      Result.Stdout    := Output;
      return Result;
   end Run;

end Tools.Shell;
