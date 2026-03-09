with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Text_IO;             use Ada.Text_IO;
with Plugins.Loader;         use Plugins.Loader;

procedure Plugin_Loader_Test is

   Passed : Natural := 0;
   Failed : Natural := 0;

   procedure Assert (Condition : Boolean; Label : String) is
   begin
      if Condition then
         Put_Line ("  PASS: " & Label);
         Passed := Passed + 1;
      else
         Put_Line ("  FAIL: " & Label);
         Failed := Failed + 1;
      end if;
   end Assert;

   procedure Write_File (Path : String; Content : String) is
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      Put (F, Content);
      Close (F);
   end Write_File;

   procedure Cleanup (Root : String) is
      Signed_Dir   : constant String := Root & "/signed-demo";
      Unsigned_Dir : constant String := Root & "/unsigned-demo";
      Broken_Dir   : constant String := Root & "/broken-demo";
   begin
      if Ada.Directories.Exists (Signed_Dir & "/manifest.json") then
         Ada.Directories.Delete_File (Signed_Dir & "/manifest.json");
      end if;
      if Ada.Directories.Exists (Unsigned_Dir & "/manifest.json") then
         Ada.Directories.Delete_File (Unsigned_Dir & "/manifest.json");
      end if;
      if Ada.Directories.Exists (Broken_Dir & "/manifest.json") then
         Ada.Directories.Delete_File (Broken_Dir & "/manifest.json");
      end if;
      if Ada.Directories.Exists (Signed_Dir) then
         Ada.Directories.Delete_Directory (Signed_Dir);
      end if;
      if Ada.Directories.Exists (Unsigned_Dir) then
         Ada.Directories.Delete_Directory (Unsigned_Dir);
      end if;
      if Ada.Directories.Exists (Broken_Dir) then
         Ada.Directories.Delete_Directory (Broken_Dir);
      end if;
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Directory (Root);
      end if;
   end Cleanup;

   procedure Test_Runtime_Discovery is
      Root         : constant String :=
        Ada.Directories.Current_Directory & "/plugin_loader_test_tmp";
      Signed_Dir   : constant String := Root & "/signed-demo";
      Unsigned_Dir : constant String := Root & "/unsigned-demo";
      Broken_Dir   : constant String := Root & "/broken-demo";
      Registry     : Plugin_Registry;
   begin
      Cleanup (Root);
      Ada.Directories.Create_Directory (Root);
      Ada.Directories.Create_Directory (Signed_Dir);
      Ada.Directories.Create_Directory (Unsigned_Dir);
      Ada.Directories.Create_Directory (Broken_Dir);

      Write_File
        (Signed_Dir & "/manifest.json",
         "{""name"":""signed-demo"",""version"":""1.0.0"",""entry"":""signed.sh"","
         & """tools"":[""file_read"",""network_fetch""],"
         & """signature_state"":""signed_trusted_key""}");
      Write_File
        (Unsigned_Dir & "/manifest.json",
         "{""name"":""unsigned-demo"",""version"":""0.1.0"",""entry"":""unsigned.sh"","
         & """tools"":[""file_read""],""signature_state"":""unsigned""}");
      Write_File (Broken_Dir & "/manifest.json", "{ not valid json");

      Discover_And_Load (Root, Registry);
      Assert (Registry.Num_Loaded = 3, "Discover_And_Load records all manifests");
      Assert (Loaded_Plugin_Count (Registry) = 1,
              "Exactly one manifest is loadable");
      Assert (Denied_Plugin_Count (Registry) = 1,
              "Unsigned manifest is denied");
      Assert (Error_Plugin_Count (Registry) = 1,
              "Malformed manifest is captured as error");
      Assert (Is_Plugin_Loaded (Registry, "signed-demo"),
              "Trusted manifest is marked as loaded");

      Load_Runtime_Registry (Root);
      declare
         JSON : constant String := Runtime_Registry_JSON;
      begin
         Assert
           (Ada.Strings.Fixed.Index (JSON, "manifest_discovery_only") > 0,
            "Runtime registry JSON reports discovery-only mode");
         Assert
           (Ada.Strings.Fixed.Index (JSON, "signed_trusted_key_required") > 0,
            "Runtime registry JSON reports the trusted-signature load policy");
         Assert
           (Ada.Strings.Fixed.Index (JSON, "signed-demo") > 0,
            "Runtime registry JSON includes loaded plugin names");
      end;

      Cleanup (Root);
   end Test_Runtime_Discovery;

   procedure Test_Default_Path_Resolution is
      Resolved : constant String := Resolve_Plugin_Directory ("");
   begin
      Assert (Resolved'Length > 0,
              "Resolve_Plugin_Directory returns a default path");
   end Test_Default_Path_Resolution;

begin
   Put_Line ("=== plugin_loader_test ===");
   Test_Default_Path_Resolution;
   Test_Runtime_Discovery;

   Put_Line ("");
   Put_Line ("Results: " & Natural'Image (Passed) & " passed, "
             & Natural'Image (Failed) & " failed");
   if Failed > 0 then
      raise Program_Error with Natural'Image (Failed) & " test(s) failed";
   end if;
end Plugin_Loader_Test;
