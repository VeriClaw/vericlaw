pragma SPARK_Mode (Off);
with Ada.Text_IO;
with Ada.Calendar;
with Ada.Calendar.Formatting;

package body Logging is

   --  Thread-safe output via a protected object.
   protected Log_Mutex is
      entry Put (Line : String);
      procedure Set_Level (Level : Log_Level);
      function  Current_Level return Log_Level;
   private
      Min_Level : Log_Level := Info;
   end Log_Mutex;

   protected body Log_Mutex is
      entry Put (Line : String) when True is
      begin
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Line);
      end Put;

      procedure Set_Level (Level : Log_Level) is
      begin
         Min_Level := Level;
      end Set_Level;

      function Current_Level return Log_Level is
      begin
         return Min_Level;
      end Current_Level;
   end Log_Mutex;

   procedure Set_Min_Level (Level : Log_Level) is
   begin
      Log_Mutex.Set_Level (Level);
   end Set_Min_Level;

   function Get_Min_Level return Log_Level is
   begin
      return Log_Mutex.Current_Level;
   end Get_Min_Level;

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
      Context : String := "";
      Req_ID  : String := "")
   is
   begin
      --  Filter by minimum log level.
      if Log_Level'Pos (Level) < Log_Level'Pos (Log_Mutex.Current_Level) then
         return;
      end if;

      declare
         TS  : constant String := Ada.Calendar.Formatting.Image
                 (Ada.Calendar.Clock, Include_Time_Fraction => False) & "Z";
         Ctx : constant String :=
                 (if Context = "" then "{}" else "{" & Context & "}");
         RID : constant String :=
                 (if Req_ID = "" then ""
                  else ",""req_id"":""" & Escape (Req_ID) & """");
         Line : constant String :=
                  "{""ts"":""" & TS
                  & """,""level"":""" & Level_String (Level)
                  & """,""msg"":""" & Escape (Message)
                  & """" & RID
                  & ",""ctx"":" & Ctx & "}";
      begin
         Log_Mutex.Put (Line);
      end;
   end Log;

   procedure Info (Message : String; Context : String := ""; Req_ID : String := "") is
   begin
      Log (Logging.Info, Message, Context, Req_ID);
   end Info;

   procedure Warning (Message : String; Context : String := ""; Req_ID : String := "") is
   begin
      Log (Logging.Warning, Message, Context, Req_ID);
   end Warning;

   procedure Error (Message : String; Context : String := ""; Req_ID : String := "") is
   begin
      Log (Logging.Error, Message, Context, Req_ID);
   end Error;

   procedure Debug (Message : String; Context : String := ""; Req_ID : String := "") is
   begin
      Log (Logging.Debug, Message, Context, Req_ID);
   end Debug;

end Logging;
