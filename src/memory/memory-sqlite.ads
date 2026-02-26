--  SQLite-backed memory: conversation history + persistent facts.
--  Uses direct SQLite3 C bindings (no GNATCOLL dependency).
--  Thread-safety: each call serialises internally; use one handle per thread.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Agent.Context;
with System;

package Memory.SQLite is

   type Memory_Handle is limited private;

   --  Open (or create) the database at the given path.
   --  Returns False and sets Error on failure.
   function Open
     (Handle : out Memory_Handle;
      Path   : String;
      Error  : out Unbounded_String) return Boolean;

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

private

   type Memory_Handle is limited record
      DB   : System.Address := System.Null_Address;
      Open : Boolean        := False;
   end record;

end Memory.SQLite;
