with Ada.Calendar;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HTTP.Client;
with Logging;

package body Observability.Tracing
  with SPARK_Mode => Off
is

   --  -----------------------------------------------------------------------
   --  Internal state
   --  -----------------------------------------------------------------------

   Enabled  : Boolean := False;
   Endpoint : Unbounded_String;  -- base URL, e.g. "http://localhost:4318"

   --  Monotonic span-ID counter (starts at 1; 0 = No_Span).
   Next_ID : Natural := 1;

   Max_Attrs : constant := 8;
   type Attr_Entry is record
      Key   : Unbounded_String;
      Value : Unbounded_String;
   end record;
   type Attr_Array is array (1 .. Max_Attrs) of Attr_Entry;

   type Span_Record is record
      Active     : Boolean := False;
      Name       : Unbounded_String;
      Trace_Hex  : Unbounded_String;  -- 32-hex-char trace ID
      Span_Hex   : Unbounded_String;  -- 16-hex-char span ID
      Parent_Hex : Unbounded_String;  -- 16-hex-char or empty
      Start_Time : Ada.Calendar.Time;
      End_Time   : Ada.Calendar.Time;
      Attrs      : Attr_Array;
      Num_Attrs  : Natural := 0;
      Has_Error  : Boolean := False;
      Error_Msg  : Unbounded_String;
   end record;

   --  -----------------------------------------------------------------------
   --  Hex ID generation from counter
   --  -----------------------------------------------------------------------

   function Hex_Digit (N : Natural) return Character is
      H : constant String := "0123456789abcdef";
   begin
      return H (H'First + (N mod 16));
   end Hex_Digit;

   function To_Hex_16 (N : Natural) return String is
      Result : String (1 .. 16) := (others => '0');
      V      : Natural := N;
   begin
      for I in reverse Result'Range loop
         Result (I) := Hex_Digit (V);
         V := V / 16;
      end loop;
      return Result;
   end To_Hex_16;

   function To_Hex_32 (N : Natural) return String is
   begin
      return "0000000000000000" & To_Hex_16 (N);
   end To_Hex_32;

   --  -----------------------------------------------------------------------
   --  Protected bounded buffer for completed spans
   --  -----------------------------------------------------------------------

   Max_Buffer : constant := 256;
   type Span_Array is array (1 .. Max_Buffer) of Span_Record;

   protected Span_Buffer is
      procedure Enqueue (S : Span_Record);
      function Pending return Natural;
      entry Drain_All (Buf : out Span_Array; Count : out Natural);
   private
      Store : Span_Array;
      Num   : Natural := 0;
   end Span_Buffer;

   protected body Span_Buffer is
      procedure Enqueue (S : Span_Record) is
      begin
         if Num < Max_Buffer then
            Num := Num + 1;
            Store (Num) := S;
         end if;
      end Enqueue;

      function Pending return Natural is
      begin
         return Num;
      end Pending;

      entry Drain_All (Buf : out Span_Array; Count : out Natural)
        when True is
      begin
         Count := Num;
         for I in 1 .. Num loop
            Buf (I) := Store (I);
         end loop;
         Num := 0;
      end Drain_All;
   end Span_Buffer;

   --  -----------------------------------------------------------------------
   --  In-flight spans (indexed by Span_ID mod Max_Buffer)
   --  -----------------------------------------------------------------------

   Inflight : array (1 .. Max_Buffer) of Span_Record;

   function Slot (S : Span_ID) return Positive is
   begin
      return ((Natural (S) - 1) mod Max_Buffer) + 1;
   end Slot;

   --  -----------------------------------------------------------------------
   --  JSON helpers for OTLP export
   --  -----------------------------------------------------------------------

   function Escape_JSON (S : String) return String is
      Result : Unbounded_String;
   begin
      for C of S loop
         case C is
            when '"'    => Append (Result, "\""");
            when '\'    => Append (Result, "\\");
            when ASCII.LF => Append (Result, "\n");
            when ASCII.CR => Append (Result, "\r");
            when ASCII.HT => Append (Result, "\t");
            when others => Append (Result, C);
         end case;
      end loop;
      return To_String (Result);
   end Escape_JSON;

   --  Convert Ada.Calendar.Time to nanoseconds since Unix epoch (approx).
   function Time_To_Nanos (T : Ada.Calendar.Time) return String is
      use Ada.Calendar;
      Epoch : constant Time := Time_Of (1970, 1, 1, 0.0);
      Dur   : constant Duration := T - Epoch;
      Secs  : constant Long_Long_Integer := Long_Long_Integer (Dur);
      Nanos : constant Long_Long_Integer := Secs * 1_000_000_000;
   begin
      return Long_Long_Integer'Image (Nanos);
   end Time_To_Nanos;

   function Build_OTLP_JSON (Spans : Span_Array; Count : Natural) return String is
      Body_Str : Unbounded_String;
   begin
      Append (Body_Str,
        "{""resourceSpans"":[{""resource"":{""attributes"":["
        & "{""key"":""service.name"",""value"":{""stringValue"":""vericlaw""}}"
        & "]},""scopeSpans"":[{""scope"":{""name"":""observability.tracing""},"
        & """spans"":[");

      for I in 1 .. Count loop
         if I > 1 then
            Append (Body_Str, ",");
         end if;
         declare
            S : Span_Record renames Spans (I);
         begin
            Append (Body_Str,
              "{""traceId"":""" & To_String (S.Trace_Hex) & """"
              & ",""spanId"":""" & To_String (S.Span_Hex) & """");
            if Length (S.Parent_Hex) > 0 then
               Append (Body_Str,
                 ",""parentSpanId"":""" & To_String (S.Parent_Hex) & """");
            end if;
            Append (Body_Str,
              ",""name"":""" & Escape_JSON (To_String (S.Name)) & """"
              & ",""kind"":1"
              & ",""startTimeUnixNano"":" & Time_To_Nanos (S.Start_Time)
              & ",""endTimeUnixNano"":" & Time_To_Nanos (S.End_Time));

            --  Status
            if S.Has_Error then
               Append (Body_Str,
                 ",""status"":{""code"":2,""message"":"
                 & """" & Escape_JSON (To_String (S.Error_Msg)) & """}");
            end if;

            --  Attributes
            if S.Num_Attrs > 0 then
               Append (Body_Str, ",""attributes"":[");
               for A in 1 .. S.Num_Attrs loop
                  if A > 1 then
                     Append (Body_Str, ",");
                  end if;
                  Append (Body_Str,
                    "{""key"":""" & Escape_JSON (To_String (S.Attrs (A).Key))
                    & """,""value"":{""stringValue"":"
                    & """" & Escape_JSON (To_String (S.Attrs (A).Value))
                    & """}}");
               end loop;
               Append (Body_Str, "]");
            end if;

            Append (Body_Str, "}");
         end;
      end loop;

      Append (Body_Str, "]}]}]}");
      return To_String (Body_Str);
   end Build_OTLP_JSON;

   --  -----------------------------------------------------------------------
   --  Background flush task
   --  -----------------------------------------------------------------------

   task type Flush_Task is
      entry Start;
      entry Stop;
      pragma Unreferenced (Stop);
   end Flush_Task;

   task body Flush_Task is
      Running : Boolean := True;
   begin
      accept Start;
      while Running loop
         select
            accept Stop do
               Running := False;
            end Stop;
         or
            delay 5.0;
         end select;

         if Span_Buffer.Pending > 0 then
            declare
               Batch : Span_Array;
               Count : Natural;
               URL   : constant String :=
                 To_String (Endpoint) & "/v1/traces";
               Hdrs  : constant HTTP.Client.Header_Array (1 .. 0) :=
                 [others => <>];
            begin
               Span_Buffer.Drain_All (Batch, Count);
               if Count > 0 then
                  declare
                     JSON : constant String :=
                       Build_OTLP_JSON (Batch, Count);
                     Resp : constant HTTP.Client.Response :=
                       HTTP.Client.Post_JSON (URL, Hdrs, JSON,
                                              Timeout_Ms => 5_000);
                  begin
                     if not HTTP.Client.Is_Success (Resp) then
                        Logging.Warning ("tracing: OTLP flush failed: HTTP "
                          & Resp.Status_Code'Image
                          & (if Length (Resp.Error) > 0
                             then " — " & To_String (Resp.Error) else ""));
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;
   end Flush_Task;

   type Flush_Task_Access is access Flush_Task;
   Flusher : Flush_Task_Access := null;

   --  -----------------------------------------------------------------------
   --  Public API
   --  -----------------------------------------------------------------------

   procedure Initialize (OTLP_Endpoint : String) is
   begin
      if OTLP_Endpoint'Length = 0 then
         Enabled := False;
         return;
      end if;
      Set_Unbounded_String (Endpoint, OTLP_Endpoint);
      Enabled := True;
      Flusher := new Flush_Task;
      Flusher.Start;
   end Initialize;

   function Is_Enabled return Boolean is
   begin
      return Enabled;
   end Is_Enabled;

   function Start_Span (Name : String; Parent : Span_ID := No_Span) return Span_ID is
      ID : Span_ID;
      Sl : Positive;
   begin
      if not Enabled then
         return No_Span;
      end if;
      ID := Span_ID (Next_ID);
      Next_ID := Next_ID + 1;
      Sl := Slot (ID);
      Inflight (Sl).Active     := True;
      Set_Unbounded_String (Inflight (Sl).Name, Name);
      Set_Unbounded_String (Inflight (Sl).Span_Hex, To_Hex_16 (Natural (ID)));
      if Parent = No_Span then
         Set_Unbounded_String (Inflight (Sl).Trace_Hex, To_Hex_32 (Natural (ID)));
         Set_Unbounded_String (Inflight (Sl).Parent_Hex, "");
      else
         --  Inherit trace ID from parent, set parent span ID
         declare
            P_Sl : constant Positive := Slot (Parent);
         begin
            Inflight (Sl).Trace_Hex  := Inflight (P_Sl).Trace_Hex;
            Inflight (Sl).Parent_Hex := Inflight (P_Sl).Span_Hex;
         end;
      end if;
      Inflight (Sl).Start_Time := Ada.Calendar.Clock;
      Inflight (Sl).Num_Attrs  := 0;
      Inflight (Sl).Has_Error  := False;
      return ID;
   end Start_Span;

   procedure End_Span (S : Span_ID) is
      Sl : Positive;
   begin
      if not Enabled or else S = No_Span then
         return;
      end if;
      Sl := Slot (S);
      if not Inflight (Sl).Active then
         return;
      end if;
      Inflight (Sl).End_Time := Ada.Calendar.Clock;
      Inflight (Sl).Active   := False;
      Span_Buffer.Enqueue (Inflight (Sl));
   end End_Span;

   procedure Set_Attribute (S : Span_ID; Key : String; Value : String) is
      Sl : Positive;
   begin
      if not Enabled or else S = No_Span then
         return;
      end if;
      Sl := Slot (S);
      if Inflight (Sl).Num_Attrs < Max_Attrs then
         Inflight (Sl).Num_Attrs := Inflight (Sl).Num_Attrs + 1;
         Set_Unbounded_String
           (Inflight (Sl).Attrs (Inflight (Sl).Num_Attrs).Key, Key);
         Set_Unbounded_String
           (Inflight (Sl).Attrs (Inflight (Sl).Num_Attrs).Value, Value);
      end if;
   end Set_Attribute;

   procedure Set_Attribute (S : Span_ID; Key : String; Value : Integer) is
   begin
      Set_Attribute (S, Key, Integer'Image (Value));
   end Set_Attribute;

   procedure Set_Error (S : Span_ID; Message : String) is
      Sl : Positive;
   begin
      if not Enabled or else S = No_Span then
         return;
      end if;
      Sl := Slot (S);
      Inflight (Sl).Has_Error := True;
      Set_Unbounded_String (Inflight (Sl).Error_Msg, Message);
   end Set_Error;

end Observability.Tracing;
