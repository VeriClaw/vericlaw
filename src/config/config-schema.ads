--  VeriClaw configuration schema.
--  All records are designed so the safe-defaults constructor produces
--  values that satisfy Security.Defaults constraints.
--  Config is loaded once at startup and treated as immutable thereafter.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Config.Schema is

   --  -----------------------------------------------------------------------
   --  Provider config
   --  -----------------------------------------------------------------------

   type Provider_Kind is
     (OpenAI, Anthropic, Azure_Foundry, OpenAI_Compatible, Gemini);

   type Provider_Config is record
      Kind       : Provider_Kind       := OpenAI;
      API_Key    : Unbounded_String;           -- never logged
      Base_URL   : Unbounded_String;           -- for Azure/Compat overrides
      Model      : Unbounded_String;
      Deployment : Unbounded_String;           -- Azure: deployment name
      API_Version : Unbounded_String;          -- Azure: e.g. "2024-02-15-preview"
      Max_Tokens : Positive              := 4096;
      Timeout_Ms : Positive              := 60_000;
   end record;

   Max_Providers : constant := 8;
   type Provider_Index is range 1 .. Max_Providers;
   type Provider_Array is array (Provider_Index range <>) of Provider_Config;

   --  -----------------------------------------------------------------------
   --  Channel config
   --  -----------------------------------------------------------------------

   type Channel_Kind is
     (CLI, Telegram, Signal, WhatsApp, Discord, Slack, Email);

   type Channel_Config is record
      Kind       : Channel_Kind    := CLI;
      Enabled    : Boolean         := False;
      Token      : Unbounded_String;   -- bot token / auth credential
      Bridge_URL : Unbounded_String;   -- for Signal/WhatsApp bridge
      Allowlist  : Unbounded_String;   -- comma-separated user IDs; empty = deny all
      Max_RPS    : Positive        := 5;
   end record;

   Max_Channels : constant := 8;
   type Channel_Index is range 1 .. Max_Channels;
   type Channel_Array is array (Channel_Index range <>) of Channel_Config;

   --  -----------------------------------------------------------------------
   --  Tool config
   --  -----------------------------------------------------------------------

   type Tool_Config is record
      Shell_Enabled      : Boolean := False;
      File_Enabled       : Boolean := True;
      Web_Fetch_Enabled  : Boolean := False;
      Brave_Search_Enabled : Boolean := False;
      Brave_API_Key      : Unbounded_String;
      MCP_Bridge_URL     : Unbounded_String;  -- e.g. "http://mcp-bridge:3004"
   end record;

   --  -----------------------------------------------------------------------
   --  Memory config
   --  -----------------------------------------------------------------------

   type Memory_Config is record
      DB_Path               : Unbounded_String;  -- "" = ~/.vericlaw/memory.db
      Max_History           : Positive := 50;    -- messages kept per session
      Facts_Enabled         : Boolean  := True;
      Session_Retention_Days : Natural := 30;    -- auto-prune sessions older than N days (0 = never)
   end record;

   --  -----------------------------------------------------------------------
   --  Gateway / HTTP server config
   --  -----------------------------------------------------------------------

   type Gateway_Config is record
      Bind_Host    : Unbounded_String;  -- default: "127.0.0.1"
      Bind_Port    : Positive  := 8787;
      TLS_Cert     : Unbounded_String;
      TLS_Key      : Unbounded_String;
   end record;

   --  -----------------------------------------------------------------------
   --  Top-level agent config
   --  -----------------------------------------------------------------------

   type Agent_Config is record
      --  Identity
      Agent_Name      : Unbounded_String;
      System_Prompt   : Unbounded_String;

      --  Providers (first entry = primary)
      Num_Providers   : Provider_Index := 1;
      Providers       : Provider_Array (1 .. Max_Providers) :=
        (others => <>);

      --  Channels
      Num_Channels    : Channel_Index := 1;
      Channels        : Channel_Array (1 .. Max_Channels) :=
        (1 => (Kind => CLI, Enabled => True, others => <>),
         others => <>);

      --  Subsystems
      Tools   : Tool_Config;
      Memory  : Memory_Config;
      Gateway : Gateway_Config;
   end record;

   function Default_Config return Agent_Config;

end Config.Schema;
