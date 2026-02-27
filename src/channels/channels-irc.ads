--  IRC channel via irc-bridge (irc-framework Node.js bridge).
--  Bridge connects to IRC server, queues incoming messages, and exposes a
--  REST API on port 3005; VeriClaw polls and replies via HTTP.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Config.Schema;
with Memory.SQLite;

package Channels.IRC
  with SPARK_Mode => Off
is

   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle);

   function Send_Message
     (Bridge_URL : String;
      Target     : String;
      Text       : String) return Boolean;

end Channels.IRC;
