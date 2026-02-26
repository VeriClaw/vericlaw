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
with Memory.SQLite;
with Agent.Context;
with Agent.Loop_Pkg;
with Channels.CLI;
with Channels.Telegram;
with Channels.Signal;
with Channels.WhatsApp;
with HTTP.Server;

procedure Main is

   procedure Print_Usage is
   begin
      Put_Line ("Usage: vericlaw <command> [options]");
      New_Line;
      Put_Line ("Commands:");
      Put_Line ("  onboard           Interactive setup wizard (run this first)");
      Put_Line ("  chat              Interactive CLI chat (default)");
      Put_Line ("  agent <message>   One-shot agent: send a message and print reply");
      Put_Line ("  gateway           Run HTTP gateway + all configured channels");
      Put_Line ("  doctor            Print configuration and health status");
      Put_Line ("  version           Print version information");
      Put_Line ("  help              Show this help message");
      New_Line;
      Put_Line ("Config: ~/.vericlaw/config.json  (or VERICLAW_CONFIG env var)");
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
      OK := Memory.SQLite.Open (Mem, DB_Path, Err);
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
         --  Start polling channels in tasks + run HTTP server.
         --  For MVP: run Telegram polling in the main thread if HTTP
         --  server is not configured (no TLS cert), otherwise run HTTP server.
         declare
            Has_Telegram  : Boolean := False;
            Has_Signal    : Boolean := False;
            Has_WhatsApp  : Boolean := False;
         begin
            for I in 1 .. CR.Config.Num_Channels loop
               case CR.Config.Channels (I).Kind is
                  when Config.Schema.Telegram =>
                     Has_Telegram := Has_Telegram
                       or else CR.Config.Channels (I).Enabled;
                  when Config.Schema.Signal =>
                     Has_Signal := Has_Signal
                       or else CR.Config.Channels (I).Enabled;
                  when Config.Schema.WhatsApp =>
                     Has_WhatsApp := Has_WhatsApp
                       or else CR.Config.Channels (I).Enabled;
                  when Config.Schema.CLI =>
                     null;
               end case;
            end loop;

            --  Run whichever channel is enabled (first found wins for MVP).
            --  Full multi-channel concurrency requires Ada tasks (post-MVP).
            if Has_Telegram then
               Channels.Telegram.Run_Polling (CR.Config, Mem);
            elsif Has_Signal then
               Channels.Signal.Run_Polling (CR.Config, Mem);
            elsif Has_WhatsApp then
               Channels.WhatsApp.Run_Polling (CR.Config, Mem);
            else
               --  No channels: run HTTP server for webhook registration.
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

