with Tools.Shell;
with Tools.File_IO;
with Tools.Brave_Search;
with Tools.MCP;
with Config.JSON_Parser; use Config.JSON_Parser;

package body Agent.Tools is

   --  Renamings to avoid ambiguity between Agent.Tools (this pkg) and top-level Tools
   package Shell_Pkg   renames Standard.Tools.Shell;
   package File_IO_Pkg renames Standard.Tools.File_IO;
   package Search_Pkg  renames Standard.Tools.Brave_Search;
   package MCP_Pkg     renames Standard.Tools.MCP;

   --  JSON Schema strings for each tool (passed to LLM providers).
   Shell_Params : constant String :=
     "{"
     & """type"":""object"","
     & """properties"":{"
     & """command"":{""type"":""string"",""description"":""Shell command to run""},"
     & """working_dir"":{""type"":""string"",""description"":""Working directory (default: workspace)""}"
     & "},"
     & """required"":[""command""]"
     & "}";

   File_Read_Params : constant String :=
     "{"
     & """type"":""object"","
     & """properties"":{"
     & """path"":{""type"":""string"",""description"":""File path (relative to workspace)""}"
     & "},"
     & """required"":[""path""]"
     & "}";

   File_Write_Params : constant String :=
     "{"
     & """type"":""object"","
     & """properties"":{"
     & """path"":{""type"":""string"",""description"":""File path (relative to workspace)""},"
     & """content"":{""type"":""string"",""description"":""Content to write""}"
     & "},"
     & """required"":[""path"",""content""]"
     & "}";

   File_List_Params : constant String :=
     "{"
     & """type"":""object"","
     & """properties"":{"
     & """path"":{""type"":""string"",""description"":""Directory path (default: workspace root)""}"
     & "},"
     & """required"":[]"
     & "}";

   Brave_Params : constant String :=
     "{"
     & """type"":""object"","
     & """properties"":{"
     & """query"":{""type"":""string"",""description"":""Search query""},"
     & """num_results"":{""type"":""integer"",""description"":""Number of results (1-10, default 5)""}"
     & "},"
     & """required"":[""query""]"
     & "}";

   function Make_Schema (N, D, P : String) return Tool_Schema is
   begin
      return
        (Name        => To_Unbounded_String (N),
         Description => To_Unbounded_String (D),
         Parameters  => To_Unbounded_String (P));
   end Make_Schema;

   procedure Build_Schemas
     (Cfg     : Tool_Config;
      Schemas : out Tool_Schema_Array;
      Num     : out Natural)
   is
   begin
      Num := 0;
      --  shell
      if Cfg.Shell_Enabled then
         Num := Num + 1;
         Schemas (Num) := Make_Schema
           ("shell", "Execute a shell command in the workspace", Shell_Params);
      end if;
      --  file tools
      if Cfg.File_Enabled then
         Num := Num + 1;
         Schemas (Num) := Make_Schema
           ("file_read", "Read a file from the workspace", File_Read_Params);
         Num := Num + 1;
         Schemas (Num) := Make_Schema
           ("file_write", "Write content to a file in the workspace",
            File_Write_Params);
         Num := Num + 1;
         Schemas (Num) := Make_Schema
           ("file_list", "List files in a workspace directory", File_List_Params);
      end if;
      --  brave search
      if Cfg.Brave_Search_Enabled then
         Num := Num + 1;
         Schemas (Num) := Make_Schema
           ("brave_search", "Search the web using Brave Search", Brave_Params);
      end if;
      --  MCP tools via bridge
      if Length (Cfg.MCP_Bridge_URL) > 0 then
         declare
            MCP_Tools : MCP_Pkg.MCP_Tool_Array (1 .. MCP_Pkg.Max_MCP_Tools);
            MCP_Count : Natural;
         begin
            MCP_Pkg.Fetch_Tools
              (To_String (Cfg.MCP_Bridge_URL), MCP_Tools, MCP_Count);
            MCP_Pkg.Append_Schemas (MCP_Tools, MCP_Count, Schemas, Num);
         end;
      end if;
   end Build_Schemas;

   function Dispatch
     (Name      : String;
      Args_JSON : String;
      Cfg       : Tool_Config;
      Workspace : String) return Tool_Result
   is
      PR     : constant Parse_Result := Parse (Args_JSON);
      Result : Tool_Result;
   begin
      if not PR.Valid then
         Set_Unbounded_String
           (Result.Error, "Invalid tool arguments JSON: " & Args_JSON);
         return Result;
      end if;

      if Name = "shell" then
         if not Cfg.Shell_Enabled then
            Set_Unbounded_String (Result.Error, "Shell tool is not enabled");
            return Result;
         end if;
         declare
            Cmd     : constant String := Get_String (PR.Root, "command");
            WD      : constant String :=
              Get_String (PR.Root, "working_dir", Workspace);
            SR      : constant Shell_Pkg.Shell_Result :=
              Shell_Pkg.Run (Cmd, WD);
         begin
            if SR.Exit_Code = 0 then
               Result.Success := True;
               Result.Output  := SR.Stdout;
            else
               Set_Unbounded_String
                 (Result.Error,
                  "Exit " & Integer'Image (SR.Exit_Code)
                  & ": " & To_String (SR.Stderr));
               Append (Result.Output, To_String (SR.Stdout));
            end if;
            if SR.Truncated then
               Append (Result.Output,
                 ASCII.LF & "[Output truncated]");
            end if;
         end;

      elsif Name = "file_read" then
         if not Cfg.File_Enabled then
            Set_Unbounded_String (Result.Error, "File tool is not enabled");
            return Result;
         end if;
         declare
            Path : constant String :=
              Workspace & "/" & Get_String (PR.Root, "path");
            FR   : constant File_IO_Pkg.File_Result :=
              File_IO_Pkg.Read (Path, Workspace);
         begin
            if FR.Success then
               Result.Success := True;
               Result.Output  := FR.Content;
            else
               Result.Error := FR.Error;
            end if;
         end;

      elsif Name = "file_write" then
         if not Cfg.File_Enabled then
            Set_Unbounded_String (Result.Error, "File tool is not enabled");
            return Result;
         end if;
         declare
            Path    : constant String :=
              Workspace & "/" & Get_String (PR.Root, "path");
            Content : constant String := Get_String (PR.Root, "content");
            FR      : constant File_IO_Pkg.File_Result :=
              File_IO_Pkg.Write (Path, Content, Workspace);
         begin
            if FR.Success then
               Result.Success := True;
               Result.Output  := FR.Content;
            else
               Result.Error := FR.Error;
            end if;
         end;

      elsif Name = "file_list" then
         if not Cfg.File_Enabled then
            Set_Unbounded_String (Result.Error, "File tool is not enabled");
            return Result;
         end if;
         declare
            Dir : constant String :=
              Get_String (PR.Root, "path", Workspace);
            FR  : constant File_IO_Pkg.File_Result :=
              File_IO_Pkg.List (Dir, Workspace);
         begin
            if FR.Success then
               Result.Success := True;
               Result.Output  := FR.Content;
            else
               Result.Error := FR.Error;
            end if;
         end;

      elsif Name = "brave_search" then
         if not Cfg.Brave_Search_Enabled then
            Set_Unbounded_String
              (Result.Error, "Brave Search tool is not enabled");
            return Result;
         end if;
         declare
            Query : constant String := Get_String (PR.Root, "query");
            NR    : constant Integer :=
              Get_Integer (PR.Root, "num_results", 5);
            SR    : constant Search_Pkg.Brave_Result :=
              Search_Pkg.Search
                (Query       => Query,
                 API_Key     => To_String (Cfg.Brave_API_Key),
                 Num_Results => (if NR > 0 then NR else 5));
         begin
            if SR.Success then
               Result.Success := True;
               Set_Unbounded_String
                 (Result.Output,
                  Search_Pkg.To_Agent_Text (SR));
            else
               Result.Error := SR.Error;
            end if;
         end;

      else
         --  Check for MCP tool (prefix "mcp__").
         if Name'Length > 5
           and then Name (Name'First .. Name'First + 4) = "mcp__"
         then
            if Length (Cfg.MCP_Bridge_URL) = 0 then
               Set_Unbounded_String
                 (Result.Error, "MCP bridge URL not configured");
            else
               declare
                  MCP_Result : constant String :=
                    MCP_Pkg.Execute
                      (To_String (Cfg.MCP_Bridge_URL), Name, Args_JSON);
               begin
                  Result.Success := True;
                  Set_Unbounded_String (Result.Output, MCP_Result);
               end;
            end if;
         else
            Set_Unbounded_String
              (Result.Error, "Unknown tool: " & Name);
         end if;
      end if;

      return Result;
   end Dispatch;

end Agent.Tools;
