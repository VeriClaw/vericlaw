--  Syslog forwarding for audit events.
--  Uses POSIX openlog/syslog C bindings (Linux and macOS).
--  SPARK_Mode is Off because C imports cannot be formally verified.

package Audit.Syslog is
   pragma SPARK_Mode (Off);

   procedure Enable (Ident : String := "vericlaw");
   --  Open syslog connection.  Call once at startup.

   procedure Log_Event
     (Event_Type : String;
      User_ID    : String := "";
      Channel    : String := "";
      Details    : String := "");
   --  Write an event to syslog.
   --  Format: "{event_type} [user={user_id}] [channel={channel}] [details]"
   --  Security events (access_denied, auth_denied) use LOG_WARNING;
   --  all others use LOG_INFO.

private
   LOG_USER    : constant := 8;   --  syslog facility: LOG_USER
   LOG_INFO    : constant := 6;   --  priority: informational
   LOG_WARNING : constant := 4;   --  priority: warning (security events)
end Audit.Syslog;
