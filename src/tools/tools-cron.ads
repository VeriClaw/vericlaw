--  Cron scheduler tool: schedule recurring AI tasks.
--  Jobs are persisted in the memory database and ticked by the heartbeat.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Memory.SQLite;

package Tools.Cron
  with SPARK_Mode => Off
is

   type Cron_Result is record
      Success : Boolean := False;
      Output  : Unbounded_String;
      Error   : Unbounded_String;
   end record;

   --  Parse a schedule string ("5m", "1h", "24h", "7d") into a Duration.
   function Parse_Interval_Seconds (Schedule : String) return Duration;

   --  Add or replace a cron job.
   function Cron_Add
     (Mem        : Memory.SQLite.Memory_Handle;
      Name       : String;
      Schedule   : String;
      Prompt     : String;
      Session_ID : String) return Cron_Result;

   --  Return a JSON array of active cron jobs.
   function Cron_List (Mem : Memory.SQLite.Memory_Handle) return Cron_Result;

   --  Remove a cron job by name.
   function Cron_Remove
     (Mem  : Memory.SQLite.Memory_Handle;
      Name : String) return Cron_Result;

end Tools.Cron;
