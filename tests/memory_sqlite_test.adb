--  Unit tests for Memory.SQLite: open, save/load messages, facts, FTS search.
--  Requires GNATCOLL + libsqlite3.  Uses an in-process temp file so no
--  external database service is needed.

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Directories;
with Agent.Context;
with Memory.SQLite;         use Memory.SQLite;

procedure Memory_Sqlite_Test is

   Passed : Natural := 0;
   Failed : Natural := 0;

   procedure Assert (Condition : Boolean; Label : String) is
   begin
      if Condition then
         Put_Line ("  PASS: " & Label);
         Passed := Passed + 1;
      else
         Put_Line ("  FAIL: " & Label);
         Failed := Failed + 1;
      end if;
   end Assert;

   DB_Path : constant String :=
     Ada.Directories.Current_Directory & "/test_memory_vericlaw.db";

   ---------------------------------------------------------
   --  Section 1: Open and Close
   ---------------------------------------------------------
   procedure Test_Open is
      H     : Memory_Handle;
      Err   : Unbounded_String;
      OK    : Boolean;
   begin
      Put_Line ("--- Open / Close ---");
      OK := Open (H, DB_Path, Err);
      Assert (OK, "Open returns True for writable path");
      Assert (Length (Err) = 0, "No error on successful open");
      Close (H);
      Assert (Ada.Directories.Exists (DB_Path), "Database file was created on disk");
   end Test_Open;

   ---------------------------------------------------------
   --  Section 2: Save_Message and Load_History round-trip
   ---------------------------------------------------------
   procedure Test_Message_Round_Trip is
      H    : Memory_Handle;
      Err  : Unbounded_String;
      OK   : Boolean;
      Conv : Agent.Context.Conversation;
   begin
      Put_Line ("--- Save_Message / Load_History ---");
      OK := Open (H, DB_Path, Err);
      Assert (OK, "Open for message round-trip");

      Save_Message (H,
        Session_ID => "sess-test-01",
        Channel    => "cli",
        Role       => Agent.Context.User,
        Content    => "Hello from test.");
      Save_Message (H,
        Session_ID => "sess-test-01",
        Channel    => "cli",
        Role       => Agent.Context.Assistant,
        Content    => "Hello back from VeriClaw.");

      Load_History (H,
        Session_ID => "sess-test-01",
        Max_Msgs   => 10,
        Conv       => Conv);

      Assert (Conv.Msg_Count >= 2, "Load_History returns at least 2 messages");
      Assert (To_String (Conv.Session_ID) = "sess-test-01",
              "Loaded conversation has correct session ID");

      Close (H);
   end Test_Message_Round_Trip;

   ---------------------------------------------------------
   --  Section 3: Upsert_Fact / Get_Fact / Delete_Fact
   ---------------------------------------------------------
   procedure Test_Facts is
      H   : Memory_Handle;
      Err : Unbounded_String;
      OK  : Boolean;
      Val : Unbounded_String;
   begin
      Put_Line ("--- Upsert_Fact / Get_Fact ---");
      OK := Open (H, DB_Path, Err);
      Assert (OK, "Open for facts test");

      Upsert_Fact (H, "user_name", "Alice");
      Val := To_Unbounded_String (Get_Fact (H, "user_name"));
      Assert (To_String (Val) = "Alice", "Get_Fact returns stored value");

      --  Upsert (overwrite)
      Upsert_Fact (H, "user_name", "Bob");
      Val := To_Unbounded_String (Get_Fact (H, "user_name"));
      Assert (To_String (Val) = "Bob", "Upsert_Fact overwrites existing value");

      --  Delete
      Delete_Fact (H, "user_name");
      Val := To_Unbounded_String (Get_Fact (H, "user_name"));
      Assert (Length (Val) = 0, "Get_Fact returns empty after Delete_Fact");

      Close (H);
   end Test_Facts;

   ---------------------------------------------------------
   --  Section 4: Full-text search
   ---------------------------------------------------------
   procedure Test_Search is
      H       : Memory_Handle;
      Err     : Unbounded_String;
      OK      : Boolean;
      Results : Search_Results (1 .. 10);
   begin
      Put_Line ("--- Search (FTS5) ---");
      OK := Open (H, DB_Path, Err);
      Assert (OK, "Open for search test");

      --  Seed some messages with distinctive words
      Save_Message (H, "sess-fts-01", "cli", Agent.Context.User,
                    "What is the capital of France?");
      Save_Message (H, "sess-fts-01", "cli", Agent.Context.Assistant,
                    "The capital of France is Paris.");
      Save_Message (H, "sess-fts-01", "cli", Agent.Context.User,
                    "Tell me about Ada programming language.");

      Results := Search (H, "France", Limit => 5);
      Assert (Results'Length >= 1, "Search for 'France' returns at least one result");

      Results := Search (H, "Ada programming", Limit => 5);
      Assert (Results'Length >= 1, "Search for 'Ada programming' returns at least one result");

      Close (H);
   end Test_Search;

begin
   Put_Line ("=== memory_sqlite_test ===");

   --  Clean up any leftover DB from a prior run
   if Ada.Directories.Exists (DB_Path) then
      Ada.Directories.Delete_File (DB_Path);
   end if;

   Test_Open;
   Test_Message_Round_Trip;
   Test_Facts;
   Test_Search;

   --  Clean up
   if Ada.Directories.Exists (DB_Path) then
      Ada.Directories.Delete_File (DB_Path);
   end if;

   Put_Line ("");
   Put_Line ("Results: " & Natural'Image (Passed) & " passed, "
             & Natural'Image (Failed) & " failed");
   if Failed > 0 then
      raise Program_Error with Natural'Image (Failed) & " test(s) failed";
   end if;
end Memory_Sqlite_Test;
