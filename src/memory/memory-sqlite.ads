--  SQLite-backed memory: conversation history + persistent facts.
--  Uses direct SQLite3 C bindings (no GNATCOLL dependency).
--  Thread-safety: each call serialises internally; use one handle per thread.

with Ada.Finalization;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Agent.Context;
with System;

pragma SPARK_Mode (Off);
package Memory.SQLite is

   type Memory_Handle is limited private;

   --  Open (or create) the database at the given path.
   --  Retention_Days: auto-prune messages older than N days on open (0 = never).
   --  Returns False and sets Error on failure.
   function Open
     (Handle         : out Memory_Handle;
      Path           : String;
      Error          : out Unbounded_String;
      Retention_Days : Natural := 30) return Boolean;

   procedure Close (Handle : in out Memory_Handle);

   --  True if the database was successfully opened.
   function Is_Open (Handle : Memory_Handle) return Boolean;

   --  -----------------------------------------------------------------------
   --  Conversation history
   --  -----------------------------------------------------------------------

   --  Persist a single message.
   procedure Save_Message
     (Handle     : Memory_Handle;
      Session_ID : String;
      Channel    : String;
      Role       : Agent.Context.Role;
      Content    : String;
      Name       : String := "");

   --  Load the last N messages for a session into Conv.
   procedure Load_History
     (Handle     : Memory_Handle;
      Session_ID : String;
      Max_Msgs   : Positive;
      Conv       : out Agent.Context.Conversation);

   --  -----------------------------------------------------------------------
   --  Persistent facts (MEMORY.md equivalent)
   --  -----------------------------------------------------------------------

   procedure Upsert_Fact (Handle : Memory_Handle; Key : String; Value : String);
   function  Get_Fact    (Handle : Memory_Handle; Key : String) return String;
   procedure Delete_Fact (Handle : Memory_Handle; Key : String);

   --  Full-text search across stored content (FTS5).
   type Search_Result is record
      Session_ID : Unbounded_String;
      Role       : Agent.Context.Role;
      Content    : Unbounded_String;
      Score      : Float;
   end record;
   type Search_Results is array (Positive range <>) of Search_Result;

   function Search
     (Handle : Memory_Handle;
      Query  : String;
      Limit  : Positive := 5) return Search_Results;

   --  -----------------------------------------------------------------------
   --  Cron scheduler
   --  -----------------------------------------------------------------------

   type Cron_Job_Info is record
      Name       : Unbounded_String;
      Schedule   : Unbounded_String;
      Prompt     : Unbounded_String;
      Session_ID : Unbounded_String;
      Last_Run   : Unbounded_String;
      Next_Run   : Unbounded_String;
   end record;

   Max_Cron_Jobs : constant := 64;
   type Cron_Job_Array is array (1 .. Max_Cron_Jobs) of Cron_Job_Info;

   type Cron_List_Result is record
      Jobs  : Cron_Job_Array;
      Count : Natural := 0;
   end record;

   --  Insert or replace a cron job (UNIQUE on name).
   procedure Cron_Insert
     (Handle     : Memory_Handle;
      Name       : String;
      Schedule   : String;
      Prompt     : String;
      Session_ID : String;
      Next_Run   : String);

   --  Return all active (enabled=1) cron jobs.
   function Cron_List_Jobs (Handle : Memory_Handle) return Cron_List_Result;

   --  Delete a cron job by name.
   procedure Cron_Delete (Handle : Memory_Handle; Name : String);

   --  Return jobs whose next_run <= now and enabled = 1.
   function Cron_Due_Jobs (Handle : Memory_Handle) return Cron_List_Result;

   --  Record execution: set last_run=now and next_run to supplied value.
   procedure Cron_Update_Run
     (Handle   : Memory_Handle;
      Name     : String;
      Next_Run : String);

   --  -----------------------------------------------------------------------
   --  Vector extension support (sqlite-vec)
   --  -----------------------------------------------------------------------

   --  Load the sqlite-vec shared library and create the vec_memories tables.
   --  Path: shared library name or path (e.g. "vec0" or "/usr/lib/vec0.so").
   procedure Load_Vec_Extension (Handle : Memory_Handle; Path : String);

   --  Return the raw SQLite database handle (needed by Memory.Vector).
   function DB_Address (Handle : Memory_Handle) return System.Address;

private

   type Memory_Handle is new Ada.Finalization.Limited_Controlled with record
      DB   : System.Address := System.Null_Address;
      Open : Boolean        := False;
   end record;

   overriding procedure Finalize (Self : in out Memory_Handle);

end Memory.SQLite;
