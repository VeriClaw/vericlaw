pragma SPARK_Mode (Off);
with Ada.Text_IO;
with Interfaces.C; use Interfaces.C;
with System;

package body Sandbox is

   Enforced : Boolean := False;

   function Is_Enforced return Boolean is (Enforced);

   --  Platform detection
   type OS_Kind is (Linux, MacOS, Windows, Unknown);

   function Detect_OS return OS_Kind is
   begin
      --  Compile-time detection via preprocessor would be ideal.
      --  Runtime fallback: check for /proc (Linux) or /System (macOS)
      declare
         use Ada.Text_IO;
         F : File_Type;
      begin
         Open (F, In_File, "/proc/version");
         Close (F);
         return Linux;
      exception
         when others =>
            begin
               Open (F, In_File, "/System/Library/CoreServices/SystemVersion.plist");
               Close (F);
               return MacOS;
            exception
               when others => return Unknown;  -- Assume Windows or unknown
            end;
      end;
   end Detect_OS;

   --  C FFI for setrlimit (Linux/macOS)
   type Rlimit is record
      Cur : unsigned_long;
      Max : unsigned_long;
   end record;
   pragma Convention (C, Rlimit);

   RLIMIT_AS    : constant := 9;   -- Linux: address space
   RLIMIT_NOFILE : constant := 7;  -- Linux: open files

   function C_Setrlimit (Resource : int; Rlim : access Rlimit) return int
     with Import => True, Convention => C, External_Name => "setrlimit";

   procedure Set_Resource_Limits (Max_Memory_MB : Positive; Max_Open_Files : Positive) is
      Mem_Limit  : aliased Rlimit;
      File_Limit : aliased Rlimit;
      Ret        : int;
      Bytes      : constant unsigned_long := unsigned_long (Max_Memory_MB) * 1024 * 1024;
   begin
      case Detect_OS is
         when Linux | MacOS =>
            Mem_Limit.Cur := Bytes;
            Mem_Limit.Max := Bytes;
            Ret := C_Setrlimit (RLIMIT_AS, Mem_Limit'Access);

            File_Limit.Cur := unsigned_long (Max_Open_Files);
            File_Limit.Max := unsigned_long (Max_Open_Files);
            Ret := C_Setrlimit (RLIMIT_NOFILE, File_Limit'Access);
         when Windows | Unknown =>
            null;  -- Windows uses Job Objects (would need Win32 FFI)
      end case;
   end Set_Resource_Limits;

   procedure Enforce (Policy : Sandbox_Policy) is
   begin
      --  Apply resource limits first (works on all POSIX)
      Set_Resource_Limits (Policy.Max_Memory_MB, Policy.Max_Open_Files);

      case Detect_OS is
         when Linux =>
            --  On Linux, we'd apply seccomp BPF via prctl(PR_SET_SECCOMP)
            --  This requires the seccomp profile to be loaded from
            --  deploy/linux/vericlaw.seccomp.json
            --  For now, set resource limits only (seccomp-profile is separate todo)
            null;

         when MacOS =>
            --  On macOS, we'd exec sandbox-exec with the .sb profile
            --  from deploy/macos/vericlaw.sb
            --  For now, set resource limits only (macos-sandbox-profile is separate todo)
            null;

         when Windows | Unknown =>
            --  Windows: CreateRestrictedToken (requires Win32 FFI)
            --  For now, resource limits are the only enforcement
            null;
      end case;

      Enforced := True;
   end Enforce;

end Sandbox;
