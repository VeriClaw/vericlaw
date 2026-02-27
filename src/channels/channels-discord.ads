--  Discord channel via discord-bridge (discord.js Gateway Node.js bridge).
--  Bridge connects to Discord Gateway WebSocket and exposes a REST API.
--  Default bridge URL: http://localhost:3002
--  Polls GET /sessions/discord/messages for incoming messages.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Config.Schema;
with Memory.SQLite;

pragma SPARK_Mode (Off);
package Channels.Discord is

   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle);

   function Send_Message
     (Bridge_URL : String;
      Channel_ID : String;
      Content    : String;
      Reply_To   : String) return Boolean;

end Channels.Discord;
