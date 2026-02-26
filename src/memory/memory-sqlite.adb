--  SQLite memory implementation using GNATCOLL.SQL.SQLite.

with GNATCOLL.SQL;                 use GNATCOLL.SQL;
with GNATCOLL.SQL.Exec;            use GNATCOLL.SQL.Exec;
with GNATCOLL.SQL.SQLite;
with Ada.Calendar;
with Ada.Calendar.Formatting;

package body Memory.SQLite is

   --  Schema DDL run on first open.
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

   type Real_Handle is record
      DB : Database_Connection;
   end record;
   type Real_Handle_Access is access Real_Handle;

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
      if S = "system"    then return Agent.Context.System_Role;
      elsif S = "assistant" then return Agent.Context.Assistant;
      elsif S = "tool"   then return Agent.Context.Tool_Result;
      else return Agent.Context.User;
      end if;
   end String_To_Role;

   function Open
     (Handle : out Memory_Handle;
      Path   : String;
      Error  : out Unbounded_String) return Boolean
   is
      Descr : constant Database_Description :=
        GNATCOLL.SQL.SQLite.Setup (Database => Path);
      Conn  : Database_Connection := Descr.Build_Connection;
      RH    : Real_Handle_Access;
   begin
      if Conn = null then
         Set_Unbounded_String (Error, "Failed to open SQLite database: " & Path);
         return False;
      end if;

      --  Create schema if needed.
      Conn.Execute (DDL_Messages);
      Conn.Execute (DDL_Messages_FTS);
      Conn.Execute (DDL_Facts);
      Conn.Execute (DDL_Facts_FTS);

      if Conn.Success then
         RH           := new Real_Handle'(DB => Conn);
         Handle.DB    := DB_Access (RH.all'Address);
         Handle.Open  := True;
         Set_Unbounded_String (Error, "");
         return True;
      else
         Set_Unbounded_String (Error, "Schema creation failed: " & Path);
         Free (Conn);
         return False;
      end if;
   end Open;

   procedure Close (Handle : in out Memory_Handle) is
   begin
      if Handle.Open and then Handle.DB /= null then
         Handle.Open := False;
         Handle.DB   := null;
      end if;
   end Close;

   function Get_Conn (Handle : Memory_Handle) return Database_Connection is
      RH : Real_Handle;
      for RH'Address use Handle.DB.all'Address;
      pragma Import (Ada, RH);
   begin
      return RH.DB;
   end Get_Conn;

   procedure Save_Message
     (Handle     : Memory_Handle;
      Session_ID : String;
      Channel    : String;
      Role       : Agent.Context.Role;
      Content    : String;
      Name       : String := "")
   is
      Conn : constant Database_Connection := Get_Conn (Handle);
      SQL  : constant String :=
        "INSERT INTO messages (session_id, channel, role, name, content, created_at)"
        & " VALUES (?, ?, ?, ?, ?, ?)";
   begin
      Conn.Execute
        (SQL,
         Params =>
           (1 => +Session_ID,
            2 => +Channel,
            3 => +Role_To_String (Role),
            4 => +Name,
            5 => +Content,
            6 => +Now_ISO));
      --  Keep FTS in sync.
      Conn.Execute
        ("INSERT INTO messages_fts (rowid, content, session_id)"
         & " VALUES (last_insert_rowid(), ?, ?)",
         Params => (1 => +Content, 2 => +Session_ID));
   end Save_Message;

   procedure Load_History
     (Handle     : Memory_Handle;
      Session_ID : String;
      Max_Msgs   : Positive;
      Conv       : out Agent.Context.Conversation)
   is
      Conn : constant Database_Connection := Get_Conn (Handle);
      SQL  : constant String :=
        "SELECT role, name, content FROM messages"
        & " WHERE session_id = ?"
        & " ORDER BY id DESC LIMIT ?";
      R    : Forward_Cursor;
   begin
      Set_Unbounded_String (Conv.Session_ID, Session_ID);
      Conv.Msg_Count := 0;

      R.Fetch (Conn, SQL,
               Params => (1 => +Session_ID, 2 => +Max_Msgs));

      --  Collect into a temporary reverse array then append in order.
      declare
         type Tmp_Array is array (1 .. Max_Msgs) of Agent.Context.Message;
         Tmp   : Tmp_Array;
         Count : Natural := 0;
      begin
         while R.Has_Row loop
            Count := Count + 1;
            Tmp (Count) :=
              (Role    => String_To_Role (R.Value (0)),
               Name    => To_Unbounded_String (R.Value (1)),
               Content => To_Unbounded_String (R.Value (2)));
            R.Next;
         end loop;
         --  Messages came out newest-first; append oldest-first.
         for I in reverse 1 .. Count loop
            Agent.Context.Append_Message
              (Conv,
               Tmp (I).Role,
               To_String (Tmp (I).Content),
               To_String (Tmp (I).Name));
         end loop;
      end;
   end Load_History;

   procedure Upsert_Fact
     (Handle : Memory_Handle; Key : String; Value : String)
   is
      Conn : constant Database_Connection := Get_Conn (Handle);
   begin
      Conn.Execute
        ("INSERT INTO facts (key, value, updated_at) VALUES (?, ?, ?)"
         & " ON CONFLICT(key) DO UPDATE SET value=excluded.value,"
         & " updated_at=excluded.updated_at",
         Params => (1 => +Key, 2 => +Value, 3 => +Now_ISO));
      Conn.Execute
        ("INSERT INTO facts_fts (key, value) VALUES (?, ?)",
         Params => (1 => +Key, 2 => +Value));
   end Upsert_Fact;

   function Get_Fact (Handle : Memory_Handle; Key : String) return String is
      Conn : constant Database_Connection := Get_Conn (Handle);
      R    : Forward_Cursor;
   begin
      R.Fetch (Conn, "SELECT value FROM facts WHERE key = ? LIMIT 1",
               Params => (1 => +Key));
      if R.Has_Row then
         return R.Value (0);
      end if;
      return "";
   end Get_Fact;

   procedure Delete_Fact (Handle : Memory_Handle; Key : String) is
      Conn : constant Database_Connection := Get_Conn (Handle);
   begin
      Conn.Execute ("DELETE FROM facts WHERE key = ?",
                    Params => (1 => +Key));
   end Delete_Fact;

   function Search
     (Handle : Memory_Handle;
      Query  : String;
      Limit  : Positive := 5) return Search_Results
   is
      Conn : constant Database_Connection := Get_Conn (Handle);
      SQL  : constant String :=
        "SELECT m.session_id, m.role, m.content, rank"
        & " FROM messages_fts f"
        & " JOIN messages m ON m.id = f.rowid"
        & " WHERE messages_fts MATCH ?"
        & " ORDER BY rank LIMIT ?";
      R    : Forward_Cursor;
      Tmp  : Search_Results (1 .. Limit);
      Count : Natural := 0;
   begin
      R.Fetch (Conn, SQL, Params => (1 => +Query, 2 => +Limit));
      while R.Has_Row and Count < Limit loop
         Count := Count + 1;
         Tmp (Count) :=
           (Session_ID => To_Unbounded_String (R.Value (0)),
            Role       => String_To_Role (R.Value (1)),
            Content    => To_Unbounded_String (R.Value (2)),
            Score      => Float'Value (R.Value (3)));
         R.Next;
      end loop;
      return Tmp (1 .. Count);
   end Search;

end Memory.SQLite;
