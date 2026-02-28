--  Matrix channel via matrix-bridge (matrix-js-sdk Node.js bridge).
--  Bridge connects to a Matrix homeserver, queues incoming messages, and
--  exposes a REST API on port 3006; VeriClaw polls and replies via HTTP.

with Config.Schema;
with Memory.SQLite;

package Channels.Matrix
  with SPARK_Mode => Off
is

   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle);

   function Send_Message
     (Bridge_URL : String;
      Room       : String;
      Text       : String) return Boolean;

end Channels.Matrix;
