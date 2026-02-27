--  WhatsApp channel via WA-Bridge (Baileys-based Node.js bridge).
--  Bridge repo: github.com/chrishubert/whatsapp-web-api (or equivalent).
--  Default bridge URL: http://localhost:3000
--  Polls GET /sessions/{session}/messages for incoming messages.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Config.Schema;
with Memory.SQLite;

package Channels.WhatsApp
  with SPARK_Mode => Off
is

   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle);

   function Send_Message
     (Bridge_URL : String;
      Session_ID : String;
      Chat_ID    : String;
      Message    : String) return Boolean;

end Channels.WhatsApp;
