--  Unit tests for Config.Schema defaults and Config.Loader.Load_From.
--  Runs without network or GNAT SPARK prover — pure Ada.

with Ada.Text_IO;      use Ada.Text_IO;
with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Config.Schema;    use Config.Schema;
with Config.Loader;    use Config.Loader;

procedure Config_Loader_Test is

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

   ---------------------------------------------------------
   --  Section 1: Default_Config schema values
   ---------------------------------------------------------
   procedure Test_Default_Config is
      Cfg : constant Agent_Config := Default_Config;
   begin
      Put_Line ("--- Default_Config ---");
      Assert (Cfg.Memory.Max_History = 50,
              "Default Max_History = 50");
      Assert (Cfg.Memory.Facts_Enabled,
              "Default Facts_Enabled = True");
      Assert (not Cfg.Tools.Shell_Enabled,
              "Default Shell_Enabled = False");
      Assert (Cfg.Tools.File_Enabled,
              "Default File_Enabled = True");
      Assert (not Cfg.Tools.Web_Fetch_Enabled,
              "Default Web_Fetch_Enabled = False");
      Assert (not Cfg.Tools.Brave_Search_Enabled,
              "Default Brave_Search_Enabled = False");
      Assert (Cfg.Gateway.Bind_Port = 8787,
              "Default Bind_Port = 8787");
      Assert (Cfg.Num_Providers >= 1,
              "Default Num_Providers >= 1");
   end Test_Default_Config;

   ---------------------------------------------------------
   --  Section 2: Load_From with a valid minimal JSON file
   ---------------------------------------------------------
   procedure Test_Load_From_Valid is
      Tmp_Dir  : constant String := Ada.Directories.Current_Directory;
      Tmp_Path : constant String := Tmp_Dir & "/test_config_valid.json";
      F        : File_Type;
      R        : Load_Result;
   begin
      Put_Line ("--- Load_From (valid JSON) ---");
      --  Write a minimal valid config
      Create (F, Out_File, Tmp_Path);
      Put_Line (F, "{");
      Put_Line (F, "  ""agent_name"": ""TestBot"",");
      Put_Line (F, "  ""system_prompt"": ""You are a test assistant."",");
      Put_Line (F, "  ""providers"": [");
      Put_Line (F, "    { ""kind"": ""openai"", ""api_key"": ""sk-test"", ""model"": ""gpt-4o"" }");
      Put_Line (F, "  ],");
      Put_Line (F, "  ""memory"": { ""max_history"": 25, ""facts_enabled"": false },");
      Put_Line (F, "  ""tools"": { ""file"": true, ""shell"": false }");
      Put_Line (F, "}");
      Close (F);

      R := Load_From (Tmp_Path);
      Assert (R.Success, "Load_From returns Success = True");
      Assert (To_String (R.Config.Agent_Name) = "TestBot",
              "Agent_Name parsed correctly");
      Assert (R.Config.Memory.Max_History = 25,
              "Memory.Max_History = 25 from JSON");
      Assert (not R.Config.Memory.Facts_Enabled,
              "Memory.Facts_Enabled = false from JSON");
      Assert (R.Config.Tools.File_Enabled,
              "Tools.File_Enabled = true from JSON");
      Assert (not R.Config.Tools.Shell_Enabled,
              "Tools.Shell_Enabled = false from JSON");
      Assert (R.Config.Num_Providers >= 1,
              "At least one provider parsed");

      Ada.Directories.Delete_File (Tmp_Path);
   end Test_Load_From_Valid;

   ---------------------------------------------------------
   --  Section 3: Load_From with a missing file
   ---------------------------------------------------------
   procedure Test_Load_From_Missing is
      R : Load_Result;
   begin
      Put_Line ("--- Load_From (missing file) ---");
      R := Load_From ("/nonexistent/path/vericlaw_config_test.json");
      Assert (not R.Success, "Load_From returns Success = False for missing file");
      Assert (Length (R.Error) > 0, "Error string is non-empty");
   end Test_Load_From_Missing;

   ---------------------------------------------------------
   --  Section 4: Load_From with malformed JSON
   ---------------------------------------------------------
   procedure Test_Load_From_Malformed is
      Tmp_Path : constant String :=
        Ada.Directories.Current_Directory & "/test_config_bad.json";
      F : File_Type;
      R : Load_Result;
   begin
      Put_Line ("--- Load_From (malformed JSON) ---");
      Create (F, Out_File, Tmp_Path);
      Put_Line (F, "{ this is not valid json !!!");
      Close (F);

      R := Load_From (Tmp_Path);
      --  Either fails gracefully with Success=False or falls back to defaults
      --  (either outcome is acceptable — must not raise unhandled exception)
      Assert (Length (R.Error) >= 0, "Load_From does not crash on malformed JSON");

      Ada.Directories.Delete_File (Tmp_Path);
   end Test_Load_From_Malformed;

begin
   Put_Line ("=== config_loader_test ===");
   Test_Default_Config;
   Test_Load_From_Valid;
   Test_Load_From_Missing;
   Test_Load_From_Malformed;

   Put_Line ("");
   Put_Line ("Results: " & Natural'Image (Passed) & " passed, "
             & Natural'Image (Failed) & " failed");
   if Failed > 0 then
      raise Program_Error with Natural'Image (Failed) & " test(s) failed";
   end if;
end Config_Loader_Test;
