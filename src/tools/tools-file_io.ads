--  File I/O tool.
--  All paths are validated against the workspace root before any operation.
--  Null-byte injection is blocked.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Tools.File_IO
  with SPARK_Mode => Off
is

   type File_Op is (Read_File, Write_File, Append_File, List_Dir, Stat_File);

   type File_Result is record
      Success  : Boolean := False;
      Content  : Unbounded_String;
      Error    : Unbounded_String;
   end record;

   --  Read the entire file.  Returns at most Max_Bytes characters.
   function Read
     (Path      : String;
      Workspace : String;
      Max_Bytes : Positive := 32_768) return File_Result;

   --  Write (overwrite) a file.  Creates parent directories as needed.
   function Write
     (Path      : String;
      Content   : String;
      Workspace : String) return File_Result;

   --  Append to a file.
   function Append
     (Path      : String;
      Content   : String;
      Workspace : String) return File_Result;

   --  List directory entries as newline-separated paths.
   function List
     (Path      : String;
      Workspace : String) return File_Result;

   --  Validate that Path is under Workspace (no path traversal).
   --  Returns an error string, or "" if valid.
   function Validate_Path
     (Path      : String;
      Workspace : String) return String;

end Tools.File_IO;
