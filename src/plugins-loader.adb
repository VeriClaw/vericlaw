with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;      use Ada.Exceptions;
with Ada.Text_IO;
with Config.JSON_Parser;  use Config.JSON_Parser;
with Logging;

package body Plugins.Loader
  with SPARK_Mode => Off
is

   Runtime_Discovery_Directory : Unbounded_String;
   Runtime_Discovery_Registry  : Plugin_Registry;

   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   function Parse_Signature_State
     (Root : JSON_Value_Type) return Capabilities.Signature_Verification_State
   is
      Signature_State : constant String :=
        Get_String (Root, "signature_state");
   begin
      if Signature_State = "signed_trusted_key" then
         return Capabilities.Manifest_Signed_Trusted_Key;
      elsif Signature_State = "signed_untrusted_key" then
         return Capabilities.Manifest_Signed_Untrusted_Key;
      elsif Signature_State = "unsigned" then
         return Capabilities.Manifest_Unsigned;
      elsif Signature_State'Length = 0
        and then Has_Key (Root, "signed")
        and then Get_Boolean (Root, "signed")
      then
         --  Legacy manifests can claim "signed", but the runtime only treats
         --  them as trusted when an external verifier emits signature_state.
         return Capabilities.Manifest_Signed_Untrusted_Key;
      end if;
      return Capabilities.Manifest_Unsigned;
   end Parse_Signature_State;

   function Parse_Tool_Kind (S : String) return Capabilities.Tool_Kind is
   begin
      if S = "file_read" then return Capabilities.File_Read_Tool;
      elsif S = "file_write" then return Capabilities.File_Write_Tool;
      elsif S = "command_exec" then return Capabilities.Command_Exec_Tool;
      elsif S = "network_fetch" then return Capabilities.Network_Fetch_Tool;
      else raise Constraint_Error;
      end if;
   end Parse_Tool_Kind;

   function Resolve_Plugin_Directory (Configured_Path : String) return String is
      Home : constant String :=
        Ada.Environment_Variables.Value ("HOME", ".");
   begin
      if Configured_Path'Length = 0 then
         return Home & "/.vericlaw/plugins";
      elsif Configured_Path = "~" then
         return Home;
      elsif Configured_Path'Length > 1
        and then Configured_Path (Configured_Path'First
          .. Configured_Path'First + 1) = "~/"
      then
         return Home
           & "/"
           & Configured_Path (Configured_Path'First + 2 .. Configured_Path'Last);
      end if;
      return Configured_Path;
   end Resolve_Plugin_Directory;

   procedure Load_Manifest
     (Path : String;
      Info : out Plugin_Info)
   is
      File    : Ada.Text_IO.File_Type;
      Content : Unbounded_String;
      Line    : String (1 .. 4096);
      Last    : Natural;
      PR      : Parse_Result;
   begin
      Info.Status := Plugin_Error;

      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Text_IO.Get_Line (File, Line, Last);
         Append (Content, Line (1 .. Last));
      end loop;
      Ada.Text_IO.Close (File);

      PR := Parse (To_String (Content));
      if not PR.Valid then
         Set_Unbounded_String (Info.Deny_Reason, "Invalid manifest JSON");
         return;
      end if;

      Set_Unbounded_String (Info.Name,
        Get_String (PR.Root, "name"));
      Set_Unbounded_String (Info.Version,
        Get_String (PR.Root, "version"));
      Set_Unbounded_String (Info.Entry_Point,
        Get_String (PR.Root, "entry"));

      Info.Manifest.Signature := Parse_Signature_State (PR.Root);

      --  Parse requested tools.
      Info.Manifest.Granted_Tools := (others => False);
      if Has_Key (PR.Root, "tools") then
         declare
            Tools_Arr : constant JSON_Array_Type :=
              Value_To_Array (Get_Object (PR.Root, "tools"));
            Len       : constant Natural := Array_Length (Tools_Arr);
         begin
            for I in 1 .. Len loop
               declare
                  Tool_Name : constant String :=
                    Array_Item (Tools_Arr, I).Get;
               begin
                  declare
                     TK : constant Capabilities.Tool_Kind :=
                       Parse_Tool_Kind (Tool_Name);
                  begin
                     Info.Manifest.Granted_Tools (TK) := True;
                  end;
               exception
                  when Constraint_Error =>
                     Logging.Warning
                       ("Unknown plugin tool: " & Tool_Name);
               end;
            end loop;
         end;
      end if;

      --  Verify against SPARK-proved capability policy.
      declare
         use Capabilities;
         Sig_Check : constant Signature_Decision :=
           Signature_Policy_Decision (Info.Manifest.Signature);
      begin
         if Sig_Check /= Signature_Allow then
            Info.Status := Plugin_Denied;
            Set_Unbounded_String (Info.Deny_Reason,
              "Signature policy: "
              & Signature_Decision'Image (Sig_Check));
            return;
         end if;
      end;

      Info.Status := Plugin_Loaded;

   exception
      when E : others =>
         Set_Unbounded_String (Info.Deny_Reason,
           "Failed to parse manifest (" & Exception_Name (E) & ")");
         Info.Status := Plugin_Error;
   end Load_Manifest;

   procedure Discover_And_Load
     (Dir      : String;
      Registry : out Plugin_Registry)
   is
      use Ada.Directories;
      Search  : Search_Type;
      Dir_Ent : Directory_Entry_Type;
   begin
      Registry.Num_Loaded := 0;

      if not Exists (Dir) then
         Logging.Info ("Plugin directory not found: " & Dir);
         return;
      end if;

      Start_Search (Search, Dir, "*", (Directory => True, others => False));
      while More_Entries (Search) loop
         exit when Registry.Num_Loaded >= Max_Plugins;
         Get_Next_Entry (Search, Dir_Ent);

         declare
            Name : constant String := Simple_Name (Dir_Ent);
            Manifest_Path : constant String :=
              Full_Name (Dir_Ent) & "/manifest.json";
         begin
            if Name /= "." and then Name /= ".."
              and then Exists (Manifest_Path)
            then
               Registry.Num_Loaded := Registry.Num_Loaded + 1;
               Load_Manifest
                 (Manifest_Path,
                  Registry.Plugins (Registry.Num_Loaded));

               case Registry.Plugins (Registry.Num_Loaded).Status is
                  when Plugin_Loaded =>
                     Logging.Info ("Plugin loaded: " & Name);
                  when Plugin_Denied =>
                     Logging.Warning ("Plugin denied: " & Name & " — "
                       & To_String
                           (Registry.Plugins
                              (Registry.Num_Loaded).Deny_Reason));
                  when Plugin_Error =>
                     Logging.Warning ("Plugin error: " & Name & " — "
                       & To_String
                           (Registry.Plugins
                              (Registry.Num_Loaded).Deny_Reason));
               end case;
            end if;
         end;
      end loop;
      End_Search (Search);
   exception
      when E : others =>
         Logging.Warning ("Error scanning plugin directory: " & Dir
           & " (" & Exception_Name (E) & ")");
   end Discover_And_Load;

   function Is_Plugin_Loaded
     (Registry : Plugin_Registry;
      Name     : String) return Boolean
   is
   begin
      for I in 1 .. Registry.Num_Loaded loop
         if To_String (Registry.Plugins (I).Name) = Name
           and then Registry.Plugins (I).Status = Plugin_Loaded
         then
            return True;
         end if;
      end loop;
      return False;
   end Is_Plugin_Loaded;

   function Get_Plugin
     (Registry : Plugin_Registry;
      Name     : String) return Plugin_Info
   is
   begin
      for I in 1 .. Registry.Num_Loaded loop
         if To_String (Registry.Plugins (I).Name) = Name then
            return Registry.Plugins (I);
         end if;
      end loop;
      return (Status => Plugin_Error, others => <>);
   end Get_Plugin;

   procedure Load_Runtime_Registry (Configured_Directory : String) is
      Resolved_Directory : constant String :=
        Resolve_Plugin_Directory (Configured_Directory);
   begin
      Set_Unbounded_String (Runtime_Discovery_Directory, Resolved_Directory);
      Discover_And_Load (Resolved_Directory, Runtime_Discovery_Registry);
   end Load_Runtime_Registry;

   function Runtime_Registry return Plugin_Registry is
   begin
      return Runtime_Discovery_Registry;
   end Runtime_Registry;

   function Runtime_Plugin_Directory return String is
   begin
      if Length (Runtime_Discovery_Directory) = 0 then
         return Resolve_Plugin_Directory ("");
      end if;
      return To_String (Runtime_Discovery_Directory);
   end Runtime_Plugin_Directory;

   function Loaded_Plugin_Count (Registry : Plugin_Registry) return Natural is
      Count : Natural := 0;
   begin
      for I in 1 .. Registry.Num_Loaded loop
         if Registry.Plugins (I).Status = Plugin_Loaded then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Loaded_Plugin_Count;

   function Denied_Plugin_Count (Registry : Plugin_Registry) return Natural is
      Count : Natural := 0;
   begin
      for I in 1 .. Registry.Num_Loaded loop
         if Registry.Plugins (I).Status = Plugin_Denied then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Denied_Plugin_Count;

   function Error_Plugin_Count (Registry : Plugin_Registry) return Natural is
      Count : Natural := 0;
   begin
      for I in 1 .. Registry.Num_Loaded loop
         if Registry.Plugins (I).Status = Plugin_Error then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Error_Plugin_Count;

   function Plugin_Status_Name (Status : Plugin_Status) return String is
   begin
      case Status is
         when Plugin_Loaded =>
            return "loaded";
         when Plugin_Denied =>
            return "denied";
         when Plugin_Error =>
            return "error";
      end case;
   end Plugin_Status_Name;

   function Signature_State_Name
     (State : Capabilities.Signature_Verification_State) return String
   is
   begin
      case State is
         when Capabilities.Manifest_Unsigned =>
            return "unsigned";
         when Capabilities.Manifest_Signed_Untrusted_Key =>
            return "signed_untrusted_key";
         when Capabilities.Manifest_Signed_Trusted_Key =>
            return "signed_trusted_key";
      end case;
   end Signature_State_Name;

   function Tool_Kind_Name (Kind : Capabilities.Tool_Kind) return String is
   begin
      case Kind is
         when Capabilities.File_Read_Tool =>
            return "file_read";
         when Capabilities.File_Write_Tool =>
            return "file_write";
         when Capabilities.Command_Exec_Tool =>
            return "command_exec";
         when Capabilities.Network_Fetch_Tool =>
            return "network_fetch";
      end case;
   end Tool_Kind_Name;

   procedure Append_Tool_Array
     (Target              : in out Unbounded_String;
      Manifest            : Capabilities.Capability_Manifest;
      Consent_Required_Only : Boolean)
   is
      First : Boolean := True;
   begin
      Append (Target, "[");
      for Tool in Capabilities.Tool_Kind loop
         if Manifest.Granted_Tools (Tool)
           and then
             (not Consent_Required_Only
              or else Capabilities.Tool_Requires_Operator_Consent (Tool))
         then
            if not First then
               Append (Target, ",");
            end if;
            Append (Target, Escape_JSON_String (Tool_Kind_Name (Tool)));
            First := False;
         end if;
      end loop;
      Append (Target, "]");
   end Append_Tool_Array;

   function Plugin_JSON (Info : Plugin_Info) return String is
      Buf : Unbounded_String;
   begin
      Append (Buf, "{""name"":");
      Append (Buf, Escape_JSON_String (To_String (Info.Name)));
      Append (Buf, ",""version"":");
      Append (Buf, Escape_JSON_String (To_String (Info.Version)));
      Append (Buf, ",""entry_point"":");
      Append (Buf, Escape_JSON_String (To_String (Info.Entry_Point)));
      Append (Buf, ",""status"":");
      Append (Buf, Escape_JSON_String (Plugin_Status_Name (Info.Status)));
      Append (Buf, ",""signature_state"":");
      Append
        (Buf,
         Escape_JSON_String
           (Signature_State_Name (Info.Manifest.Signature)));
      Append (Buf, ",""granted_tools"":");
      Append_Tool_Array (Buf, Info.Manifest, Consent_Required_Only => False);
      Append (Buf, ",""operator_consent_required"":");
      Append_Tool_Array (Buf, Info.Manifest, Consent_Required_Only => True);
      Append (Buf, ",""deny_reason"":");
      Append (Buf, Escape_JSON_String (To_String (Info.Deny_Reason)));
      Append (Buf, "}");
      return To_String (Buf);
   end Plugin_JSON;

   function Runtime_Registry_JSON return String is
      Registry : constant Plugin_Registry := Runtime_Discovery_Registry;
      Buf      : Unbounded_String;
   begin
      Append (Buf, "{""mode"":");
      Append (Buf, Escape_JSON_String (Local_Plugin_Mode));
      Append (Buf, ",""load_policy"":");
      Append (Buf, Escape_JSON_String (Local_Load_Policy));
      Append (Buf, ",""plugin_directory"":");
      Append (Buf, Escape_JSON_String (Runtime_Plugin_Directory));
      Append (Buf, ",""plugins_discovered"":" & Img (Registry.Num_Loaded));
      Append (Buf, ",""plugins_loaded"":" & Img (Loaded_Plugin_Count (Registry)));
      Append (Buf, ",""plugins_denied"":" & Img (Denied_Plugin_Count (Registry)));
      Append (Buf, ",""plugins_errors"":" & Img (Error_Plugin_Count (Registry)));
      Append (Buf, ",""plugins"":[");
      for I in 1 .. Registry.Num_Loaded loop
         if I > 1 then
            Append (Buf, ",");
         end if;
         Append (Buf, Plugin_JSON (Registry.Plugins (I)));
      end loop;
      Append (Buf, "]}");
      return To_String (Buf);
   end Runtime_Registry_JSON;

end Plugins.Loader;
