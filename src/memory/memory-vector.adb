pragma SPARK_Mode (Off);
with Ada.Strings.Fixed;
with Logging;
with Ada.Calendar;
with Ada.Calendar.Formatting;
with Interfaces.C;            use Interfaces.C;
with Interfaces.C.Strings;    use Interfaces.C.Strings;
with System;
with System.Storage_Elements;
with HTTP.Client;

package body Memory.Vector is
   use type System.Address;

   --  SQLite return codes
   SQLITE_OK  : constant Interfaces.C.int := 0;
   SQLITE_ROW : constant Interfaces.C.int := 100;

   --  SQLITE_TRANSIENT: tells SQLite to copy the string immediately.
   SQLITE_TRANSIENT : constant System.Address :=
     System.Storage_Elements.To_Address
       (System.Storage_Elements.Integer_Address'Last);

   --  -------------------------------------------------------------------------
   --  Local SQLite C bindings
   --  -------------------------------------------------------------------------

   function c_prepare_v2
     (DB    : System.Address;
      SQL   : chars_ptr;
      NLen  : Interfaces.C.int;
      Stmt  : out System.Address;
      PTail : System.Address) return Interfaces.C.int
   with Import, Convention => C, External_Name => "sqlite3_prepare_v2";

   function c_step (Stmt : System.Address) return Interfaces.C.int
   with Import, Convention => C, External_Name => "sqlite3_step";

   function c_finalize (Stmt : System.Address) return Interfaces.C.int
   with Import, Convention => C, External_Name => "sqlite3_finalize";

   function c_bind_text
     (Stmt  : System.Address;
      Col   : Interfaces.C.int;
      Value : chars_ptr;
      NLen  : Interfaces.C.int;
      Destr : System.Address) return Interfaces.C.int
   with Import, Convention => C, External_Name => "sqlite3_bind_text";

   function c_bind_int
     (Stmt  : System.Address;
      Col   : Interfaces.C.int;
      Value : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "sqlite3_bind_int";

   function c_bind_int64
     (Stmt  : System.Address;
      Col   : Interfaces.C.int;
      Value : Long_Long_Integer) return Interfaces.C.int
   with Import, Convention => C, External_Name => "sqlite3_bind_int64";

   function c_column_text
     (Stmt : System.Address;
      Col  : Interfaces.C.int) return chars_ptr
   with Import, Convention => C, External_Name => "sqlite3_column_text";

   function c_column_double
     (Stmt : System.Address;
      Col  : Interfaces.C.int) return Interfaces.C.double
   with Import, Convention => C, External_Name => "sqlite3_column_double";

   function c_last_insert_rowid
     (DB : System.Address) return Long_Long_Integer
   with Import, Convention => C, External_Name => "sqlite3_last_insert_rowid";

   --  -------------------------------------------------------------------------
   --  Internal helpers
   --  -------------------------------------------------------------------------

   procedure Bind_Text
     (Stmt : System.Address; Col : Positive; Val : String)
   is
      CS : chars_ptr := New_String (Val);
      Rc : Interfaces.C.int;
   begin
      Rc := c_bind_text (Stmt, Interfaces.C.int (Col), CS, -1,
                         SQLITE_TRANSIENT);
      Free (CS);
      pragma Unreferenced (Rc);
   end Bind_Text;

   function Col_Text (Stmt : System.Address; Col : Natural) return String is
      CS : constant chars_ptr := c_column_text (Stmt, Interfaces.C.int (Col));
   begin
      if CS = Null_Ptr then return ""; end if;
      return Value (CS);
   end Col_Text;

   --  Format a Float for inclusion in a JSON array (no leading space).
   function Float_Img (F : Float) return String is
   begin
      return Ada.Strings.Fixed.Trim (Float'Image (F), Ada.Strings.Left);
   end Float_Img;

   --  Serialise an Embedding as a JSON array string "[v1,v2,...]".
   function Embedding_To_JSON (Vec : Embedding) return String is
      Buf : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Ada.Strings.Unbounded.Append (Buf, "[");
      for I in Vec'Range loop
         if I > 1 then
            Ada.Strings.Unbounded.Append (Buf, ",");
         end if;
         Ada.Strings.Unbounded.Append (Buf, Float_Img (Vec (I)));
      end loop;
      Ada.Strings.Unbounded.Append (Buf, "]");
      return Ada.Strings.Unbounded.To_String (Buf);
   end Embedding_To_JSON;

   --  Minimal JSON string escaper (handles " \ and common control chars).
   function JSON_Escape (S : String) return String is
      Buf : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for C of S loop
         if C = '"' then
            Ada.Strings.Unbounded.Append (Buf, "\");
            Ada.Strings.Unbounded.Append (Buf, '"');
         elsif C = '\' then
            Ada.Strings.Unbounded.Append (Buf, "\\");
         elsif C = ASCII.LF then
            Ada.Strings.Unbounded.Append (Buf, "\n");
         elsif C = ASCII.CR then
            Ada.Strings.Unbounded.Append (Buf, "\r");
         elsif C = ASCII.HT then
            Ada.Strings.Unbounded.Append (Buf, "\t");
         else
            Ada.Strings.Unbounded.Append (Buf, C);
         end if;
      end loop;
      return Ada.Strings.Unbounded.To_String (Buf);
   end JSON_Escape;

   --  -------------------------------------------------------------------------
   --  Public operations
   --  -------------------------------------------------------------------------

   function Embed
     (Text     : String;
      API_Key  : String;
      Base_URL : String := "https://api.openai.com/v1") return Embedding
   is
      Zero_Vec  : constant Embedding := [others => 0.0];
      Body_JSON : constant String :=
        "{""model"":""text-embedding-3-small"","
        & """input"":""" & JSON_Escape (Text) & """}";
      Auth_Hdr  : constant HTTP.Client.Header_Array :=
        [1 => (Name  => Ada.Strings.Unbounded.To_Unbounded_String
                          ("Authorization"),
               Value => Ada.Strings.Unbounded.To_Unbounded_String
                          ("Bearer " & API_Key))];
      Resp : constant HTTP.Client.Response :=
        HTTP.Client.Post_JSON
          (URL        => Base_URL & "/embeddings",
           Headers    => Auth_Hdr,
           Body_JSON  => Body_JSON,
           Timeout_Ms => 30_000);
   begin
      if not HTTP.Client.Is_Success (Resp) then
         return Zero_Vec;
      end if;

      declare
         Body_Str : constant String :=
           Ada.Strings.Unbounded.To_String (Resp.Body_Text);
         Marker   : constant String := """embedding"":[";
         Start    : Natural := 0;
         Result   : Embedding := [others => 0.0];
         Idx      : Natural := 0;
         Pos      : Natural;
      begin
         --  Find the "embedding":[ marker in the response JSON.
         for I in Body_Str'Range loop
            if I + Marker'Length - 1 <= Body_Str'Last
              and then Body_Str (I .. I + Marker'Length - 1) = Marker
            then
               Start := I + Marker'Length;
               exit;
            end if;
         end loop;

         if Start = 0 then return Result; end if;

         --  Parse comma-separated floats until the closing ].
         Pos := Start;
         while Pos <= Body_Str'Last and then Body_Str (Pos) /= ']' loop
            while Pos <= Body_Str'Last
              and then (Body_Str (Pos) = ',' or else Body_Str (Pos) = ' ')
            loop
               Pos := Pos + 1;
            end loop;

            exit when Pos > Body_Str'Last or else Body_Str (Pos) = ']';

            declare
               Num_Start : constant Natural := Pos;
               Num_End   : Natural := Pos;
            begin
               while Num_End <= Body_Str'Last
                 and then Body_Str (Num_End) /= ','
                 and then Body_Str (Num_End) /= ']'
               loop
                  Num_End := Num_End + 1;
               end loop;

               Idx := Idx + 1;
               if Idx <= Max_Embedding_Dims then
                  begin
                     Result (Idx) :=
                       Float'Value (Body_Str (Num_Start .. Num_End - 1));
                  exception
                     when Constraint_Error =>
                         Logging.Debug ("Vector operation constraint error");
                  end;
               end if;
               Pos := Num_End;
            end;
         end loop;

         return Result;
      end;
   end Embed;

   procedure Store
     (Mem        : Memory.SQLite.Memory_Handle;
      Session_ID : String;
      Content    : String;
      Vec        : Embedding)
   is
      DB : constant System.Address := Memory.SQLite.DB_Address (Mem);
      SQL_Meta : constant String :=
        "INSERT INTO vec_memories_meta (session_id, content, ts)"
        & " VALUES (?, ?, ?)";
      CS    : chars_ptr;
      Stmt  : System.Address;
      Rc    : Interfaces.C.int;
      Rowid : Long_Long_Integer;
   begin
      if DB = System.Null_Address then return; end if;

      CS := New_String (SQL_Meta);
      Rc := c_prepare_v2 (DB, CS, -1, Stmt, System.Null_Address);
      Free (CS);
      if Rc /= SQLITE_OK then return; end if;

      Bind_Text (Stmt, 1, Session_ID);
      Bind_Text (Stmt, 2, Content);
      Bind_Text (Stmt, 3,
        Ada.Calendar.Formatting.Image (Ada.Calendar.Clock));
      declare
         Dummy : Interfaces.C.int;
         pragma Warnings (Off, "useless assignment");
      begin
         Dummy := c_step (Stmt);
         Dummy := c_finalize (Stmt);
         pragma Unreferenced (Dummy);
      end;

      Rowid := c_last_insert_rowid (DB);

      declare
         JSON_Vec : constant String := Embedding_To_JSON (Vec);
         SQL_Vec  : constant String :=
           "INSERT INTO vec_memories (rowid, embedding) VALUES (?, ?)";
         Rc2   : Interfaces.C.int;
         Stmt2 : System.Address;
         pragma Warnings (Off, "useless assignment");
      begin
         CS := New_String (SQL_Vec);
         Rc2 := c_prepare_v2 (DB, CS, -1, Stmt2, System.Null_Address);
         Free (CS);
         if Rc2 /= SQLITE_OK then return; end if;

         Rc2 := c_bind_int64 (Stmt2, 1, Rowid);
         Bind_Text (Stmt2, 2, JSON_Vec);
         Rc2 := c_step (Stmt2);
         Rc2 := c_finalize (Stmt2);
         pragma Unreferenced (Rc2);
      end;
   end Store;

   procedure Search
     (Mem        : Memory.SQLite.Memory_Handle;
      Query_Vec  : Embedding;
      K          : Positive;
      Results    : out Chunk_Array;
      Num        : out Natural)
   is
      DB : constant System.Address := Memory.SQLite.DB_Address (Mem);
      JSON_Vec : constant String := Embedding_To_JSON (Query_Vec);
      SQL : constant String :=
        "SELECT m.content, m.session_id, v.distance"
        & " FROM vec_memories v"
        & " JOIN vec_memories_meta m ON v.rowid = m.rowid"
        & " WHERE v.embedding MATCH json(?)"
        & " ORDER BY v.distance"
        & " LIMIT ?";
      CS   : chars_ptr;
      Stmt : System.Address;
      Rc   : Interfaces.C.int;
   begin
      Num := 0;
      Results := [others => (Content    => Ada.Strings.Unbounded.Null_Unbounded_String,
                             Session_ID => Ada.Strings.Unbounded.Null_Unbounded_String,
                             Score      => 0.0)];

      if DB = System.Null_Address then return; end if;

      CS := New_String (SQL);
      Rc := c_prepare_v2 (DB, CS, -1, Stmt, System.Null_Address);
      Free (CS);
      --  If prepare fails (vec extension not loaded), return silently.
      if Rc /= SQLITE_OK then return; end if;

      Bind_Text (Stmt, 1, JSON_Vec);
      Rc := c_bind_int (Stmt, 2, Interfaces.C.int (K));

      while c_step (Stmt) = SQLITE_ROW
        and then Num < K
        and then Num < Max_Results
      loop
         Num := Num + 1;
         Results (Num) :=
           (Content    => Ada.Strings.Unbounded.To_Unbounded_String
                            (Col_Text (Stmt, 0)),
            Session_ID => Ada.Strings.Unbounded.To_Unbounded_String
                            (Col_Text (Stmt, 1)),
            Score      => Float (c_column_double (Stmt, 2)));
      end loop;
      Rc := c_finalize (Stmt);
      pragma Unreferenced (Rc);
   end Search;

end Memory.Vector;
