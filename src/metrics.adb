with Ada.Calendar;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

pragma SPARK_Mode (Off);
package body Metrics is

   use type Ada.Calendar.Time;

   --  Captured at elaboration time; used to compute vericlaw_uptime_seconds.
   Start_Time : constant Ada.Calendar.Time := Ada.Calendar.Clock;

   Max_Counters : constant := 32;

   type Counter_Entry is record
      Active : Boolean          := False;
      Name   : Unbounded_String;
      Label  : Unbounded_String;
      Count  : Natural          := 0;
   end record;

   type Counter_Array is array (1 .. Max_Counters) of Counter_Entry;

   protected Store is
      procedure Inc (Name : String; Label : String);
      procedure Snapshot (Data : out Counter_Array; Num : out Natural);
   private
      Entries : Counter_Array;
      Size    : Natural := 0;
   end Store;

   protected body Store is

      procedure Inc (Name : String; Label : String) is
      begin
         for I in 1 .. Size loop
            if Entries (I).Active
              and then To_String (Entries (I).Name)  = Name
              and then To_String (Entries (I).Label) = Label
            then
               Entries (I).Count := Entries (I).Count + 1;
               return;
            end if;
         end loop;
         if Size < Max_Counters then
            Size := Size + 1;
            Entries (Size).Active := True;
            Set_Unbounded_String (Entries (Size).Name,  Name);
            Set_Unbounded_String (Entries (Size).Label, Label);
            Entries (Size).Count := 1;
         end if;
      end Inc;

      procedure Snapshot (Data : out Counter_Array; Num : out Natural) is
      begin
         Data := Entries;
         Num  := Size;
      end Snapshot;

   end Store;

   --  Strip the leading space that Ada's 'Image adds for non-negative values.
   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   procedure Increment (Name : String; Label : String := "") is
   begin
      Store.Inc (Name, Label);
   end Increment;

   --  Infer the Prometheus label key name from the metric name.
   function Label_Key (N : String) return String is
   begin
      if N = "requests_total" or else N = "errors_total" then
         return "channel";
      elsif N = "provider_calls_total" or else N = "provider_errors_total" then
         return "provider";
      elsif N = "tool_calls_total" then
         return "tool";
      else
         return "label";
      end if;
   end Label_Key;

   function Get_Counter (Name : String; Label : String := "") return Natural is
      Data  : Counter_Array;
      Num   : Natural;
      Total : Natural := 0;
   begin
      Store.Snapshot (Data, Num);
      for I in 1 .. Num loop
         if Data (I).Active
           and then To_String (Data (I).Name) = Name
           and then (Label = "*"
                     or else To_String (Data (I).Label) = Label)
         then
            Total := Total + Data (I).Count;
         end if;
      end loop;
      return Total;
   end Get_Counter;

   function Render return String is
      Data      : Counter_Array;
      Num       : Natural;
      Result    : Unbounded_String;
      Last_Name : Unbounded_String;
      Elapsed   : constant Duration :=
        Ada.Calendar.Clock - Start_Time;
      Secs      : constant Natural  := Natural (Elapsed);
   begin
      Store.Snapshot (Data, Num);

      for I in 1 .. Num loop
         if Data (I).Active then
            declare
               N    : constant String := To_String (Data (I).Name);
               L    : constant String := To_String (Data (I).Label);
               Full : constant String := "vericlaw_" & N;
            begin
               --  Emit # TYPE header once per metric family (relies on
               --  counters of the same family being contiguous, which holds
               --  because they are inserted in first-seen order per channel).
               if To_String (Last_Name) /= N then
                  if Length (Result) > 0 then
                     Append (Result, ASCII.LF);
                  end if;
                  Append (Result,
                    "# TYPE " & Full & " counter" & ASCII.LF);
                  Set_Unbounded_String (Last_Name, N);
               end if;

               if L'Length > 0 then
                  Append (Result,
                    Full & "{" & Label_Key (N) & "=""" & L & """} "
                    & Img (Data (I).Count) & ASCII.LF);
               else
                  Append (Result,
                    Full & " " & Img (Data (I).Count) & ASCII.LF);
               end if;
            end;
         end if;
      end loop;

      Append (Result, ASCII.LF);
      Append (Result, "# TYPE vericlaw_uptime_seconds gauge" & ASCII.LF);
      Append (Result, "vericlaw_uptime_seconds " & Img (Secs) & ASCII.LF);

      return To_String (Result);
   end Render;

end Metrics;
