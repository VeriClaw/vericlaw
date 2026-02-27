pragma SPARK_Mode (Off);
package Logging is

   type Log_Level is (Debug, Info, Warning, Error);

   --  Minimum log level: messages below this threshold are discarded.
   --  Defaults to Info; set via VERICLAW_LOG_LEVEL env var ("debug","info","warning","error").
   procedure Set_Min_Level (Level : Log_Level);
   function  Get_Min_Level return Log_Level;

   --  Emit one JSON log line to stderr:
   --  {"ts":"2026-02-27T14:51:23Z","level":"info","msg":"...","req_id":"...","ctx":{...}}
   --  Thread-safe: protected by an internal mutex task.
   procedure Log
     (Level   : Log_Level;
      Message : String;
      Context : String := "";  -- optional JSON object fragment
      Req_ID  : String := ""); -- optional request correlation ID

   --  Convenience wrappers
   procedure Info    (Message : String; Context : String := ""; Req_ID : String := "");
   procedure Warning (Message : String; Context : String := ""; Req_ID : String := "");
   procedure Error   (Message : String; Context : String := ""; Req_ID : String := "");
   procedure Debug   (Message : String; Context : String := ""; Req_ID : String := "");

end Logging;
