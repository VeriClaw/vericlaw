pragma SPARK_Mode (Off);
package Logging is

   type Log_Level is (Debug, Info, Warning, Error);

   --  Emit one JSON log line to stderr:
   --  {"ts":"2026-02-27T14:51:23Z","level":"info","msg":"...","ctx":{...}}
   --  Thread-safe: protected by an internal mutex task.
   procedure Log
     (Level   : Log_Level;
      Message : String;
      Context : String := "");  -- optional JSON object fragment, e.g. "\"channel\":\"telegram\""

   --  Convenience wrappers
   procedure Info    (Message : String; Context : String := "");
   procedure Warning (Message : String; Context : String := "");
   procedure Error   (Message : String; Context : String := "");
   procedure Debug   (Message : String; Context : String := "");

end Logging;
