--  Slack channel via Slack-Bridge (Node.js Bolt/Socket Mode bridge).
--  Bridge: slack-bridge/
--  Default bridge URL: http://localhost:3001
--  Polls GET /sessions/slack/messages for incoming messages.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Config.Schema;
with Memory.SQLite;

pragma SPARK_Mode (Off);
package Channels.Slack is

   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle);

   --  Send a reply to a Slack channel.
   --  Chan_ID   : Slack channel ID (e.g. "C0123456789")
   --  Text      : message body
   --  Thread_TS : timestamp of the parent message (replies in-thread)
   function Send_Message
     (Bridge_URL : String;
      Chan_ID    : String;
      Text       : String;
      Thread_TS  : String) return Boolean;

end Channels.Slack;
