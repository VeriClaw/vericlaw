with Ada.Calendar; use Ada.Calendar;
with Ada.Strings.Fixed;

package body Channels.Rate_Limit is

   Max_Sessions : constant := 64;

   type Session_Entry is record
      Key        : String (1 .. 128);
      Key_Len    : Natural         := 0;
      Window_Start : Ada.Calendar.Time;
      Count      : Natural         := 0;
   end record;

   Sessions : array (1 .. Max_Sessions) of Session_Entry;
   Num_Sessions : Natural := 0;

   function Check (Session_Key : String; Max_RPS : Positive) return Boolean is
      Now       : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Key_Len   : constant Natural :=
        Natural'Min (Session_Key'Length, 128);
      Key_Trunc : constant String :=
        Session_Key (Session_Key'First .. Session_Key'First + Key_Len - 1);
   begin
      --  Search existing entry.
      for I in 1 .. Num_Sessions loop
         if Sessions (I).Key_Len = Key_Len
           and then Sessions (I).Key (1 .. Key_Len) = Key_Trunc
         then
            declare
               Elapsed : constant Duration :=
                 Now - Sessions (I).Window_Start;
            begin
               --  Reset window if more than 1 second has passed.
               if Elapsed >= 1.0 then
                  Sessions (I).Window_Start := Now;
                  Sessions (I).Count := 1;
                  return True;
               end if;
               if Sessions (I).Count >= Max_RPS then
                  return False;  -- rate exceeded
               end if;
               Sessions (I).Count := Sessions (I).Count + 1;
               return True;
            end;
         end if;
      end loop;

      --  New session: find a free slot or evict oldest.
      declare
         Slot : Natural := 0;
      begin
         if Num_Sessions < Max_Sessions then
            Num_Sessions := Num_Sessions + 1;
            Slot := Num_Sessions;
         else
            --  Evict the entry with the oldest window (simple policy).
            Slot := 1;
            for I in 2 .. Max_Sessions loop
               if Sessions (I).Window_Start < Sessions (Slot).Window_Start then
                  Slot := I;
               end if;
            end loop;
         end if;
         Sessions (Slot).Key (1 .. Key_Len) := Key_Trunc;
         Sessions (Slot).Key_Len    := Key_Len;
         Sessions (Slot).Window_Start := Now;
         Sessions (Slot).Count      := 1;
      end;
      return True;
   end Check;

end Channels.Rate_Limit;
