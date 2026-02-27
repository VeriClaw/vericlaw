with Ada.Directories;
with Ada.Text_IO;
with Config.JSON_Parser;  use Config.JSON_Parser;
with Logging;

pragma SPARK_Mode (Off);
package body Plugins.Loader is

   function Parse_Tool_Kind (S : String) return Capabilities.Tool_Kind is
   begin
      if S = "file_read" then return Capabilities.File_Read_Tool;
      elsif S = "file_write" then return Capabilities.File_Write_Tool;
      elsif S = "command_exec" then return Capabilities.Command_Exec_Tool;
      elsif S = "network_fetch" then return Capabilities.Network_Fetch_Tool;
      else raise Constraint_Error;
      end if;
   end Parse_Tool_Kind;

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

      --  Parse signature status.
      if Has_Key (PR.Root, "signed")
        and then Get_Boolean (PR.Root, "signed")
      then
         Info.Manifest.Signature :=
           Capabilities.Manifest_Signed_Trusted_Key;
      else
         Info.Manifest.Signature := Capabilities.Manifest_Unsigned;
      end if;

      --  Parse requested tools.
      Info.Manifest.Granted_Tools := (others => False);
      if Has_Key (PR.Root, "tools") then
         declare
            Tools_Arr : constant JSON_Value_Type :=
              Get_Object (PR.Root, "tools");
            Len       : constant Natural := Array_Length (Tools_Arr);
         begin
            for I in 0 .. Len - 1 loop
               begin
                  declare
                     TK : constant Capabilities.Tool_Kind :=
                       Parse_Tool_Kind (Get_Array_String (Tools_Arr, I));
                  begin
                     Info.Manifest.Granted_Tools (TK) := True;
                  end;
               exception
                  when Constraint_Error =>
                     Logging.Warning ("Unknown plugin tool: " & Get_Array_String (Tools_Arr, I));
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
      when others =>
         Set_Unbounded_String (Info.Deny_Reason, "Failed to parse manifest");
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
      when others =>
         Logging.Warning ("Error scanning plugin directory: " & Dir);
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

end Plugins.Loader;
