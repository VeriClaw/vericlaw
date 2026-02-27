pragma SPARK_Mode (Off);
with Ada.Text_IO;
with Ada.Calendar;
with Ada.Calendar.Formatting;

package body Logging is

   --  Thread-safe output via a protected object.
   protected Log_Mutex is
      entry Put (Line : String);
   end Log_Mutex;

   protected body Log_Mutex is
      entry Put (Line : String) when True is
      begin
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Line);
      end Put;
   end Log_Mutex;

   --  JSON-escape backslashes and double-quotes in a message string.
   function Escape (S : String) return String is
      Result : String (1 .. S'Length * 2);
      Pos    : Natural := 0;
   begin
      for C of S loop
         if C = '\' or else C = '"' then
            Pos := Pos + 1;
            Result (Pos) := '\';
         end if;
         Pos := Pos + 1;
         Result (Pos) := C;
      end loop;
      return Result (1 .. Pos);
   end Escape;

   function Level_String (Level : Log_Level) return String is
   begin
      case Level is
         when Debug   => return "debug";
         when Info    => return "info";
         when Warning => return "warning";
         when Error   => return "error";
      end case;
   end Level_String;

   procedure Log
     (Level   : Log_Level;
      Message : String;
      Context : String := "")
   is
      TS  : constant String := Ada.Calendar.Formatting.Image
              (Ada.Calendar.Clock, Include_Time_Fraction => False) & "Z";
      Ctx : constant String :=
              (if Context = "" then "{}" else "{" & Context & "}");
      Line : constant String :=
               "{""ts"":""" & TS
               & """,""level"":""" & Level_String (Level)
               & """,""msg"":""" & Escape (Message)
               & """,""ctx"":" & Ctx & "}";
   begin
      Log_Mutex.Put (Line);
   end Log;

   procedure Info (Message : String; Context : String := "") is
   begin
      Log (Logging.Info, Message, Context);
   end Info;

   procedure Warning (Message : String; Context : String := "") is
   begin
      Log (Logging.Warning, Message, Context);
   end Warning;

   procedure Error (Message : String; Context : String := "") is
   begin
      Log (Logging.Error, Message, Context);
   end Error;

   procedure Debug (Message : String; Context : String := "") is
   begin
      Log (Logging.Debug, Message, Context);
   end Debug;

end Logging;
