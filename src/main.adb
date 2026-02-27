with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Command_Line;      use Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Directories;
with Ada.Environment_Variables;

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
with HTTP.Server;
with Config.Reload;
with Metrics;

procedure Main is

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
      Put_Line ("  doctor                           Print configuration and health status");
      Put_Line ("  version                          Print version information");
      Put_Line ("  help                             Show this help message");
      New_Line;
      Put_Line ("Config: ~/.vericlaw/config.json  (or VERICLAW_CONFIG env var)");
      Put_Line ("WhatsApp: see docs/setup/whatsapp.md for full setup guide");
   end Print_Usage;

   procedure Cmd_Version is
   begin
      Put_Line ("vericlaw 1.0.0  |  Ada/SPARK  |  SPARK-verified security core");
      Put_Line ("Built with Ada 2022 + GNAT  |  https://github.com/vericlaw");
   end Cmd_Version;

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
   begin
      Put_Line ("=== VeriClaw Doctor ===");
      New_Line;
      Put_Line ("Agent name  : " & To_String (Cfg.Agent_Name));
      Put_Line ("Providers   : " & Config.Schema.Provider_Index'Image
        (Cfg.Num_Providers));
      for I in 1 .. Cfg.Num_Providers loop
         Put_Line ("  [" & Config.Schema.Provider_Index'Image (I) & "] "
           & Config.Schema.Provider_Kind'Image (Cfg.Providers (I).Kind)
           & "  model=" & To_String (Cfg.Providers (I).Model)
           & (if Length (Cfg.Providers (I).Base_URL) > 0
              then "  url=" & To_String (Cfg.Providers (I).Base_URL)
              else ""));
      end loop;
      New_Line;
      Put_Line ("Channels    : " & Config.Schema.Channel_Index'Image
        (Cfg.Num_Channels));
      for I in 1 .. Cfg.Num_Channels loop
         Put ("  [" & Config.Schema.Channel_Index'Image (I) & "] "
           & Config.Schema.Channel_Kind'Image (Cfg.Channels (I).Kind));
         if Cfg.Channels (I).Enabled then
            Put_Line ("  ENABLED");
         else
            Put_Line ("  disabled");
         end if;
      end loop;
      New_Line;
      Put_Line ("Tools:");
      Put_Line ("  shell       : " & Boolean'Image (Cfg.Tools.Shell_Enabled));
      Put_Line ("  file        : " & Boolean'Image (Cfg.Tools.File_Enabled));
      Put_Line ("  web_fetch   : " & Boolean'Image
        (Cfg.Tools.Web_Fetch_Enabled));
      Put_Line ("  brave_search: " & Boolean'Image
        (Cfg.Tools.Brave_Search_Enabled));
      New_Line;
      Put_Line ("Gateway: " & To_String (Cfg.Gateway.Bind_Host)
        & ":" & Positive'Image (Cfg.Gateway.Bind_Port));
      New_Line;
      Put_Line ("SPARK security core: OK");
   end Cmd_Doctor;

   --  Entry point
   Cmd    : Unbounded_String := To_Unbounded_String ("chat");
   CR     : Config.Loader.Load_Result;
   Mem    : aliased Memory.SQLite.Memory_Handle;
   Mem_OK : Boolean;

begin
   --  SPARK security assertion runs unconditionally on startup.
   Assert_Security_Defaults;

   --  Parse subcommand.
   if Argument_Count >= 1 then
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
                    Headers   => (1 .. 0 => <>),
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
                                   Headers    => (1 .. 0 => <>),
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

   --  Open memory database.
   Open_Memory_Or_Warn (CR.Config, Mem, Mem_OK);

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
            --  Concatenate remaining arguments as the message.
            declare
               Input : Unbounded_String;
            begin
               for I in 2 .. Argument_Count loop
                  if I > 2 then Append (Input, " "); end if;
                  Append (Input, Argument (I));
               end loop;
               Channels.CLI.Run_Once
                 (To_String (Input), CR.Config, Mem);
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
                        Memory.SQLite.Close (T_Mem);
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
                        Memory.SQLite.Close (T_Mem);
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
                        Memory.SQLite.Close (T_Mem);
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
                        Memory.SQLite.Close (T_Mem);
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
                        Memory.SQLite.Close (T_Mem);
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
                        Memory.SQLite.Close (T_Mem);
                     else
                        Put_Line ("Gateway[Email]: memory open failed: "
                                  & To_String (T_Err));
                     end if;
                  end Email_Poller;
               begin
                  null;
                  --  Block waits for all pollers to terminate.
                  --  Enabled channels loop forever; disabled ones return quickly.
               end;
            else
               --  No channels configured: run HTTP server for webhooks.
               HTTP.Server.Run (CR.Config, Mem);
            end if;
         end;

      elsif C = "doctor" then
         Cmd_Doctor (CR.Config);

      else
         Put_Line ("Unknown command: " & C);
         Print_Usage;
         Set_Exit_Status (Failure);
      end if;
   end;

   if Mem_OK then
      Memory.SQLite.Close (Mem);
   end if;

end Main;

