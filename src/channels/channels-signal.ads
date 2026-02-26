--  Signal channel via signal-cli REST bridge.
--  Requires signal-cli running with REST API enabled:
--    java -jar signal-cli.jar daemon --http=127.0.0.1:8080
--  Polls /v1/receive/<number> for incoming messages.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Config.Schema;
with Memory.SQLite;

package Channels.Signal is

   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle);

   function Process_Message_JSON
     (Msg_JSON : String;
      Cfg      : Config.Schema.Agent_Config;
      Mem      : Memory.SQLite.Memory_Handle) return String;

   function Send_Message
     (Bridge_URL  : String;
      Sender      : String;
      Recipient   : String;
      Message     : String) return Boolean;

end Channels.Signal;
