--  Signal bridge lifecycle manager.
--
--  Manages the bundled `vericlaw-signal` Rust companion binary as a child process.
--  Communication is via JSON-over-stdin/stdout (no sockets, no HTTP, no port allocation).
--
--  IPC message format:
--    Incoming (vericlaw-signal → VeriClaw):
--      {"type":"incoming","from":"+44...","body":"...","image":null,"audio":null}
--    Outgoing (VeriClaw → vericlaw-signal):
--      {"type":"send","to":"+44...","body":"..."}
--    Health ping (VeriClaw → vericlaw-signal):
--      {"type":"ping"}
--    Health pong (vericlaw-signal → VeriClaw):
--      {"type":"pong"}
--    Provisioning QR (vericlaw-signal → VeriClaw, during onboard):
--      {"type":"provision_qr","data":"...","text":"..."}
--
--  VeriClaw spawns vericlaw-signal on startup and manages its lifecycle:
--    - Starts the process and monitors health via periodic pings
--    - Restarts on crash (up to Max_Restart_Attempts times)
--    - Surfaces a fatal error if the bridge is unrecoverable
--    - Relays QR code data to the terminal UI during onboard/repair

with GNAT.OS_Lib;

package Signal.Manager is

   --  IPC message kinds
   type IPC_Kind is (Incoming, Send, Ping, Pong, Provision_QR, Unknown);

   --  Represents a single IPC message exchanged with vericlaw-signal
   type IPC_Message (Kind : IPC_Kind := Unknown) is record
      case Kind is
         when Incoming =>
            From  : String (1 .. 32) := (others => ' ');
            From_Last : Natural := 0;
            Body_Text : String (1 .. 4096) := (others => ' ');
            Body_Last : Natural := 0;
            Image_Path : String (1 .. 256) := (others => ' ');
            Image_Last : Natural := 0;
            Audio_Path : String (1 .. 256) := (others => ' ');
            Audio_Last : Natural := 0;
         when Send =>
            To   : String (1 .. 32) := (others => ' ');
            To_Last : Natural := 0;
            Send_Body : String (1 .. 4096) := (others => ' ');
            Send_Body_Last : Natural := 0;
         when Provision_QR =>
            QR_Data : String (1 .. 512) := (others => ' ');
            QR_Data_Last : Natural := 0;
            QR_Text : String (1 .. 4096) := (others => ' ');
            QR_Text_Last : Natural := 0;
         when Ping | Pong | Unknown =>
            null;
      end case;
   end record;

   --  Bridge process state
   type Bridge_State is (Stopped, Starting, Running, Crashed, Fatal);

   --  Maximum number of automatic restart attempts before entering Fatal state
   Max_Restart_Attempts : constant := 3;

   --  Health ping interval in seconds
   Ping_Interval_Seconds : constant := 30;

   --  Ping timeout: if no pong within this many seconds, the bridge is considered crashed
   Ping_Timeout_Seconds : constant := 10;

   --  Start the vericlaw-signal bridge process.
   --  Locates the binary relative to the VeriClaw executable directory,
   --  then in ~/.vericlaw/bin/, then in PATH.
   --  Raises Bridge_Not_Found if the binary cannot be located.
   --  Raises Bridge_Start_Failed if the process cannot be spawned.
   procedure Start;

   --  Stop the bridge process gracefully (SIGTERM, then SIGKILL after 5s).
   procedure Stop;

   --  Send a message outbound via Signal.
   --  Raises Bridge_Not_Running if the bridge is not in Running state.
   procedure Send_Message (To : String; Body_Text : String);

   --  Poll for an incoming message (non-blocking).
   --  Returns True and populates Msg if a message is available.
   --  Returns False immediately if no message is waiting.
   function Poll_Incoming (Msg : out IPC_Message) return Boolean;

   --  Perform a health check ping.
   --  Returns True if the bridge responds with a pong within Ping_Timeout_Seconds.
   function Ping return Boolean;

   --  Return the current bridge state.
   function State return Bridge_State;

   --  Return the number of times the bridge has been restarted since VeriClaw started.
   function Restart_Count return Natural;

   --  Raised when the vericlaw-signal binary cannot be found
   Bridge_Not_Found : exception;

   --  Raised when the bridge process cannot be started
   Bridge_Start_Failed : exception;

   --  Raised when Send_Message is called while the bridge is not running
   Bridge_Not_Running : exception;

   --  Raised when the bridge has exceeded Max_Restart_Attempts
   Bridge_Fatal : exception;

private
   --  Process handle for the running vericlaw-signal child process
   Bridge_PID : GNAT.OS_Lib.Process_Id := GNAT.OS_Lib.Invalid_Pid;

   --  Current state
   Current_State : Bridge_State := Stopped;

   --  Restart counter
   Current_Restart_Count : Natural := 0;

   --  Stdin/stdout pipe descriptors
   Bridge_Stdin  : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
   Bridge_Stdout : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;

end Signal.Manager;
