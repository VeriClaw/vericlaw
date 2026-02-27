with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Strings.Fixed;

package body Tools.Cron is

   --  Escape a string for embedding in a JSON string value.
   function JSON_Escape (S : String) return String is
      R : Unbounded_String;
   begin
      for C of S loop
         if C = '"' then
            Append (R, "\""");
         elsif C = '\' then
            Append (R, "\\");
         elsif C = ASCII.LF then
            Append (R, "\n");
         elsif C = ASCII.CR then
            Append (R, "\r");
         else
            Append (R, C);
         end if;
      end loop;
      return To_String (R);
   end JSON_Escape;

   function Parse_Interval_Seconds (Schedule : String) return Duration is
      Last : Positive;
      Unit : Character;
      N    : Integer;
   begin
      if Schedule'Length = 0 then
         return 3600.0;
      end if;
      Last := Schedule'Last;
      Unit := Schedule (Last);
      begin
         N := Integer'Value
           (Ada.Strings.Fixed.Trim
              (Schedule (Schedule'First .. Last - 1), Ada.Strings.Both));
      exception
         when others => return 3600.0;
      end;
      case Unit is
         when 'm'    => return Duration (N * 60);
         when 'h'    => return Duration (N * 3600);
         when 'd'    => return Duration (N * 86400);
         when others => return Duration (N);
      end case;
   end Parse_Interval_Seconds;

   function Next_Run_ISO (Schedule : String) return String is
      use Ada.Calendar;
      Interval : constant Duration := Parse_Interval_Seconds (Schedule);
   begin
      return Ada.Calendar.Formatting.Image (Clock + Interval);
   end Next_Run_ISO;

   function Jobs_To_JSON (R : Memory.SQLite.Cron_List_Result) return String is
      Out_S : Unbounded_String := To_Unbounded_String ("[");
      First : Boolean := True;
   begin
      for I in 1 .. R.Count loop
         declare
            J : constant Memory.SQLite.Cron_Job_Info := R.Jobs (I);
         begin
            if not First then
               Append (Out_S, ",");
            end if;
            First := False;
            Append (Out_S,
              "{""name"":"""
              & JSON_Escape (To_String (J.Name)) & ""","
              & """schedule"":"""
              & JSON_Escape (To_String (J.Schedule)) & ""","
              & """last_run"":"""
              & JSON_Escape (To_String (J.Last_Run)) & ""","
              & """next_run"":"""
              & JSON_Escape (To_String (J.Next_Run)) & ""","
              & """session_id"":"""
              & JSON_Escape (To_String (J.Session_ID)) & """}");
         end;
      end loop;
      Append (Out_S, "]");
      return To_String (Out_S);
   end Jobs_To_JSON;

   function Cron_Add
     (Mem        : Memory.SQLite.Memory_Handle;
      Name       : String;
      Schedule   : String;
      Prompt     : String;
      Session_ID : String) return Cron_Result
   is
      Result : Cron_Result;
   begin
      if not Memory.SQLite.Is_Open (Mem) then
         Set_Unbounded_String (Result.Error, "Memory not available");
         return Result;
      end if;
      Memory.SQLite.Cron_Insert
        (Mem, Name, Schedule, Prompt, Session_ID, Next_Run_ISO (Schedule));
      Set_Unbounded_String
        (Result.Output, "Scheduled '" & Name & "' to run every " & Schedule);
      Result.Success := True;
      return Result;
   end Cron_Add;

   function Cron_List (Mem : Memory.SQLite.Memory_Handle) return Cron_Result is
      Result : Cron_Result;
   begin
      if not Memory.SQLite.Is_Open (Mem) then
         Set_Unbounded_String (Result.Error, "Memory not available");
         return Result;
      end if;
      declare
         Jobs : constant Memory.SQLite.Cron_List_Result :=
           Memory.SQLite.Cron_List_Jobs (Mem);
      begin
         Set_Unbounded_String (Result.Output, Jobs_To_JSON (Jobs));
         Result.Success := True;
      end;
      return Result;
   end Cron_List;

   function Cron_Remove
     (Mem  : Memory.SQLite.Memory_Handle;
      Name : String) return Cron_Result
   is
      Result : Cron_Result;
   begin
      if not Memory.SQLite.Is_Open (Mem) then
         Set_Unbounded_String (Result.Error, "Memory not available");
         return Result;
      end if;
      Memory.SQLite.Cron_Delete (Mem, Name);
      Set_Unbounded_String (Result.Output, "Removed '" & Name & "'");
      Result.Success := True;
      return Result;
   end Cron_Remove;

end Tools.Cron;
