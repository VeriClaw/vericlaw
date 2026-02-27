--  Syslog forwarding — POSIX C binding implementation.

with Interfaces.C;         use Interfaces.C;
with Interfaces.C.Strings; use Interfaces.C.Strings;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Audit.Syslog is

   LOG_NDELAY : constant := 8;  --  open syslog connection immediately

   --  POSIX syslog C bindings.
   procedure C_Openlog (Ident : chars_ptr; Option : int; Facility : int)
   with Import, Convention => C, External_Name => "openlog";

   --  syslog is variadic; bind as 3-arg: (priority, "%s", message).
   procedure C_Syslog (Priority : int; Fmt : chars_ptr; Msg : chars_ptr)
   with Import, Convention => C, External_Name => "syslog";

   --  Keep the ident string alive for the process lifetime (openlog stores
   --  the pointer, not a copy).
   Syslog_Ident : chars_ptr := Null_Ptr;

   procedure Enable (Ident : String := "vericlaw") is
   begin
      if Syslog_Ident /= Null_Ptr then
         Free (Syslog_Ident);
      end if;
      Syslog_Ident := New_String (Ident);
      C_Openlog (Syslog_Ident, int (LOG_NDELAY), int (LOG_USER));
   end Enable;

   procedure Log_Event
     (Event_Type : String;
      User_ID    : String := "";
      Channel    : String := "";
      Details    : String := "")
   is
      Msg      : Unbounded_String;
      C_Fmt    : chars_ptr;
      C_Msg    : chars_ptr;
      Priority : int := int (LOG_INFO);
   begin
      Append (Msg, Event_Type);
      if User_ID'Length > 0 then
         Append (Msg, " user=" & User_ID);
      end if;
      if Channel'Length > 0 then
         Append (Msg, " channel=" & Channel);
      end if;
      if Details'Length > 0 then
         Append (Msg, " " & Details);
      end if;

      if Event_Type = "access_denied" or else Event_Type = "auth_denied" then
         Priority := int (LOG_WARNING);
      end if;

      C_Fmt := New_String ("%s");
      C_Msg := New_String (To_String (Msg));
      C_Syslog (Priority, C_Fmt, C_Msg);
      Free (C_Fmt);
      Free (C_Msg);
   end Log_Event;

end Audit.Syslog;
