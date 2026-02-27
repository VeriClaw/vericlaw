--  SQLite memory implementation using direct SQLite3 C thin bindings.
--  Replaces GNATCOLL.SQL.SQLite with the same pattern used in http-client.adb.
--  Links against -lsqlite3 (declared in vericlaw.gpr Linker switches).

with Interfaces.C;            use Interfaces.C;
with Interfaces.C.Strings;    use Interfaces.C.Strings;
with System;                   use System;
with System.Storage_Elements;
with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Strings.Fixed;

package body Memory.SQLite is

   --  SQLite3 return codes
   SQLITE_OK   : constant int := 0;
   SQLITE_ROW  : constant int := 100;

   --  SQLITE_TRANSIENT: tells SQLite to copy the string immediately.
   --  C value is (sqlite3_destructor_type)(-1) = all-bits-set address.
   SQLITE_TRANSIENT : constant System.Address :=
     System.Storage_Elements.To_Address
       (System.Storage_Elements.Integer_Address'Last);

   --  -----------------------------------------------------------------------
   --  Thin C bindings
   --  -----------------------------------------------------------------------

   function c_open
     (Filename : chars_ptr;
      DB       : out System.Address) return int
   with Import, Convention => C, External_Name => "sqlite3_open";

   function c_close (DB : System.Address) return int
   with Import, Convention => C, External_Name => "sqlite3_close";

   function c_exec
     (DB       : System.Address;
      SQL      : chars_ptr;
      Callback : System.Address;
      UserData : System.Address;
      ErrMsg   : access chars_ptr) return int
   with Import, Convention => C, External_Name => "sqlite3_exec";

   procedure c_free (Ptr : chars_ptr)
   with Import, Convention => C, External_Name => "sqlite3_free";

   function c_prepare_v2
     (DB    : System.Address;
      SQL   : chars_ptr;
      NLen  : int;
      Stmt  : out System.Address;
      PTail : System.Address) return int
   with Import, Convention => C, External_Name => "sqlite3_prepare_v2";

   function c_step (Stmt : System.Address) return int
   with Import, Convention => C, External_Name => "sqlite3_step";

   function c_finalize (Stmt : System.Address) return int
   with Import, Convention => C, External_Name => "sqlite3_finalize";

   function c_bind_text
     (Stmt  : System.Address;
      Col   : int;
      Value : chars_ptr;
      NLen  : int;
      Destr : System.Address) return int
   with Import, Convention => C, External_Name => "sqlite3_bind_text";

   function c_bind_int
     (Stmt  : System.Address;
      Col   : int;
      Value : int) return int
   with Import, Convention => C, External_Name => "sqlite3_bind_int";

   function c_column_text
     (Stmt : System.Address;
      Col  : int) return chars_ptr
   with Import, Convention => C, External_Name => "sqlite3_column_text";

   function c_column_double
     (Stmt : System.Address;
      Col  : int) return double
   with Import, Convention => C, External_Name => "sqlite3_column_double";

   function c_errmsg (DB : System.Address) return chars_ptr
   with Import, Convention => C, External_Name => "sqlite3_errmsg";

   --  -----------------------------------------------------------------------
   --  Schema DDL (run on first open)
   --  -----------------------------------------------------------------------

   DDL_Messages : constant String :=
     "CREATE TABLE IF NOT EXISTS messages ("
     & " id INTEGER PRIMARY KEY AUTOINCREMENT,"
     & " session_id TEXT NOT NULL,"
     & " channel TEXT NOT NULL DEFAULT '',"
     & " role TEXT NOT NULL,"
     & " name TEXT NOT NULL DEFAULT '',"
     & " content TEXT NOT NULL,"
     & " created_at TEXT NOT NULL"
     & ");";

   DDL_Messages_FTS : constant String :=
     "CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5("
     & " content, session_id UNINDEXED,"
     & " content='messages', content_rowid='id'"
     & ");";

   DDL_Facts : constant String :=
     "CREATE TABLE IF NOT EXISTS facts ("
     & " key TEXT PRIMARY KEY,"
     & " value TEXT NOT NULL,"
     & " updated_at TEXT NOT NULL"
     & ");";

   DDL_Facts_FTS : constant String :=
     "CREATE VIRTUAL TABLE IF NOT EXISTS facts_fts USING fts5("
     & " key, value,"
     & " content='facts', content_rowid='rowid'"
     & ");";

   DDL_Cron : constant String :=
     "CREATE TABLE IF NOT EXISTS cron_jobs ("
     & " id INTEGER PRIMARY KEY AUTOINCREMENT,"
     & " name TEXT NOT NULL UNIQUE,"
     & " schedule TEXT NOT NULL,"
     & " prompt TEXT NOT NULL,"
     & " session_id TEXT NOT NULL,"
     & " last_run TEXT,"
     & " next_run TEXT NOT NULL,"
     & " enabled INTEGER DEFAULT 1"
     & ");";

   --  -----------------------------------------------------------------------
   --  Internal helpers
   --  -----------------------------------------------------------------------

   --  Execute a DDL statement (no parameters, no result set).
   procedure Exec_DDL (DB : System.Address; SQL : String) is
      CS  : chars_ptr := New_String (SQL);
      Err : aliased chars_ptr := Null_Ptr;
      Rc  : int;
   begin
      Rc := c_exec (DB, CS, System.Null_Address, System.Null_Address,
                    Err'Access);
      Free (CS);
      if Err /= Null_Ptr then
         c_free (Err);
      end if;
      pragma Unreferenced (Rc);
   end Exec_DDL;

   --  Bind a text parameter (column 1-indexed).
   procedure Bind_Text
     (Stmt : System.Address; Col : Positive; Val : String)
   is
      CS : chars_ptr := New_String (Val);
      Rc : int;
   begin
      Rc := c_bind_text (Stmt, int (Col), CS, -1, SQLITE_TRANSIENT);
      Free (CS);
      pragma Unreferenced (Rc);
   end Bind_Text;

   --  Bind an integer parameter (column 1-indexed).
   procedure Bind_Int
     (Stmt : System.Address; Col : Positive; Val : Integer)
   is
      Rc : int;
   begin
      Rc := c_bind_int (Stmt, int (Col), int (Val));
      pragma Unreferenced (Rc);
   end Bind_Int;

   --  Return column text as Ada String (0-indexed column).
   function Col_Text (Stmt : System.Address; Col : Natural) return String is
      CS : constant chars_ptr := c_column_text (Stmt, int (Col));
   begin
      if CS = Null_Ptr then
         return "";
      end if;
      return Value (CS);  --  Value copies; SQLite owns the pointer
   end Col_Text;

   function Now_ISO return String is
   begin
      return Ada.Calendar.Formatting.Image (Ada.Calendar.Clock);
   end Now_ISO;

   function Role_To_String (R : Agent.Context.Role) return String is
   begin
      case R is
         when Agent.Context.System_Role  => return "system";
         when Agent.Context.User         => return "user";
         when Agent.Context.Assistant    => return "assistant";
         when Agent.Context.Tool_Result  => return "tool";
      end case;
   end Role_To_String;

   function String_To_Role (S : String) return Agent.Context.Role is
   begin
      if    S = "system"    then return Agent.Context.System_Role;
      elsif S = "assistant" then return Agent.Context.Assistant;
      elsif S = "tool"      then return Agent.Context.Tool_Result;
      else                       return Agent.Context.User;
      end if;
   end String_To_Role;

   --  -----------------------------------------------------------------------
   --  Public operations
   --  -----------------------------------------------------------------------

   function Open
     (Handle         : out Memory_Handle;
      Path           : String;
      Error          : out Unbounded_String;
      Retention_Days : Natural := 30) return Boolean
   is
      CS : chars_ptr := New_String (Path);
      DB : System.Address;
      Rc : int;
   begin
      Rc := c_open (CS, DB);
      Free (CS);

      if Rc /= SQLITE_OK or else DB = System.Null_Address then
         Set_Unbounded_String (Error,
           "Failed to open SQLite database: " & Path);
         return False;
      end if;

      --  Enable WAL mode for safe concurrent multi-writer access.
      Exec_DDL (DB, "PRAGMA journal_mode=WAL");

      --  Create schema if needed.
      Exec_DDL (DB, DDL_Messages);
      Exec_DDL (DB, DDL_Messages_FTS);
      Exec_DDL (DB, DDL_Facts);
      Exec_DDL (DB, DDL_Facts_FTS);
      Exec_DDL (DB, DDL_Cron);

      --  Prune old sessions on startup if retention is configured.
      if Retention_Days > 0 then
         declare
            Days_Str : constant String :=
              Ada.Strings.Fixed.Trim
                (Natural'Image (Retention_Days), Ada.Strings.Left);
         begin
            Exec_DDL (DB,
              "DELETE FROM messages WHERE"
              & " julianday('now') - julianday(created_at) > " & Days_Str);
         end;
      end if;

      Handle.DB   := DB;
      Handle.Open := True;
      Set_Unbounded_String (Error, "");
      return True;
   end Open;

   procedure Close (Handle : in out Memory_Handle) is
      Rc : int;
   begin
      if Handle.Open and then Handle.DB /= System.Null_Address then
         Rc := c_close (Handle.DB);
         pragma Unreferenced (Rc);
         Handle.DB   := System.Null_Address;
         Handle.Open := False;
      end if;
   end Close;

   function Is_Open (Handle : Memory_Handle) return Boolean is
   begin
      return Handle.Open;
   end Is_Open;

   procedure Save_Message
     (Handle     : Memory_Handle;
      Session_ID : String;
      Channel    : String;
      Role       : Agent.Context.Role;
      Content    : String;
      Name       : String := "")
   is
      SQL  : constant String :=
        "INSERT INTO messages (session_id, channel, role, name, content,"
        & " created_at) VALUES (?, ?, ?, ?, ?, ?)";
      CS   : chars_ptr := New_String (SQL);
      Stmt : System.Address;
      Rc   : int;
   begin
      Rc := c_prepare_v2 (Handle.DB, CS, -1, Stmt, System.Null_Address);
      Free (CS);
      if Rc /= SQLITE_OK then return; end if;

      Bind_Text (Stmt, 1, Session_ID);
      Bind_Text (Stmt, 2, Channel);
      Bind_Text (Stmt, 3, Role_To_String (Role));
      Bind_Text (Stmt, 4, Name);
      Bind_Text (Stmt, 5, Content);
      Bind_Text (Stmt, 6, Now_ISO);
      Rc := c_step (Stmt);
      Rc := c_finalize (Stmt);

      --  Keep FTS in sync.
      declare
         FTS_SQL  : constant String :=
           "INSERT INTO messages_fts (rowid, content, session_id)"
           & " VALUES (last_insert_rowid(), ?, ?)";
         FCS  : chars_ptr := New_String (FTS_SQL);
         FStmt : System.Address;
      begin
         Rc := c_prepare_v2 (Handle.DB, FCS, -1, FStmt, System.Null_Address);
         Free (FCS);
         if Rc = SQLITE_OK then
            Bind_Text (FStmt, 1, Content);
            Bind_Text (FStmt, 2, Session_ID);
            Rc := c_step (FStmt);
            Rc := c_finalize (FStmt);
         end if;
      end;
      pragma Unreferenced (Rc);
   end Save_Message;

   procedure Load_History
     (Handle     : Memory_Handle;
      Session_ID : String;
      Max_Msgs   : Positive;
      Conv       : out Agent.Context.Conversation)
   is
      SQL  : constant String :=
        "SELECT role, name, content FROM messages"
        & " WHERE session_id = ? ORDER BY id DESC LIMIT ?";
      CS   : chars_ptr := New_String (SQL);
      Stmt : System.Address;
      Rc   : int;

      Max_Buf : constant := 1024;
      type Role_Array    is array (1 .. Max_Buf) of Agent.Context.Role;
      type Name_Array    is array (1 .. Max_Buf) of Unbounded_String;
      type Content_Array is array (1 .. Max_Buf) of Unbounded_String;
      Roles    : Role_Array;
      Names    : Name_Array;
      Contents : Content_Array;
      Count    : Natural := 0;
   begin
      Set_Unbounded_String (Conv.Session_ID, Session_ID);
      Conv.Msg_Count := 0;

      Rc := c_prepare_v2 (Handle.DB, CS, -1, Stmt, System.Null_Address);
      Free (CS);
      if Rc /= SQLITE_OK then return; end if;

      Bind_Text (Stmt, 1, Session_ID);
      Bind_Int  (Stmt, 2, Max_Msgs);

      while c_step (Stmt) = SQLITE_ROW and Count < Max_Buf loop
         Count            := Count + 1;
         Roles (Count)    := String_To_Role (Col_Text (Stmt, 0));
         Names (Count)    := To_Unbounded_String (Col_Text (Stmt, 1));
         Contents (Count) := To_Unbounded_String (Col_Text (Stmt, 2));
      end loop;
      Rc := c_finalize (Stmt);
      pragma Unreferenced (Rc);

      --  Rows came out newest-first; feed oldest-first into Conv.
      for I in reverse 1 .. Count loop
         Agent.Context.Append_Message
           (Conv,
            Roles (I),
            To_String (Contents (I)),
            To_String (Names (I)));
      end loop;
   end Load_History;

   procedure Upsert_Fact
     (Handle : Memory_Handle; Key : String; Value : String)
   is
      SQL  : constant String :=
        "INSERT INTO facts (key, value, updated_at) VALUES (?, ?, ?)"
        & " ON CONFLICT(key) DO UPDATE SET value=excluded.value,"
        & " updated_at=excluded.updated_at";
      CS   : chars_ptr := New_String (SQL);
      Stmt : System.Address;
      Rc   : int;
   begin
      Rc := c_prepare_v2 (Handle.DB, CS, -1, Stmt, System.Null_Address);
      Free (CS);
      if Rc /= SQLITE_OK then return; end if;
      Bind_Text (Stmt, 1, Key);
      Bind_Text (Stmt, 2, Value);
      Bind_Text (Stmt, 3, Now_ISO);
      Rc := c_step (Stmt);
      Rc := c_finalize (Stmt);
      pragma Unreferenced (Rc);
   end Upsert_Fact;

   function Get_Fact (Handle : Memory_Handle; Key : String) return String is
      SQL  : constant String :=
        "SELECT value FROM facts WHERE key = ? LIMIT 1";
      CS   : chars_ptr := New_String (SQL);
      Stmt : System.Address;
      Rc   : int;
      Res  : Unbounded_String;
   begin
      Rc := c_prepare_v2 (Handle.DB, CS, -1, Stmt, System.Null_Address);
      Free (CS);
      if Rc /= SQLITE_OK then return ""; end if;
      Bind_Text (Stmt, 1, Key);
      if c_step (Stmt) = SQLITE_ROW then
         Res := To_Unbounded_String (Col_Text (Stmt, 0));
      end if;
      Rc := c_finalize (Stmt);
      pragma Unreferenced (Rc);
      return To_String (Res);
   end Get_Fact;

   procedure Delete_Fact (Handle : Memory_Handle; Key : String) is
      SQL  : constant String := "DELETE FROM facts WHERE key = ?";
      CS   : chars_ptr := New_String (SQL);
      Stmt : System.Address;
      Rc   : int;
   begin
      Rc := c_prepare_v2 (Handle.DB, CS, -1, Stmt, System.Null_Address);
      Free (CS);
      if Rc /= SQLITE_OK then return; end if;
      Bind_Text (Stmt, 1, Key);
      Rc := c_step (Stmt);
      Rc := c_finalize (Stmt);
      pragma Unreferenced (Rc);
   end Delete_Fact;

   function Search
     (Handle : Memory_Handle;
      Query  : String;
      Limit  : Positive := 5) return Search_Results
   is
      SQL  : constant String :=
        "SELECT m.session_id, m.role, m.content, rank"
        & " FROM messages_fts f"
        & " JOIN messages m ON m.id = f.rowid"
        & " WHERE messages_fts MATCH ?"
        & " ORDER BY rank LIMIT ?";
      CS   : chars_ptr := New_String (SQL);
      Stmt : System.Address;
      Rc   : int;
      Tmp  : Search_Results (1 .. Limit);
      Count : Natural := 0;
   begin
      Rc := c_prepare_v2 (Handle.DB, CS, -1, Stmt, System.Null_Address);
      Free (CS);
      if Rc /= SQLITE_OK then return Tmp (1 .. 0); end if;

      Bind_Text (Stmt, 1, Query);
      Bind_Int  (Stmt, 2, Limit);

      while c_step (Stmt) = SQLITE_ROW and Count < Limit loop
         Count := Count + 1;
         Tmp (Count) :=
           (Session_ID => To_Unbounded_String (Col_Text (Stmt, 0)),
            Role       => String_To_Role (Col_Text (Stmt, 1)),
            Content    => To_Unbounded_String (Col_Text (Stmt, 2)),
            Score      => Float (c_column_double (Stmt, 3)));
      end loop;
      Rc := c_finalize (Stmt);
      pragma Unreferenced (Rc);
      return Tmp (1 .. Count);
   end Search;

   procedure Cron_Insert
     (Handle     : Memory_Handle;
      Name       : String;
      Schedule   : String;
      Prompt     : String;
      Session_ID : String;
      Next_Run   : String)
   is
      SQL  : constant String :=
        "INSERT INTO cron_jobs (name, schedule, prompt, session_id, next_run)"
        & " VALUES (?, ?, ?, ?, ?)"
        & " ON CONFLICT(name) DO UPDATE SET"
        & "  schedule=excluded.schedule,"
        & "  prompt=excluded.prompt,"
        & "  session_id=excluded.session_id,"
        & "  next_run=excluded.next_run,"
        & "  enabled=1";
      CS   : chars_ptr := New_String (SQL);
      Stmt : System.Address;
      Rc   : int;
   begin
      Rc := c_prepare_v2 (Handle.DB, CS, -1, Stmt, System.Null_Address);
      Free (CS);
      if Rc /= SQLITE_OK then return; end if;
      Bind_Text (Stmt, 1, Name);
      Bind_Text (Stmt, 2, Schedule);
      Bind_Text (Stmt, 3, Prompt);
      Bind_Text (Stmt, 4, Session_ID);
      Bind_Text (Stmt, 5, Next_Run);
      Rc := c_step (Stmt);
      Rc := c_finalize (Stmt);
      pragma Unreferenced (Rc);
   end Cron_Insert;

   function Cron_Fill_Jobs
     (Handle : Memory_Handle;
      SQL    : String) return Cron_List_Result
   is
      CS    : chars_ptr := New_String (SQL);
      Stmt  : System.Address;
      Rc    : int;
      Res   : Cron_List_Result;
   begin
      Rc := c_prepare_v2 (Handle.DB, CS, -1, Stmt, System.Null_Address);
      Free (CS);
      if Rc /= SQLITE_OK then return Res; end if;
      while c_step (Stmt) = SQLITE_ROW
        and Res.Count < Max_Cron_Jobs
      loop
         Res.Count := Res.Count + 1;
         Res.Jobs (Res.Count) :=
           (Name       => To_Unbounded_String (Col_Text (Stmt, 0)),
            Schedule   => To_Unbounded_String (Col_Text (Stmt, 1)),
            Prompt     => To_Unbounded_String (Col_Text (Stmt, 2)),
            Session_ID => To_Unbounded_String (Col_Text (Stmt, 3)),
            Last_Run   => To_Unbounded_String (Col_Text (Stmt, 4)),
            Next_Run   => To_Unbounded_String (Col_Text (Stmt, 5)));
      end loop;
      Rc := c_finalize (Stmt);
      pragma Unreferenced (Rc);
      return Res;
   end Cron_Fill_Jobs;

   function Cron_List_Jobs (Handle : Memory_Handle) return Cron_List_Result is
   begin
      return Cron_Fill_Jobs
        (Handle,
         "SELECT name, schedule, prompt, session_id,"
         & " coalesce(last_run,''), next_run"
         & " FROM cron_jobs WHERE enabled = 1 ORDER BY name");
   end Cron_List_Jobs;

   procedure Cron_Delete (Handle : Memory_Handle; Name : String) is
      SQL  : constant String := "DELETE FROM cron_jobs WHERE name = ?";
      CS   : chars_ptr := New_String (SQL);
      Stmt : System.Address;
      Rc   : int;
   begin
      Rc := c_prepare_v2 (Handle.DB, CS, -1, Stmt, System.Null_Address);
      Free (CS);
      if Rc /= SQLITE_OK then return; end if;
      Bind_Text (Stmt, 1, Name);
      Rc := c_step (Stmt);
      Rc := c_finalize (Stmt);
      pragma Unreferenced (Rc);
   end Cron_Delete;

   function Cron_Due_Jobs (Handle : Memory_Handle) return Cron_List_Result is
   begin
      return Cron_Fill_Jobs
        (Handle,
         "SELECT name, schedule, prompt, session_id,"
         & " coalesce(last_run,''), next_run"
         & " FROM cron_jobs"
         & " WHERE next_run <= datetime('now') AND enabled = 1"
         & " ORDER BY next_run");
   end Cron_Due_Jobs;

   procedure Cron_Update_Run
     (Handle   : Memory_Handle;
      Name     : String;
      Next_Run : String)
   is
      SQL  : constant String :=
        "UPDATE cron_jobs SET last_run = datetime('now'), next_run = ?"
        & " WHERE name = ?";
      CS   : chars_ptr := New_String (SQL);
      Stmt : System.Address;
      Rc   : int;
   begin
      Rc := c_prepare_v2 (Handle.DB, CS, -1, Stmt, System.Null_Address);
      Free (CS);
      if Rc /= SQLITE_OK then return; end if;
      Bind_Text (Stmt, 1, Next_Run);
      Bind_Text (Stmt, 2, Name);
      Rc := c_step (Stmt);
      Rc := c_finalize (Stmt);
      pragma Unreferenced (Rc);
   end Cron_Update_Run;

end Memory.SQLite;
