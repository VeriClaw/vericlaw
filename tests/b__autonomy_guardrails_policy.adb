pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__autonomy_guardrails_policy.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__autonomy_guardrails_policy.adb");
pragma Suppress (Overflow_Check);

package body ada_main is

   E078 : Short_Integer; pragma Import (Ada, E078, "system__os_lib_E");
   E014 : Short_Integer; pragma Import (Ada, E014, "ada__exceptions_E");
   E019 : Short_Integer; pragma Import (Ada, E019, "system__soft_links_E");
   E031 : Short_Integer; pragma Import (Ada, E031, "system__exception_table_E");
   E044 : Short_Integer; pragma Import (Ada, E044, "ada__containers_E");
   E073 : Short_Integer; pragma Import (Ada, E073, "ada__io_exceptions_E");
   E059 : Short_Integer; pragma Import (Ada, E059, "ada__strings_E");
   E061 : Short_Integer; pragma Import (Ada, E061, "ada__strings__maps_E");
   E065 : Short_Integer; pragma Import (Ada, E065, "ada__strings__maps__constants_E");
   E049 : Short_Integer; pragma Import (Ada, E049, "interfaces__c_E");
   E032 : Short_Integer; pragma Import (Ada, E032, "system__exceptions_E");
   E084 : Short_Integer; pragma Import (Ada, E084, "system__object_reader_E");
   E054 : Short_Integer; pragma Import (Ada, E054, "system__dwarf_lines_E");
   E027 : Short_Integer; pragma Import (Ada, E027, "system__soft_links__initialize_E");
   E043 : Short_Integer; pragma Import (Ada, E043, "system__traceback__symbolic_E");
   E100 : Short_Integer; pragma Import (Ada, E100, "ada__assertions_E");
   E009 : Short_Integer; pragma Import (Ada, E009, "channels__security_E");
   E112 : Short_Integer; pragma Import (Ada, E112, "gateway__provider__registry_E");
   E110 : Short_Integer; pragma Import (Ada, E110, "gateway__provider__credentials_E");
   E103 : Short_Integer; pragma Import (Ada, E103, "plugins__capabilities_E");
   E106 : Short_Integer; pragma Import (Ada, E106, "security__policy_E");
   E006 : Short_Integer; pragma Import (Ada, E006, "runtime__executor_E");

   Sec_Default_Sized_Stacks : array (1 .. 1) of aliased System.Secondary_Stack.SS_Stack (System.Parameters.Runtime_Default_Sec_Stack_Size);

   Local_Priority_Specific_Dispatching : constant String := "";
   Local_Interrupt_States : constant String := "";

   Is_Elaborated : Boolean := False;

   procedure adafinal is
      procedure s_stalib_adafinal;
      pragma Import (Ada, s_stalib_adafinal, "system__standard_library__adafinal");

      procedure Runtime_Finalize;
      pragma Import (C, Runtime_Finalize, "__gnat_runtime_finalize");

   begin
      if not Is_Elaborated then
         return;
      end if;
      Is_Elaborated := False;
      Runtime_Finalize;
      s_stalib_adafinal;
   end adafinal;

   type No_Param_Proc is access procedure;
   pragma Favor_Top_Level (No_Param_Proc);

   procedure adainit is
      Main_Priority : Integer;
      pragma Import (C, Main_Priority, "__gl_main_priority");
      Time_Slice_Value : Integer;
      pragma Import (C, Time_Slice_Value, "__gl_time_slice_val");
      WC_Encoding : Character;
      pragma Import (C, WC_Encoding, "__gl_wc_encoding");
      Locking_Policy : Character;
      pragma Import (C, Locking_Policy, "__gl_locking_policy");
      Queuing_Policy : Character;
      pragma Import (C, Queuing_Policy, "__gl_queuing_policy");
      Task_Dispatching_Policy : Character;
      pragma Import (C, Task_Dispatching_Policy, "__gl_task_dispatching_policy");
      Priority_Specific_Dispatching : System.Address;
      pragma Import (C, Priority_Specific_Dispatching, "__gl_priority_specific_dispatching");
      Num_Specific_Dispatching : Integer;
      pragma Import (C, Num_Specific_Dispatching, "__gl_num_specific_dispatching");
      Main_CPU : Integer;
      pragma Import (C, Main_CPU, "__gl_main_cpu");
      Interrupt_States : System.Address;
      pragma Import (C, Interrupt_States, "__gl_interrupt_states");
      Num_Interrupt_States : Integer;
      pragma Import (C, Num_Interrupt_States, "__gl_num_interrupt_states");
      Unreserve_All_Interrupts : Integer;
      pragma Import (C, Unreserve_All_Interrupts, "__gl_unreserve_all_interrupts");
      Detect_Blocking : Integer;
      pragma Import (C, Detect_Blocking, "__gl_detect_blocking");
      Default_Stack_Size : Integer;
      pragma Import (C, Default_Stack_Size, "__gl_default_stack_size");
      Default_Secondary_Stack_Size : System.Parameters.Size_Type;
      pragma Import (C, Default_Secondary_Stack_Size, "__gnat_default_ss_size");
      Bind_Env_Addr : System.Address;
      pragma Import (C, Bind_Env_Addr, "__gl_bind_env_addr");

      procedure Runtime_Initialize (Install_Handler : Integer);
      pragma Import (C, Runtime_Initialize, "__gnat_runtime_initialize");

      Finalize_Library_Objects : No_Param_Proc;
      pragma Import (C, Finalize_Library_Objects, "__gnat_finalize_library_objects");
      Binder_Sec_Stacks_Count : Natural;
      pragma Import (Ada, Binder_Sec_Stacks_Count, "__gnat_binder_ss_count");
      Default_Sized_SS_Pool : System.Address;
      pragma Import (Ada, Default_Sized_SS_Pool, "__gnat_default_ss_pool");

   begin
      if Is_Elaborated then
         return;
      end if;
      Is_Elaborated := True;
      Main_Priority := -1;
      Time_Slice_Value := -1;
      WC_Encoding := 'b';
      Locking_Policy := ' ';
      Queuing_Policy := ' ';
      Task_Dispatching_Policy := ' ';
      Priority_Specific_Dispatching :=
        Local_Priority_Specific_Dispatching'Address;
      Num_Specific_Dispatching := 0;
      Main_CPU := -1;
      Interrupt_States := Local_Interrupt_States'Address;
      Num_Interrupt_States := 0;
      Unreserve_All_Interrupts := 0;
      Detect_Blocking := 0;
      Default_Stack_Size := -1;

      ada_main'Elab_Body;
      Default_Secondary_Stack_Size := System.Parameters.Runtime_Default_Sec_Stack_Size;
      Binder_Sec_Stacks_Count := 1;
      Default_Sized_SS_Pool := Sec_Default_Sized_Stacks'Address;

      Runtime_Initialize (1);

      Finalize_Library_Objects := null;

      Ada.Exceptions'Elab_Spec;
      System.Soft_Links'Elab_Spec;
      System.Exception_Table'Elab_Body;
      E031 := E031 + 1;
      Ada.Containers'Elab_Spec;
      E044 := E044 + 1;
      Ada.Io_Exceptions'Elab_Spec;
      E073 := E073 + 1;
      Ada.Strings'Elab_Spec;
      E059 := E059 + 1;
      Ada.Strings.Maps'Elab_Spec;
      E061 := E061 + 1;
      Ada.Strings.Maps.Constants'Elab_Spec;
      E065 := E065 + 1;
      Interfaces.C'Elab_Spec;
      E049 := E049 + 1;
      System.Exceptions'Elab_Spec;
      E032 := E032 + 1;
      System.Object_Reader'Elab_Spec;
      E084 := E084 + 1;
      System.Dwarf_Lines'Elab_Spec;
      E054 := E054 + 1;
      System.Os_Lib'Elab_Body;
      E078 := E078 + 1;
      System.Soft_Links.Initialize'Elab_Body;
      E027 := E027 + 1;
      E019 := E019 + 1;
      System.Traceback.Symbolic'Elab_Body;
      E043 := E043 + 1;
      E014 := E014 + 1;
      Ada.Assertions'Elab_Spec;
      E100 := E100 + 1;
      E009 := E009 + 1;
      E112 := E112 + 1;
      E110 := E110 + 1;
      E103 := E103 + 1;
      E106 := E106 + 1;
      E006 := E006 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_autonomy_guardrails_policy");

   function main
     (argc : Integer;
      argv : System.Address;
      envp : System.Address)
      return Integer
   is
      procedure Initialize (Addr : System.Address);
      pragma Import (C, Initialize, "__gnat_initialize");

      procedure Finalize;
      pragma Import (C, Finalize, "__gnat_finalize");
      SEH : aliased array (1 .. 2) of Integer;

      Ensure_Reference : aliased System.Address := Ada_Main_Program_Name'Address;
      pragma Volatile (Ensure_Reference);

   begin
      if gnat_argc = 0 then
         gnat_argc := argc;
         gnat_argv := argv;
      end if;
      gnat_envp := envp;

      Initialize (SEH'Address);
      adainit;
      Ada_Main_Program;
      adafinal;
      Finalize;
      return (gnat_exit_status);
   end;

--  BEGIN Object file/option list
   --   /workspace/tests/channels.o
   --   /workspace/tests/channels-security.o
   --   /workspace/tests/gateway.o
   --   /workspace/tests/gateway-provider.o
   --   /workspace/tests/gateway-provider-registry.o
   --   /workspace/tests/gateway-provider-credentials.o
   --   /workspace/tests/plugins.o
   --   /workspace/tests/plugins-capabilities.o
   --   /workspace/tests/runtime.o
   --   /workspace/tests/security.o
   --   /workspace/tests/security-policy.o
   --   /workspace/tests/runtime-executor.o
   --   /workspace/tests/autonomy_guardrails_policy.o
   --   -L/workspace/tests/
   --   -L/workspace/tests/
   --   -L/opt/gnat/lib/gcc/x86_64-pc-linux-gnu/10.3.1/adalib/
   --   -static
   --   -lgnat
   --   -ldl
--  END Object file/option list   

end ada_main;
