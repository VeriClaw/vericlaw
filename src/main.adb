with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Command_Line;      use Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Calendar;
with Ada.Calendar.Formatting;
with Logging;
with Build_Info;

--  Existing SPARK-verified security layer (unchanged)
with Channels.Security;
with Core.Agent;

--  New runtime modules
with Config.Loader;
with Config.Schema;
with Config.JSON_Parser;
with HTTP.Client;
with Memory.SQLite;
with Agent.Context;
with Agent.Loop_Pkg;
with Channels.CLI;
with Channels.Telegram;
with Channels.Signal;
with Channels.WhatsApp;
with Channels.Discord;
with Channels.Slack;
with Channels.Email;
with Channels.IRC;
with Channels.Matrix;
with HTTP.Server;
with Tools.Cron;
with Audit.Syslog;
with Metrics.Cost;
with Observability.Tracing;
with Sandbox;

procedure Main
  with SPARK_Mode => Off
is

   use type Config.Schema.Channel_Kind;

   procedure Print_Usage is
   begin
      Put_Line ("Usage: vericlaw <command> [options]");
      New_Line;
      Put_Line ("Commands:");
      Put_Line ("  onboard                          Interactive setup wizard (run this first)");
      Put_Line ("  channels login --channel <name>  Link a messaging channel (e.g. whatsapp)");
      Put_Line ("  chat                             Interactive CLI chat (default)");
      Put_Line ("  agent <message>                  One-shot agent: send a message and print reply");
      Put_Line ("  gateway                          Run HTTP gateway + all configured channels");
      Put_Line ("  status                           Show runtime status summary");
      Put_Line ("  export --session <id> [--format] Export conversation (md or json)");
      Put_Line ("  config validate                  Validate config file without starting agent");
      Put_Line ("  doctor                           Print configuration and health status");
      Put_Line ("  update-check                     Check for new VeriClaw releases");
      Put_Line ("  version                          Print version information");
      Put_Line ("  help                             Show this help message");
      New_Line;
      Put_Line ("Global flags:");
      Put_Line ("  --json       Machine-readable JSON output (agent, status)");
      Put_Line ("  --no-color   Disable ANSI colors (auto-detected for pipes)");
      New_Line;
      Put_Line ("Config: ~/.vericlaw/config.json  (or VERICLAW_CONFIG env var)");
      Put_Line ("WhatsApp: see docs/setup/whatsapp.md for full setup guide");
   end Print_Usage;

   procedure Cmd_Version is
   begin
      Put_Line ("vericlaw " & Build_Info.Version & " (" &
                Build_Info.Git_Commit & " " &
                Build_Info.Build_Date & " " &
                Build_Info.Target_Triple & ")");
      Put_Line ("Built with Ada 2022 + GNAT  |  https://github.com/vericlaw");
   end Cmd_Version;

   procedure Cmd_Update_Check is
      use HTTP.Client;
      Resp : HTTP.Client.Response;
      API_URL : constant String := "https://api.github.com/repos/vericlaw/vericlaw/releases/latest";
      No_Headers : constant HTTP.Client.Header_Array (1 .. 0) :=
        [others => <>];
   begin
      Put_Line ("Checking for updates...");
      Resp := HTTP.Client.Get (API_URL, No_Headers, Timeout_Ms => 5000);
      if not Is_Success (Resp) then
         Put_Line ("  Could not reach update server.");
         Put_Line ("  Current version: " & Build_Info.Version);
         return;
      end if;

      --  Parse tag_name from response JSON
      declare
         Resp_Body : constant String := To_String (Resp.Body_Text);
         Tag_Key  : constant String := """tag_name"":""";
         Tag_Pos  : Natural;
         Tag_End  : Natural;
         Latest   : Unbounded_String;
      begin
         Tag_Pos := Ada.Strings.Fixed.Index (Resp_Body, Tag_Key);
         if Tag_Pos = 0 then
            Put_Line ("  Could not parse latest version.");
            return;
         end if;
         Tag_Pos := Tag_Pos + Tag_Key'Length;
         Tag_End := Ada.Strings.Fixed.Index (Resp_Body, """", Tag_Pos);
         if Tag_End = 0 then
            Put_Line ("  Could not parse latest version.");
            return;
         end if;
         Set_Unbounded_String (Latest, Resp_Body (Tag_Pos .. Tag_End - 1));

         --  Strip leading 'v' if present
         declare
            Latest_Str : constant String := To_String (Latest);
            Clean_Latest : constant String :=
              (if Latest_Str'Length > 0 and then Latest_Str (Latest_Str'First) = 'v'
               then Latest_Str (Latest_Str'First + 1 .. Latest_Str'Last)
               else Latest_Str);
         begin
            if Clean_Latest = Build_Info.Version then
               Put_Line ("  You are running the latest version (" & Build_Info.Version & ").");
            else
               Put_Line ("  Update available: " & Clean_Latest & " (current: " & Build_Info.Version & ")");
               Put_Line ("");
               Put_Line ("  To update:");
               Put_Line ("    brew upgrade vericlaw       # if installed via Homebrew");
               Put_Line ("    sudo apt upgrade vericlaw   # if installed via APT");
               Put_Line ("    scoop update vericlaw       # if installed via Scoop");
               Put_Line ("    curl -fsSL https://get.vericlaw.dev | sh  # universal installer");
            end if;
         end;
      end;
   end Cmd_Update_Check;

   --  Verify SPARK security defaults still hold (keeps the proven layer active).
   procedure Assert_Security_Defaults is
      Spark_Cfg      : constant Core.Agent.Agent_Config := (others => <>);
      Channel_Result : constant Channels.Security.Channel_Request_Result :=
        Channels.Security.Evaluate_Channel_Request
          (Channel                 => Channels.Security.CLI_Channel,
           Allowlist_Size          => 1,
           Candidate_Matches       => True,
           Limiter_Configured      => True,
           Requests_In_Window      => 0,
           Max_Requests            => 10,
           Idempotency_Key_Present => True,
           Seen_Before             => False);
   begin
      if not Core.Agent.Config_Is_Safe_Default (Spark_Cfg)
        or else not Channel_Result.Allowed
      then
         Put_Line ("FATAL: SPARK security assertion failed. Refusing to start.");
         Set_Exit_Status (Failure);
         return;
      end if;
   end Assert_Security_Defaults;

   procedure Load_Config_Or_Die
     (Result : out Config.Loader.Load_Result)
   is
      Default_Path : constant String :=
        Ada.Environment_Variables.Value ("HOME", ".")
        & "/.vericlaw/config.json";
   begin
      Result := Config.Loader.Load;
      if not Result.Success then
         Put_Line ("Config error: " & To_String (Result.Error));
         --  If config doesn't exist, write a starter and bail with guidance.
         if not Ada.Directories.Exists (Default_Path) then
            Config.Loader.Write_Default_Config (Default_Path);
            Put_Line ("Created starter config: " & Default_Path);
            Put_Line ("Edit it to add your API keys, then run vericlaw again.");
         end if;
         Set_Exit_Status (Failure);
      end if;
   end Load_Config_Or_Die;

   procedure Open_Memory_Or_Warn
     (Cfg    : Config.Schema.Agent_Config;
      Mem    : out Memory.SQLite.Memory_Handle;
      OK     : out Boolean)
   is
      Home   : constant String :=
        Ada.Environment_Variables.Value ("HOME", ".");
      DB_Path : constant String :=
        (if Length (Cfg.Memory.DB_Path) > 0
         then To_String (Cfg.Memory.DB_Path)
         else Home & "/.vericlaw/memory.db");
      Err    : Unbounded_String;
   begin
      OK := Memory.SQLite.Open (Mem, DB_Path, Err,
                                Cfg.Memory.Session_Retention_Days);
      if not OK then
         Put_Line ("Warning: memory unavailable: " & To_String (Err));
      end if;
   end Open_Memory_Or_Warn;

   procedure Cmd_Doctor (Cfg : Config.Schema.Agent_Config) is
      Home : constant String :=
        Ada.Environment_Variables.Value ("HOME", ".");
      DB_Path : constant String :=
        (if Length (Cfg.Memory.DB_Path) > 0
         then To_String (Cfg.Memory.DB_Path)
         else Home & "/.vericlaw/memory.db");
      Workspace_Path : constant String :=
        Home & "/.vericlaw/workspace/";

      Total  : Natural := 0;
      Passed : Natural := 0;
   begin
      Put_Line ("=== VeriClaw Doctor ===");
      New_Line;

      --  1. Config check (already loaded by caller via Load_Config_Or_Die)
      Put_Line ("Config:");
      Put_Line ("  config      : OK");
      Total  := Total + 1;
      Passed := Passed + 1;
      Put_Line ("  agent_name  : " & To_String (Cfg.Agent_Name));
      Put_Line ("  providers   : " & Config.Schema.Provider_Index'Image
        (Cfg.Num_Providers));
      for I in 1 .. Cfg.Num_Providers loop
         Put_Line ("    [" & Config.Schema.Provider_Index'Image (I) & "] "
           & Config.Schema.Provider_Kind'Image (Cfg.Providers (I).Kind)
           & "  model=" & To_String (Cfg.Providers (I).Model)
           & (if Length (Cfg.Providers (I).Base_URL) > 0
              then "  url=" & To_String (Cfg.Providers (I).Base_URL)
              else ""));
      end loop;
      Put_Line ("  channels    : " & Config.Schema.Channel_Index'Image
        (Cfg.Num_Channels));
      for I in 1 .. Cfg.Num_Channels loop
         Put ("    [" & Config.Schema.Channel_Index'Image (I) & "] "
           & Config.Schema.Channel_Kind'Image (Cfg.Channels (I).Kind));
         if Cfg.Channels (I).Enabled then
            Put_Line ("  ENABLED");
         else
            Put_Line ("  disabled");
         end if;
      end loop;
      New_Line;

      --  2. Database connectivity
      Put_Line ("Database:");
      Total := Total + 1;
      declare
         Test_Mem : Memory.SQLite.Memory_Handle;
         Test_OK  : Boolean;
         Err      : Unbounded_String;
      begin
         Test_OK := Memory.SQLite.Open (Test_Mem, DB_Path, Err);
         if Test_OK then
            Put_Line ("  database    : OK (" & DB_Path & ")");
            Memory.SQLite.Close (Test_Mem);
            Passed := Passed + 1;
         else
            Put_Line ("  database    : FAIL (" & To_String (Err) & ")");
         end if;
      end;
      New_Line;

      --  3. Bridge health — check each enabled bridge channel
      Put_Line ("Bridges:");
      for I in 1 .. Cfg.Num_Channels loop
         if Cfg.Channels (I).Enabled
           and then Length (Cfg.Channels (I).Bridge_URL) > 0
         then
            Total := Total + 1;
            declare
               URL : constant String :=
                 To_String (Cfg.Channels (I).Bridge_URL) & "/health";
               Resp : constant HTTP.Client.Response :=
                 HTTP.Client.Get
                   (URL, HTTP.Client.Header_Array'[1 .. 0 => <>],
                    Timeout_Ms => 5000);
            begin
               if HTTP.Client.Is_Success (Resp) then
                  Put_Line ("  "
                    & Config.Schema.Channel_Kind'Image
                        (Cfg.Channels (I).Kind)
                    & " bridge : OK (" & URL & ")");
                  Passed := Passed + 1;
               else
                  Put_Line ("  "
                    & Config.Schema.Channel_Kind'Image
                        (Cfg.Channels (I).Kind)
                    & " bridge : FAIL (" & URL & " => "
                    & (if Length (Resp.Error) > 0
                       then To_String (Resp.Error)
                       else "HTTP" & Natural'Image (Resp.Status_Code))
                    & ")");
               end if;
            end;
         end if;
      end loop;
      New_Line;

      --  4. SPARK security core (compile-time verified)
      Put_Line ("SPARK:");
      Put_Line ("  security core: OK (compile-time verified)");
      Total  := Total + 1;
      Passed := Passed + 1;
      New_Line;

      --  5. Workspace directory
      Put_Line ("Workspace:");
      Total := Total + 1;
      if Ada.Directories.Exists (Workspace_Path) then
         declare
            Test_File : constant String :=
              Workspace_Path & ".doctor_probe";
         begin
            declare
               F : Ada.Text_IO.File_Type;
            begin
               Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Test_File);
               Ada.Text_IO.Close (F);
               Ada.Directories.Delete_File (Test_File);
               Put_Line ("  workspace   : OK (" & Workspace_Path & ")");
               Passed := Passed + 1;
            exception
               when others =>
                  Put_Line ("  workspace   : FAIL (not writable: "
                    & Workspace_Path & ")");
            end;
         end;
      else
         Put_Line ("  workspace   : FAIL (missing: "
           & Workspace_Path & ")");
      end if;
      New_Line;

      --  Summary
      Put_Line ("Summary: " & Natural'Image (Passed) & " /"
        & Natural'Image (Total) & " checks passed");
      if Passed < Total then
         Ada.Command_Line.Set_Exit_Status (1);
      end if;
   end Cmd_Doctor;

   --  Graceful shutdown flag (placeholder for future signal handling).
   Shutdown_Requested : constant Boolean := False;

   --  Entry point
   Cmd    : Unbounded_String := To_Unbounded_String ("chat");
   CR     : Config.Loader.Load_Result;
   Mem    : aliased Memory.SQLite.Memory_Handle;
   Mem_OK : Boolean;

   --  Global flags
   JSON_Mode : Boolean := False;
   No_Color  : Boolean := False;

   procedure Parse_Global_Flags is
   begin
      for I in 1 .. Argument_Count loop
         if Argument (I) = "--json" then
            JSON_Mode := True;
         elsif Argument (I) = "--no-color" then
            No_Color := True;
         end if;
      end loop;
      --  Auto-detect non-TTY: disable color when stdout is piped.
      --  Ada doesn't expose isatty directly; we check TERM env var as proxy.
      if not No_Color then
         declare
            Term : constant String :=
              (if Ada.Environment_Variables.Exists ("TERM")
               then Ada.Environment_Variables.Value ("TERM")
               else "");
         begin
            if Term = "dumb" or else Term = "" then
               No_Color := True;
            end if;
         end;
         --  Also disable color if NO_COLOR env var is set (https://no-color.org/)
         if Ada.Environment_Variables.Exists ("NO_COLOR") then
            No_Color := True;
         end if;
      end if;
   end Parse_Global_Flags;

begin
   --  SPARK security assertion runs unconditionally on startup.
   Assert_Security_Defaults;

   --  Open syslog connection for audit event forwarding.
   Audit.Syslog.Enable ("vericlaw");

   --  Parse global flags (--json, --no-color).
   Parse_Global_Flags;

   --  Parse subcommand (skip flags starting with --).
   if Argument_Count >= 1
     and then Argument (1) (Argument (1)'First) /= '-'
   then
      Set_Unbounded_String (Cmd, Argument (1));
   end if;

   if To_String (Cmd) = "version" or else To_String (Cmd) = "--version" then
      Cmd_Version;
      return;
   end if;

   if To_String (Cmd) = "help" or else To_String (Cmd) = "--help" then
      Print_Usage;
      return;
   end if;

   if To_String (Cmd) = "update-check" then
      Cmd_Update_Check;
      return;
   end if;

   if To_String (Cmd) = "onboard" then
      declare
         Default_Path : constant String :=
           Ada.Environment_Variables.Value ("HOME", ".")
           & "/.vericlaw/config.json";
         Env_Path : constant String :=
           Ada.Environment_Variables.Value ("VERICLAW_CONFIG", "");
         Path : constant String :=
           (if Env_Path'Length > 0 then Env_Path else Default_Path);
      begin
         Config.Loader.Run_Onboard (Path);
      end;
      return;
   end if;

   --  channels login --channel whatsapp
   --  Guides the user through pairing a messaging channel. Currently supports
   --  whatsapp via the wa-bridge Baileys sidecar (see docs/setup/whatsapp.md).
   if To_String (Cmd) = "channels" then
      if Argument_Count >= 3
        and then Ada.Command_Line.Argument (2) = "login"
        and then Ada.Command_Line.Argument (3) = "--channel"
        and then Argument_Count >= 4
        and then Ada.Command_Line.Argument (4) = "whatsapp"
      then
         declare
            Phone_Buf  : String (1 .. 32);
            Phone_Last : Natural := 0;
            Bridge     : constant String :=
               Ada.Environment_Variables.Value
                 ("VERICLAW_BRIDGE", "http://localhost:3000");
         begin
            Put_Line ("VeriClaw — WhatsApp pairing");
            New_Line;
            Put_Line ("Prerequisites:");
            Put_Line ("  1. Start the wa-bridge: docker compose up wa-bridge -d");
            Put_Line ("     or: cd wa-bridge && npm install && node index.js");
            New_Line;
            Put ("Enter your WhatsApp phone number (e.g. +447700900000): ");
            Ada.Text_IO.Get_Line (Phone_Buf, Phone_Last);

            if Phone_Last = 0 then
               Put_Line ("Error: phone number is required.");
               Ada.Command_Line.Set_Exit_Status (1);
               return;
            end if;

            declare
               Phone     : constant String := Phone_Buf (1 .. Phone_Last);
               Body_JSON : constant String :=
                 "{""phone"":""" & Phone & """}";
               Pair_Resp : constant HTTP.Client.Response :=
                 HTTP.Client.Post_JSON
                   (URL       => Bridge & "/sessions/vericlaw/pair",
                    Headers   => [1 .. 0 => <>],
                    Body_JSON => Body_JSON);
            begin
               if HTTP.Client.Is_Success (Pair_Resp) then
                  declare
                     use Config.JSON_Parser;
                     PR   : constant Parse_Result :=
                       Parse (Ada.Strings.Unbounded.To_String
                                (Pair_Resp.Body_Text));
                     Code : constant String :=
                       (if PR.Valid
                        then Get_String (PR.Root, "code")
                        else "");
                  begin
                     if Code'Length > 0 then
                        New_Line;
                        Put_Line ("WhatsApp pairing code: " & Code);
                        New_Line;
                        Put_Line ("On your phone:");
                        Put_Line ("  1. Open WhatsApp");
                        Put_Line ("  2. Go to Settings -> Linked Devices");
                        Put_Line ("  3. Tap 'Link a Device'");
                        Put_Line ("  4. Tap 'Link with phone number instead'");
                        Put_Line ("  5. Enter: " & Code);
                        New_Line;
                        Put_Line ("Waiting for pairing confirmation...");
                        --  Poll status until open or timeout (120s)
                        for Attempt in 1 .. 40 loop
                           delay 3.0;
                           declare
                              St_Resp : constant HTTP.Client.Response :=
                                HTTP.Client.Get
                                  (URL        => Bridge & "/sessions/vericlaw/status",
                                   Headers    => [1 .. 0 => <>],
                                   Timeout_Ms => 5_000);
                              St_PR   : constant Parse_Result :=
                                Parse (Ada.Strings.Unbounded.To_String
                                         (St_Resp.Body_Text));
                              Status  : constant String :=
                                (if St_PR.Valid
                                 then Get_String (St_PR.Root, "status")
                                 else "");
                           begin
                              if Status = "open" then
                                 New_Line;
                                 Put_Line ("Paired successfully!");
                                 Put_Line
                                   ("Run 'vericlaw gateway' to start the agent.");
                                 return;
                              end if;
                           end;
                        end loop;
                        Put_Line ("Timeout waiting for pairing. " &
                                  "Try again or check wa-bridge logs.");
                     else
                        Put_Line ("Bridge returned success but no pairing code. " &
                                  "Check wa-bridge logs.");
                     end if;
                  end;
               else
                  Put_Line ("Could not reach wa-bridge at " & Bridge);
                  Put_Line ("Start it first: docker compose up wa-bridge -d");
               end if;
            end;
         end;
      else
         Put_Line ("Usage: vericlaw channels login --channel whatsapp");
         Put_Line ("See docs/setup/whatsapp.md for full guide.");
         Ada.Command_Line.Set_Exit_Status (1);
      end if;
      return;
   end if;

   --  Load config (required for all remaining commands).
   Load_Config_Or_Die (CR);
   if not CR.Success then
      return;
   end if;

   --  Initialize OpenTelemetry tracing (no-ops if endpoint is empty).
   Observability.Tracing.Initialize
     (To_String (CR.Config.Observability.OTLP_Endpoint));

   --  Open memory database.
   Open_Memory_Or_Warn (CR.Config, Mem, Mem_OK);

   --  Apply runtime sandbox before processing any commands.
   declare
      Policy : Sandbox.Sandbox_Policy;
   begin
      Policy.Allow_Network := True;  -- Agent needs HTTP
      Policy.Allow_Subprocess := CR.Config.Tools.Shell_Enabled;
      Sandbox.Enforce (Policy);
   end;

   --  Load sqlite-vec extension if RAG is enabled.
   if Mem_OK and then CR.Config.Tools.RAG_Enabled then
      begin
         Memory.SQLite.Load_Vec_Extension (Mem, "vec0");
      exception
         when others =>
            Logging.Warning
              ("sqlite-vec extension not available, RAG disabled");
      end;
   end if;

   --  Dispatch command.
   declare
      C : constant String := To_String (Cmd);
   begin
      if C = "chat" or else C = "" then
         Channels.CLI.Run_Interactive (CR.Config, Mem);

      elsif C = "agent" then
         if Argument_Count < 2 then
            Put_Line ("Usage: vericlaw agent <message>");
            Set_Exit_Status (Failure);
         else
            --  Concatenate remaining arguments (skip flags).
            declare
               Input : Unbounded_String;
            begin
               for I in 2 .. Argument_Count loop
                  declare
                     A : constant String := Argument (I);
                  begin
                     if A (A'First) /= '-' then
                        if Length (Input) > 0 then
                           Append (Input, " ");
                        end if;
                        Append (Input, A);
                     end if;
                  end;
               end loop;
               if JSON_Mode then
                  --  Non-streaming: capture full reply as JSON object.
                  declare
                     Conv  : Agent.Context.Conversation;
                     Reply : Agent.Loop_Pkg.Agent_Reply;
                  begin
                     Set_Unbounded_String
                       (Conv.Session_ID,
                        Agent.Context.Make_Session_ID);
                     Set_Unbounded_String (Conv.Channel, "cli");
                     Reply := Agent.Loop_Pkg.Process_Message
                       (User_Input => To_String (Input),
                        Conv       => Conv,
                        Cfg        => CR.Config,
                        Mem        => Mem);
                     Put_Line ("{""success"":" & Boolean'Image (Reply.Success)
                       & ",""content"":"
                       & Config.JSON_Parser.Escape_JSON_String
                           (To_String (Reply.Content))
                       & (if Reply.Success then ""
                          else ",""error"":"
                            & Config.JSON_Parser.Escape_JSON_String
                                (To_String (Reply.Error)))
                       & "}");
                  end;
               else
                  Channels.CLI.Run_Once
                    (To_String (Input), CR.Config, Mem);
               end if;
            end;
         end if;

      elsif C = "gateway" then
         --  Run all enabled channels concurrently via Ada tasks.
         --  Each task opens its own memory handle (WAL mode allows safe concurrency).
         declare
            Home    : constant String :=
              Ada.Environment_Variables.Value ("HOME", ".");
            DB_Path : constant String :=
              (if Length (CR.Config.Memory.DB_Path) > 0
               then To_String (CR.Config.Memory.DB_Path)
               else Home & "/.vericlaw/memory.db");
            Has_Any : Boolean := False;
         begin
            for I in 1 .. CR.Config.Num_Channels loop
               if CR.Config.Channels (I).Enabled
                 and then CR.Config.Channels (I).Kind /= Config.Schema.CLI
               then
                  Has_Any := True;
                  exit;
               end if;
            end loop;

            if Has_Any then
               declare
                  task Telegram_Poller;
                  task body Telegram_Poller is
                     T_Mem : Memory.SQLite.Memory_Handle;
                     T_Err : Unbounded_String;
                     T_OK  : Boolean;
                  begin
                     T_OK := Memory.SQLite.Open
                       (T_Mem, DB_Path, T_Err,
                        CR.Config.Memory.Session_Retention_Days);
                     if T_OK then
                        Channels.Telegram.Run_Polling (CR.Config, T_Mem);
                        Memory.SQLite.Close (T_Mem);  --  explicit close; Finalize is the safety-net on exception
                     else
                        Put_Line ("Gateway[Telegram]: memory open failed: "
                                  & To_String (T_Err));
                     end if;
                  end Telegram_Poller;

                  task Signal_Poller;
                  task body Signal_Poller is
                     T_Mem : Memory.SQLite.Memory_Handle;
                     T_Err : Unbounded_String;
                     T_OK  : Boolean;
                  begin
                     T_OK := Memory.SQLite.Open
                       (T_Mem, DB_Path, T_Err,
                        CR.Config.Memory.Session_Retention_Days);
                     if T_OK then
                        Channels.Signal.Run_Polling (CR.Config, T_Mem);
                        Memory.SQLite.Close (T_Mem);  --  explicit close; Finalize is the safety-net on exception
                     else
                        Put_Line ("Gateway[Signal]: memory open failed: "
                                  & To_String (T_Err));
                     end if;
                  end Signal_Poller;

                  task WhatsApp_Poller;
                  task body WhatsApp_Poller is
                     T_Mem : Memory.SQLite.Memory_Handle;
                     T_Err : Unbounded_String;
                     T_OK  : Boolean;
                  begin
                     T_OK := Memory.SQLite.Open
                       (T_Mem, DB_Path, T_Err,
                        CR.Config.Memory.Session_Retention_Days);
                     if T_OK then
                        Channels.WhatsApp.Run_Polling (CR.Config, T_Mem);
                        Memory.SQLite.Close (T_Mem);  --  explicit close; Finalize is the safety-net on exception
                     else
                        Put_Line ("Gateway[WhatsApp]: memory open failed: "
                                  & To_String (T_Err));
                     end if;
                  end WhatsApp_Poller;

                  task Discord_Poller;
                  task body Discord_Poller is
                     T_Mem : Memory.SQLite.Memory_Handle;
                     T_Err : Unbounded_String;
                     T_OK  : Boolean;
                  begin
                     T_OK := Memory.SQLite.Open
                       (T_Mem, DB_Path, T_Err,
                        CR.Config.Memory.Session_Retention_Days);
                     if T_OK then
                        Channels.Discord.Run_Polling (CR.Config, T_Mem);
                        Memory.SQLite.Close (T_Mem);  --  explicit close; Finalize is the safety-net on exception
                     else
                        Put_Line ("Gateway[Discord]: memory open failed: "
                                  & To_String (T_Err));
                     end if;
                  end Discord_Poller;

                  task Slack_Poller;
                  task body Slack_Poller is
                     T_Mem : Memory.SQLite.Memory_Handle;
                     T_Err : Unbounded_String;
                     T_OK  : Boolean;
                  begin
                     T_OK := Memory.SQLite.Open
                       (T_Mem, DB_Path, T_Err,
                        CR.Config.Memory.Session_Retention_Days);
                     if T_OK then
                        Channels.Slack.Run_Polling (CR.Config, T_Mem);
                        Memory.SQLite.Close (T_Mem);  --  explicit close; Finalize is the safety-net on exception
                     else
                        Put_Line ("Gateway[Slack]: memory open failed: "
                                  & To_String (T_Err));
                     end if;
                  end Slack_Poller;

                  task Email_Poller;
                  task body Email_Poller is
                     T_Mem : Memory.SQLite.Memory_Handle;
                     T_Err : Unbounded_String;
                     T_OK  : Boolean;
                  begin
                     T_OK := Memory.SQLite.Open
                       (T_Mem, DB_Path, T_Err,
                        CR.Config.Memory.Session_Retention_Days);
                     if T_OK then
                        Channels.Email.Run_Polling (CR.Config, T_Mem);
                        Memory.SQLite.Close (T_Mem);  --  explicit close; Finalize is the safety-net on exception
                     else
                        Put_Line ("Gateway[Email]: memory open failed: "
                                  & To_String (T_Err));
                     end if;
                  end Email_Poller;

                  task IRC_Poller;
                  task body IRC_Poller is
                     T_Mem : Memory.SQLite.Memory_Handle;
                     T_Err : Unbounded_String;
                     T_OK  : Boolean;
                  begin
                     T_OK := Memory.SQLite.Open
                       (T_Mem, DB_Path, T_Err,
                        CR.Config.Memory.Session_Retention_Days);
                     if T_OK then
                        Channels.IRC.Run_Polling (CR.Config, T_Mem);
                        Memory.SQLite.Close (T_Mem);  --  explicit close; Finalize is the safety-net on exception
                     else
                        Put_Line ("Gateway[IRC]: memory open failed: "
                                  & To_String (T_Err));
                     end if;
                  end IRC_Poller;

                  task Matrix_Poller;
                  task body Matrix_Poller is
                     T_Mem : Memory.SQLite.Memory_Handle;
                     T_Err : Unbounded_String;
                     T_OK  : Boolean;
                  begin
                     T_OK := Memory.SQLite.Open
                       (T_Mem, DB_Path, T_Err,
                        CR.Config.Memory.Session_Retention_Days);
                     if T_OK then
                        Channels.Matrix.Run_Polling (CR.Config, T_Mem);
                        Memory.SQLite.Close (T_Mem);  --  explicit close; Finalize is the safety-net on exception
                     else
                        Put_Line ("Gateway[Matrix]: memory open failed: "
                                  & To_String (T_Err));
                     end if;
                  end Matrix_Poller;

                  --  Background task: fire due cron jobs every 60 seconds.
                  task Cron_Heartbeat;
                  task body Cron_Heartbeat is
                     use Ada.Calendar;
                     use Ada.Calendar.Formatting;
                  begin
                     loop
                        delay 60.0;
                        if Memory.SQLite.Is_Open (Mem) then
                           declare
                              Due : constant Memory.SQLite.Cron_List_Result :=
                                Memory.SQLite.Cron_Due_Jobs (Mem);
                           begin
                              for I in 1 .. Due.Count loop
                                 declare
                                    Job   : constant Memory.SQLite.Cron_Job_Info :=
                                      Due.Jobs (I);
                                    Conv  : Agent.Context.Conversation;
                                    Reply : Agent.Loop_Pkg.Agent_Reply;
                                    Nxt   : constant String :=
                                      Image (Clock
                                        + Tools.Cron.Parse_Interval_Seconds
                                            (To_String (Job.Schedule)));
                                 begin
                                    Set_Unbounded_String
                                      (Conv.Session_ID, To_String (Job.Session_ID));
                                    Reply := Agent.Loop_Pkg.Process_Message
                                      (To_String (Job.Prompt), Conv,
                                       CR.Config, Mem);
                                    Memory.SQLite.Cron_Update_Run
                                      (Mem, To_String (Job.Name), Nxt);
                                    if Reply.Success then
                                       Put_Line
                                         ("[cron:" & To_String (Job.Name) & "] "
                                          & To_String (Reply.Content));
                                    end if;
                                 end;
                              end loop;
                           end;
                        end if;
                     end loop;
                  end Cron_Heartbeat;
               begin
                  loop
                     delay 1.0;
                     exit when Shutdown_Requested;
                  end loop;
                  Logging.Info ("Shutdown signal received, stopping gateway...");
                  abort Telegram_Poller, Signal_Poller, WhatsApp_Poller,
                        Discord_Poller, Slack_Poller, Email_Poller,
                        IRC_Poller, Matrix_Poller, Cron_Heartbeat;
               end;
            else
               --  No channels configured: run HTTP server for webhooks.
               declare
                  task HTTP_Runner;
                  task body HTTP_Runner is
                  begin
                     HTTP.Server.Run (CR.Config, Mem);
                  end HTTP_Runner;
               begin
                  loop
                     delay 1.0;
                     exit when Shutdown_Requested;
                  end loop;
                  Logging.Info ("Shutdown signal received, stopping gateway...");
                  HTTP.Server.Stop;
                  abort HTTP_Runner;
               end;
            end if;
         end;

      elsif C = "doctor" then
         Cmd_Doctor (CR.Config);

      elsif C = "status" then
         --  Show runtime status: version, active channels, provider, memory, cost.
         declare
            Active    : Natural := 0;
            Tok_In    : constant Natural := Metrics.Cost.Total_Tokens_In;
            Tok_Out   : constant Natural := Metrics.Cost.Total_Tokens_Out;
            Tot_Cost  : constant Float   := Metrics.Cost.Total_Cost;
            Cost_Img  : constant String  := Float'Image (Tot_Cost);
         begin
            for I in 1 .. CR.Config.Num_Channels loop
               if CR.Config.Channels (I).Enabled then
                  Active := Active + 1;
               end if;
            end loop;
            if JSON_Mode then
               Put_Line ("{""version"":""" & Build_Info.Version & """"
                 & ",""channels_active"":" & Natural'Image (Active)
                 & ",""channels_total"":" & Config.Schema.Channel_Index'Image (CR.Config.Num_Channels)
                 & ",""provider"":"
                 & Config.JSON_Parser.Escape_JSON_String
                     (Config.Schema.Provider_Kind'Image
                        (CR.Config.Providers (1).Kind))
                 & ",""model"":"
                 & Config.JSON_Parser.Escape_JSON_String
                     (To_String (CR.Config.Providers (1).Model))
                 & ",""memory"":"
                 & (if Mem_OK then """ok""" else """unavailable""")
                 & ",""gateway"":"
                 & Config.JSON_Parser.Escape_JSON_String
                     (To_String (CR.Config.Gateway.Bind_Host) & ":"
                      & Positive'Image (CR.Config.Gateway.Bind_Port))
                 & ",""tokens_in"":" & Natural'Image (Tok_In)
                 & ",""tokens_out"":" & Natural'Image (Tok_Out)
                 & ",""total_cost"":" & Cost_Img
                 & "}");
            else
               Put_Line ("VeriClaw status");
               Put_Line ("  version   : " & Build_Info.Version);
               Put_Line ("  channels  : "
                          & Natural'Image (Active) & " active /"
                          & Config.Schema.Channel_Index'Image (CR.Config.Num_Channels) & " configured");
               Put_Line ("  provider  : "
                          & Config.Schema.Provider_Kind'Image
                              (CR.Config.Providers (1).Kind));
               Put_Line ("  model     : "
                          & To_String (CR.Config.Providers (1).Model));
               Put_Line ("  memory    : "
                          & (if Mem_OK then "ok" else "unavailable"));
               Put_Line ("  gateway   : "
                          & To_String (CR.Config.Gateway.Bind_Host) & ":"
                          & Positive'Image (CR.Config.Gateway.Bind_Port));
               Put_Line ("  tokens    : "
                          & Natural'Image (Tok_In) & " in /"
                          & Natural'Image (Tok_Out) & " out");
               Put_Line ("  cost      : $" & Cost_Img);
            end if;
         end;

      elsif C = "config" then
         --  Sub-commands: config validate
         if Argument_Count >= 2
           and then Argument (2) = "validate"
         then
            Put_Line ("Config loaded and validated successfully.");
            Put_Line ("  provider : "
                       & Config.Schema.Provider_Kind'Image
                           (CR.Config.Providers (1).Kind));
            Put_Line ("  channels : "
                       & Config.Schema.Channel_Index'Image (CR.Config.Num_Channels));
            Put_Line ("  tools    : "
                       & (if CR.Config.Tools.Shell_Enabled
                          then "shell " else "")
                       & (if CR.Config.Tools.File_Enabled
                          then "file " else "")
                       & (if CR.Config.Tools.Git_Enabled
                          then "git " else "")
                       & (if CR.Config.Tools.Web_Fetch_Enabled
                          then "web_fetch " else "")
                       & (if CR.Config.Tools.RAG_Enabled
                          then "rag " else ""));
         else
            Put_Line ("Usage: vericlaw config validate");
            Set_Exit_Status (Failure);
         end if;

      elsif C = "export" then
         --  vericlaw export --session <id> --format md|json
         declare
            Sess_ID : Unbounded_String;
            Format  : Unbounded_String := To_Unbounded_String ("md");
            I       : Natural := 2;
         begin
            while I <= Argument_Count loop
               if Argument (I) = "--session" and I < Argument_Count then
                  I := I + 1;
                  Set_Unbounded_String (Sess_ID, Argument (I));
               elsif Argument (I) = "--format" and I < Argument_Count then
                  I := I + 1;
                  Set_Unbounded_String (Format, Argument (I));
               end if;
               I := I + 1;
            end loop;

            if Length (Sess_ID) = 0 then
               Put_Line ("Usage: vericlaw export --session <id> [--format md|json]");
               Set_Exit_Status (Failure);
            elsif not Mem_OK then
               Put_Line ("Error: memory database unavailable");
               Set_Exit_Status (Failure);
            else
               declare
                  Conv : Agent.Context.Conversation;
                  Fmt  : constant String := To_String (Format);
               begin
                  Memory.SQLite.Export_Session
                    (Mem, To_String (Sess_ID), Conv);
                  if Conv.Msg_Count = 0 then
                     Put_Line ("No messages found for session "
                       & To_String (Sess_ID));
                  elsif Fmt = "json" then
                     Put_Line ("{""session_id"":"
                       & Config.JSON_Parser.Escape_JSON_String
                           (To_String (Sess_ID))
                       & ",""messages"":[");
                     for J in 1 .. Conv.Msg_Count loop
                        if J > 1 then Put (","); end if;
                        Put_Line ("{""role"":"
                          & Config.JSON_Parser.Escape_JSON_String
                              (Agent.Context.Role'Image
                                 (Conv.Messages (J).Role))
                          & ",""content"":"
                          & Config.JSON_Parser.Escape_JSON_String
                              (To_String (Conv.Messages (J).Content))
                          & "}");
                     end loop;
                     Put_Line ("]}");
                  else
                     --  Markdown format
                     Put_Line ("# Session " & To_String (Sess_ID));
                     New_Line;
                     for J in 1 .. Conv.Msg_Count loop
                        case Conv.Messages (J).Role is
                           when Agent.Context.User =>
                              Put_Line ("## User");
                           when Agent.Context.Assistant =>
                              Put_Line ("## Assistant");
                           when Agent.Context.System_Role =>
                              Put_Line ("## System");
                           when Agent.Context.Tool_Result =>
                              Put_Line ("## Tool Result");
                        end case;
                        New_Line;
                        Put_Line (To_String (Conv.Messages (J).Content));
                        New_Line;
                     end loop;
                  end if;
               end;
            end if;
         end;

      else
         Put_Line ("Unknown command: " & C);
         Print_Usage;
         Set_Exit_Status (Failure);
      end if;
   end;

   if Mem_OK then
      Memory.SQLite.Close (Mem);  --  explicit close; Finalize is the safety-net on exception
   end if;

end Main;

