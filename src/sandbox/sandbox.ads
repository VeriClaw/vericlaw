pragma SPARK_Mode (Off);
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
package Sandbox is

   Max_Hosts : constant := 16;
   Max_Paths : constant := 32;

   type Host_Entry is record
      Host    : String (1 .. 256);
      Host_Len : Natural := 0;
   end record;
   type Host_List is array (1 .. Max_Hosts) of Host_Entry;

   type Path_Entry is record
      Path     : String (1 .. 1024);
      Path_Len : Natural := 0;
   end record;
   type Path_List is array (1 .. Max_Paths) of Path_Entry;

   type Sandbox_Policy is record
      Allow_Network    : Boolean := False;
      Allowed_Hosts    : Host_List;
      Num_Hosts        : Natural := 0;
      Writable_Paths   : Path_List;
      Num_Writable     : Natural := 0;
      Readable_Paths   : Path_List;
      Num_Readable     : Natural := 0;
      Allow_Subprocess : Boolean := False;
      Max_Memory_MB    : Positive := 512;
      Max_Open_Files   : Positive := 64;
   end record;

   function Is_Enforced return Boolean;

   procedure Enforce (Policy : Sandbox_Policy)
     with Pre => not Is_Enforced;
   --  Applies OS-native sandboxing. Cannot be undone.
   --  Linux: seccomp BPF filter
   --  macOS: sandbox-exec profile generation
   --  Windows: restricted token

   procedure Set_Resource_Limits (Max_Memory_MB : Positive; Max_Open_Files : Positive);
   --  Set rlimits (Linux/macOS) or job object limits (Windows)

end Sandbox;
