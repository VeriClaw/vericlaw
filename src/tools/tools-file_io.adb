with Ada.Exceptions;     use Ada.Exceptions;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Directories;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Interfaces.C;
with Interfaces.C.Strings;
with Logging;

package body Tools.File_IO
  with SPARK_Mode => Off
is
   use type Interfaces.C.int;

   --  Thin C binding to vericlaw_symlink.c for portable symlink detection.
   function vericlaw_is_symlink
     (Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int;
   pragma Import (C, vericlaw_is_symlink, "vericlaw_is_symlink");

   function Is_Symlink (Path : String) return Boolean is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Result : constant Interfaces.C.int := vericlaw_is_symlink (C_Path);
   begin
      Interfaces.C.Strings.Free (C_Path);
      return Result /= 0;
   end Is_Symlink;

   function Contains_Null (S : String) return Boolean is
   begin
      for C of S loop
         if C = ASCII.NUL then return True; end if;
      end loop;
      return False;
   end Contains_Null;

   function Normalize_Path (P : String) return String is
      Result : Unbounded_String := To_Unbounded_String (P);
      Pos    : Natural;
   begin
      --  Collapse consecutive slashes.
      loop
         Pos := Index (To_String (Result), "//");
         exit when Pos = 0;
         Delete (Result, Pos, Pos);
      end loop;
      return To_String (Result);
   end Normalize_Path;

   function Validate_Path
     (Path      : String;
      Workspace : String) return String
   is
      Norm_Path : constant String := Normalize_Path (Path);
      Norm_WS   : constant String := Normalize_Path (Workspace);
   begin
      if Contains_Null (Path) then
         return "Path contains null byte";
      end if;
      if Index (Norm_Path, "..") /= 0 then
         return "Path traversal not allowed";
      end if;
      if Norm_Path'Length < Norm_WS'Length
        or else Norm_Path (1 .. Norm_WS'Length) /= Norm_WS
      then
         return "Path is outside workspace: " & Path;
      end if;
      if Is_Symlink (Path) then
         return "Symlink not allowed: " & Path;
      end if;
      return "";
   end Validate_Path;

   function Read
     (Path      : String;
      Workspace : String;
      Max_Bytes : Positive := 32_768) return File_Result
   is
      Err    : constant String := Validate_Path (Path, Workspace);
      Result : File_Result;
   begin
      if Err'Length > 0 then
         Set_Unbounded_String (Result.Error, Err);
         return Result;
      end if;

      if not Ada.Directories.Exists (Path) then
         Set_Unbounded_String (Result.Error, "File not found: " & Path);
         return Result;
      end if;

      declare
         File    : Ada.Text_IO.File_Type;
         Content : Unbounded_String;
         Line    : String (1 .. 4096);
         Last    : Natural;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
         while not Ada.Text_IO.End_Of_File (File) loop
            Ada.Text_IO.Get_Line (File, Line, Last);
            if Length (Content) + Last + 1 > Max_Bytes then
               Append (Content, Line (1 .. Max_Bytes - Length (Content)));
               Result.Content := Content;
               Ada.Text_IO.Close (File);
               Result.Success := True;
               return Result;
            end if;
            Append (Content, Line (1 .. Last));
            Append (Content, ASCII.LF);
         end loop;
         Ada.Text_IO.Close (File);
         Result.Content := Content;
         Result.Success := True;
      exception
         when E : others =>
            if Ada.Text_IO.Is_Open (File) then
               Ada.Text_IO.Close (File);
            end if;
            Logging.Warning ("file_io: read error on " & Path
              & " (" & Exception_Name (E) & "): " & Exception_Message (E));
            Set_Unbounded_String (Result.Error, "Error reading: " & Path);
      end;
      return Result;
   end Read;

   procedure Write_To_File
     (Path    : String;
      Content : String;
      Mode    : Ada.Text_IO.File_Mode;
      Result  : out File_Result)
   is
      File : Ada.Text_IO.File_Type;
   begin
      --  Ensure parent directory exists.
      declare
         Dir : constant String :=
           Ada.Directories.Containing_Directory (Path);
      begin
         if not Ada.Directories.Exists (Dir) then
            Ada.Directories.Create_Directory (Dir);
         end if;
      end;

      if Mode = Ada.Text_IO.Out_File or else
         not Ada.Directories.Exists (Path)
      then
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      else
         Ada.Text_IO.Open (File, Ada.Text_IO.Append_File, Path);
      end if;

      Ada.Text_IO.Put (File, Content);
      Ada.Text_IO.Close (File);
      Set_Unbounded_String (Result.Content, "Written: " & Path);
      Result.Success := True;
   exception
      when E : others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         Logging.Warning ("file_io: write error on " & Path
           & " (" & Exception_Name (E) & "): " & Exception_Message (E));
         Set_Unbounded_String (Result.Error, "Error writing: " & Path);
   end Write_To_File;

   function Write
     (Path      : String;
      Content   : String;
      Workspace : String) return File_Result
   is
      Err    : constant String := Validate_Path (Path, Workspace);
      Result : File_Result;
   begin
      if Err'Length > 0 then
         Set_Unbounded_String (Result.Error, Err);
         return Result;
      end if;
      Write_To_File (Path, Content, Ada.Text_IO.Out_File, Result);
      return Result;
   end Write;

   function Append
     (Path      : String;
      Content   : String;
      Workspace : String) return File_Result
   is
      Err    : constant String := Validate_Path (Path, Workspace);
      Result : File_Result;
   begin
      if Err'Length > 0 then
         Set_Unbounded_String (Result.Error, Err);
         return Result;
      end if;
      Write_To_File (Path, Content, Ada.Text_IO.Append_File, Result);
      return Result;
   end Append;

   function List
     (Path      : String;
      Workspace : String) return File_Result
   is
      Err    : constant String := Validate_Path (Path, Workspace);
      Result : File_Result;
      Search : Ada.Directories.Search_Type;
      Dir_Ent : Ada.Directories.Directory_Entry_Type;
   begin
      if Err'Length > 0 then
         Set_Unbounded_String (Result.Error, Err);
         return Result;
      end if;

      if not Ada.Directories.Exists (Path) then
         Set_Unbounded_String (Result.Error, "Directory not found: " & Path);
         return Result;
      end if;

      Ada.Directories.Start_Search (Search, Path, "*");
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Dir_Ent);
         declare
            Simple : constant String :=
              Ada.Directories.Simple_Name (Dir_Ent);
         begin
            if Simple /= "." and then Simple /= ".." then
               Append (Result.Content, Simple & ASCII.LF);
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
      Result.Success := True;
      return Result;
   end List;

end Tools.File_IO;
