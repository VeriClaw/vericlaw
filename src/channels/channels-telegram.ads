--  Telegram Bot API channel.
--  Dev mode: long-polling (getUpdates).
--  Prod mode: webhook receiver via HTTP.Server.
--  Uses channels-security.ads SPARK policy for allowlist/rate-limit checks.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Config.Schema;
with Memory.SQLite;

package Channels.Telegram is

   --  Start long-polling loop (blocks; run in its own task or main thread).
   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle);

   --  Process a single Telegram update JSON (used by webhook receiver).
   --  Returns the reply text to send back (empty = no reply needed).
   function Process_Update
     (Update_JSON : String;
      Cfg         : Config.Schema.Agent_Config;
      Mem         : Memory.SQLite.Memory_Handle) return String;

   --  Send a text message to a Telegram chat.
   function Send_Message
     (Bot_Token : String;
      Chat_ID   : String;
      Text      : String) return Boolean;

end Channels.Telegram;
