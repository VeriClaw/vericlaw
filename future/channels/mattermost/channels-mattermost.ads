--  Mattermost channel via mattermost-bridge (Node.js bridge).
--  Bridge: mattermost-bridge/
--  Default bridge URL: http://localhost:3008
--  Polls GET /receive for incoming messages.

with Config.Schema;
with Memory.SQLite;

package Channels.Mattermost
  with SPARK_Mode => Off
is

   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle);

   --  Send a reply to a Mattermost channel.
   --  Chan_ID : Mattermost channel ID
   --  Text    : message body
   function Send_Message
     (Bridge_URL : String;
      Chan_ID    : String;
      Text       : String) return Boolean;

end Channels.Mattermost;
