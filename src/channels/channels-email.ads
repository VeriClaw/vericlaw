--  Email channel via email-bridge (IMAP/SMTP Node.js bridge).
--  Bridge polls IMAP inbox every 30 seconds for unread messages.
--  Exposes REST API on port 3003; VeriClaw polls and replies via HTTP.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Config.Schema;
with Memory.SQLite;

package Channels.Email
  with SPARK_Mode => Off
is

   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle);

   function Send_Message
     (Bridge_URL : String;
      To_Addr    : String;
      Subject    : String;
      Text       : String) return Boolean;

end Channels.Email;
