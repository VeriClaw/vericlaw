with Tools.Shell;
with Tools.File_IO;
with Tools.Cron;
with Agent.Orchestrator;
with Config.JSON_Parser; use Config.JSON_Parser;

package body Agent.Tools
  with SPARK_Mode => Off
is

   --  Renamings to avoid ambiguity between Agent.Tools (this pkg) and top-level Tools
   package Shell_Pkg   renames Standard.Tools.Shell;
   package File_IO_Pkg renames Standard.Tools.File_IO;
   package Cron_Pkg    renames Standard.Tools.Cron;

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

   Cron_Add_Params : constant String :=
     "{"
     & """type"":""object"","
     & """properties"":{"
     & """name"":{""type"":""string"",""description"":""Unique job name""},"
     & """schedule"":{""type"":""string"","
     &   """description"":""Interval: 5m, 1h, 24h, 7d""},"
     & """prompt"":{""type"":""string"","
     &   """description"":""Task prompt to run on schedule""},"
     & """session_id"":{""type"":""string"","
     &   """description"":""Memory session ID (default: cron)""}"
     & "},"
     & """required"":[""name"",""schedule"",""prompt""]"
     & "}";

   Cron_Remove_Params : constant String :=
     "{"
     & """type"":""object"","
     & """properties"":{"
     & """name"":{""type"":""string"",""description"":""Job name to remove""}"
     & "},"
     & """required"":[""name""]"
     & "}";

   Cron_List_Params : constant String :=
     "{"
     & """type"":""object"","
     & """properties"":{},"
     & """required"":[]"
     & "}";

   Delegate_Params : constant String :=
     "{"
     & """type"":""object"","
     & """properties"":{"
     & """task"":{""type"":""string"","
     &   """description"":""Task prompt for the delegated agent""},"
     & """role"":{""type"":""string"","
     &   """enum"":[""researcher"",""coder"",""reviewer"",""general""],"
     &   """description"":""Agent role (default: general)""},"
     & """timeout"":{""type"":""integer"","
     &   """description"":""Timeout in seconds (default: 120)""}"
     & "},"
     & """required"":[""task""]"
     & "}";

   function Make_Schema (N, D, P : String) return Tool_Schema is
   begin
      return
        (Name        => To_Unbounded_String (N),
         Description => To_Unbounded_String (D),
         Parameters  => To_Unbounded_String (P));
   end Make_Schema;

   function JSON_Bool (Value : Boolean) return String is
   begin
      if Value then
         return "true";
      end if;
      return "false";
   end JSON_Bool;

   function Is_Allowed_Tool_Name (Name : String) return Boolean is
   begin
      --  Accept any MCP-bridged tool (dynamically discovered at runtime).
      if Name'Length > 5
        and then Name (Name'First .. Name'First + 4) = "mcp__"
      then
         return True;
      end if;
      --  Check against the compile-time known tool list.
      for I in Known_Tool_Names'Range loop
         if Known_Tool_Names (I).all = Name then
            return True;
         end if;
      end loop;
      return False;
   end Is_Allowed_Tool_Name;

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
      --  cron tools
      Num := Num + 1;
      Schemas (Num) := Make_Schema
        ("cron_add", "Schedule a recurring AI task", Cron_Add_Params);
      Num := Num + 1;
      Schemas (Num) := Make_Schema
        ("cron_list", "List all scheduled cron jobs", Cron_List_Params);
      Num := Num + 1;
      Schemas (Num) := Make_Schema
        ("cron_remove", "Remove a scheduled cron job", Cron_Remove_Params);
      --  delegate (multi-agent orchestration)
      Num := Num + 1;
       Schemas (Num) := Make_Schema
         ("delegate",
          "Delegate a task to a role-specialized sub-agent (researcher, coder, reviewer, general)",
          Delegate_Params);
   end Build_Schemas;

   function Dispatch
     (Name      : String;
      Args_JSON : String;
      Cfg       : Agent_Config;
      Mem       : Memory.SQLite.Memory_Handle;
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
         if not Cfg.Tools.Shell_Enabled then
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
         if not Cfg.Tools.File_Enabled then
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
         if not Cfg.Tools.File_Enabled then
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
         if not Cfg.Tools.File_Enabled then
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

      elsif Name = "cron_add" then
         declare
            CName : constant String := Get_String (PR.Root, "name");
            CSch  : constant String := Get_String (PR.Root, "schedule");
            CProm : constant String := Get_String (PR.Root, "prompt");
            CSess : constant String :=
              Get_String (PR.Root, "session_id", "cron");
            CR    : constant Cron_Pkg.Cron_Result :=
              Cron_Pkg.Cron_Add (Mem, CName, CSch, CProm, CSess);
         begin
            if CR.Success then
               Result.Success := True;
               Result.Output  := CR.Output;
            else
               Result.Error := CR.Error;
            end if;
         end;

      elsif Name = "cron_list" then
         declare
            CR : constant Cron_Pkg.Cron_Result :=
              Cron_Pkg.Cron_List (Mem);
         begin
            if CR.Success then
               Result.Success := True;
               Result.Output  := CR.Output;
            else
               Result.Error := CR.Error;
            end if;
         end;

      elsif Name = "cron_remove" then
         declare
            CName : constant String := Get_String (PR.Root, "name");
            CR    : constant Cron_Pkg.Cron_Result :=
              Cron_Pkg.Cron_Remove (Mem, CName);
         begin
            if CR.Success then
               Result.Success := True;
               Result.Output  := CR.Output;
            else
               Result.Error := CR.Error;
            end if;
         end;

      elsif Name = "delegate" then
          declare
             use Agent.Orchestrator;
            Task_Str : constant String := Get_String (PR.Root, "task");
            Role_Str : constant String := Get_String (PR.Root, "role", "general");
            Tmout    : constant Integer := Get_Integer (PR.Root, "timeout", 120);
            Role     : Agent_Role := General;
            Req      : Delegation_Request;
            Del_Res  : Delegation_Result;
          begin
            --  Parse role string.
            if Role_Str = "researcher" then
               Role := Researcher;
            elsif Role_Str = "coder" then
               Role := Coder;
            elsif Role_Str = "reviewer" then
               Role := Reviewer;
            else
               Role := General;
            end if;

            --  Check depth before delegating.
            if not Can_Delegate (0) then
               Set_Unbounded_String
                 (Result.Error, "Maximum delegation depth reached");
               return Result;
            end if;

            Req := (Role         => Role,
                    Task_Prompt  => To_Unbounded_String (Task_Str),
                    Parent_Depth => 0,
                    Timeout_Sec  => (if Tmout > 0 then Tmout else 120));

            Del_Res := Delegate (Req, Cfg);

            if Del_Res.Success then
               Result.Success := True;
               Result.Output  := Del_Res.Output;
            else
               Set_Unbounded_String
                 (Result.Error, To_String (Del_Res.Error));
            end if;
          end;

      else
         Set_Unbounded_String (Result.Error, "Unknown tool: " & Name);
      end if;

      return Result;
   end Dispatch;

   function Safe_Dispatch
     (Name      : String;
      Args_JSON : String;
      Cfg       : Agent_Config;
      Mem       : Memory.SQLite.Memory_Handle;
      Workspace : String) return Tool_Result
   is
   begin
      if not Is_Allowed_Tool_Name (Name) then
         return (Success => False,
                 Output  => Null_Unbounded_String,
                 Error   => To_Unbounded_String ("Unknown tool: " & Name));
      end if;
      return Dispatch (Name, Args_JSON, Cfg, Mem, Workspace);
   end Safe_Dispatch;

end Agent.Tools;
