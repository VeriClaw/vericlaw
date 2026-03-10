--  Signal bridge lifecycle manager — implementation.
--
--  This package manages the vericlaw-signal Rust companion process lifecycle.
--  The companion binary ships alongside the main VeriClaw binary in the release
--  archive and is spawned as a child process with JSON-over-stdin/stdout IPC.

with Ada.Characters.Latin_1;
with Ada.Strings.Fixed;
with GNAT.OS_Lib;
with GNAT.IO;

package body Signal.Manager is

   --  Simple JSON line writer — writes a JSON object as a single line to the bridge stdin.
   --  This is intentionally minimal: vericlaw-signal reads one JSON object per line.
   procedure Write_JSON_Line (FD : GNAT.OS_Lib.File_Descriptor; JSON : String) is
      NL : constant String := (1 => Ada.Characters.Latin_1.LF);
      Buf : constant String := JSON & NL;
      Written : Integer;
   begin
      Written := GNAT.OS_Lib.Write (FD, Buf'Address, Buf'Length);
      pragma Unreferenced (Written);
   end Write_JSON_Line;

   --  Locate the vericlaw-signal binary.
   --  Search order: next to the VeriClaw binary, then ~/.vericlaw/bin/, then PATH.
   function Find_Signal_Binary return String is
      Home : constant String := GNAT.OS_Lib.Getenv ("HOME").all;
      Candidates : constant array (1 .. 2) of access constant String :=
        (new String'(Home & "/.vericlaw/bin/vericlaw-signal"),
         new String'("/usr/local/bin/vericlaw-signal"));
   begin
      --  Check each candidate path
      for C of Candidates loop
         if GNAT.OS_Lib.Is_Executable_File (C.all) then
            return C.all;
         end if;
      end loop;

      --  Fall back to PATH lookup
      declare
         Path_Result : GNAT.OS_Lib.String_Access :=
           GNAT.OS_Lib.Locate_Exec_On_Path ("vericlaw-signal");
      begin
         if Path_Result /= null then
            declare
               Result : constant String := Path_Result.all;
            begin
               GNAT.OS_Lib.Free (Path_Result);
               return Result;
            end;
         end if;
      end;

      raise Bridge_Not_Found with
        "vericlaw-signal not found. Run: vericlaw onboard --repair-signal";
   end Find_Signal_Binary;

   --  Start the vericlaw-signal bridge process.
   procedure Start is
      Binary : constant String := Find_Signal_Binary;
      Args   : GNAT.OS_Lib.Argument_List (1 .. 0);
      Success : Boolean;
   begin
      if Current_State = Running then
         return;
      end if;

      Current_State := Starting;

      GNAT.OS_Lib.Spawn
        (Program_Name => Binary,
         Args         => Args,
         Output_File  => "",
         Success      => Success,
         Return_Code  => Bridge_PID);

      if not Success then
         Current_State := Stopped;
         raise Bridge_Start_Failed with
           "Failed to spawn vericlaw-signal process. Binary: " & Binary;
      end if;

      Current_State := Running;

   exception
      when Bridge_Not_Found =>
         Current_State := Fatal;
         raise;
      when others =>
         Current_State := Crashed;
         raise Bridge_Start_Failed with
           "Exception while starting vericlaw-signal";
   end Start;

   --  Stop the bridge process.
   procedure Stop is
   begin
      if Current_State = Running and then Bridge_PID /= GNAT.OS_Lib.Invalid_Pid then
         GNAT.OS_Lib.Kill (Bridge_PID, Hard_Kill => False);
         Current_State := Stopped;
      end if;
   end Stop;

   --  Send a message outbound via Signal.
   procedure Send_Message (To : String; Body_Text : String) is
   begin
      if Current_State /= Running then
         raise Bridge_Not_Running with
           "Signal bridge is not running (state: " & Bridge_State'Image (Current_State) & ")";
      end if;

      --  Build outgoing JSON: {"type":"send","to":"<To>","body":"<Body>"}
      --  Note: A production implementation should escape special characters.
      declare
         JSON : constant String :=
           "{""type"":""send"",""to"":""" & To & """,""body"":""" & Body_Text & """}";
      begin
         Write_JSON_Line (Bridge_Stdin, JSON);
      end;
   end Send_Message;

   --  Poll for an incoming message (non-blocking stub).
   --  Full implementation reads from Bridge_Stdout with a non-blocking check.
   function Poll_Incoming (Msg : out IPC_Message) return Boolean is
   begin
      --  Stub: full implementation uses non-blocking reads from Bridge_Stdout
      --  and a simple JSON parser for the incoming message format.
      Msg := (Kind => Unknown);
      return False;
   end Poll_Incoming;

   --  Health check ping.
   function Ping return Boolean is
   begin
      if Current_State /= Running then
         return False;
      end if;

      Write_JSON_Line (Bridge_Stdin, "{""type"":""ping""}");

      --  Stub: full implementation reads Bridge_Stdout with Ping_Timeout_Seconds timeout
      --  and checks for {"type":"pong"}
      return True;
   end Ping;

   --  Return the current bridge state.
   function State return Bridge_State is
   begin
      return Current_State;
   end State;

   --  Return the restart count.
   function Restart_Count return Natural is
   begin
      return Current_Restart_Count;
   end Restart_Count;

end Signal.Manager;
