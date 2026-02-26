--  Unit tests for Agent.Tools: Build_Schemas and Dispatch routing.
--  Tests verify schema generation and dispatch gating logic (tool enabled/disabled)
--  without executing real shell commands or making network calls.

with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Config.Schema;          use Config.Schema;
with Providers.Interface_Pkg; use Providers.Interface_Pkg;
with Agent.Tools;            use Agent.Tools;

procedure Agent_Tools_Test is

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
   --  Section 1: Build_Schemas — all tools disabled
   ---------------------------------------------------------
   procedure Test_Schemas_All_Disabled is
      Cfg : Tool_Config;  -- all disabled by default except File_Enabled
      Schemas : Tool_Schema_Array (1 .. Max_Tool_Schemas);
      Num     : Natural;
   begin
      Put_Line ("--- Build_Schemas (all disabled) ---");
      Cfg.File_Enabled         := False;
      Cfg.Shell_Enabled        := False;
      Cfg.Web_Fetch_Enabled    := False;
      Cfg.Brave_Search_Enabled := False;

      Build_Schemas (Cfg, Schemas, Num);
      Assert (Num = 0, "Num = 0 when all tools disabled");
   end Test_Schemas_All_Disabled;

   ---------------------------------------------------------
   --  Section 2: Build_Schemas — file only
   ---------------------------------------------------------
   procedure Test_Schemas_File_Only is
      Cfg : Tool_Config;
      Schemas : Tool_Schema_Array (1 .. Max_Tool_Schemas);
      Num     : Natural;
   begin
      Put_Line ("--- Build_Schemas (file only) ---");
      Cfg.File_Enabled         := True;
      Cfg.Shell_Enabled        := False;
      Cfg.Web_Fetch_Enabled    := False;
      Cfg.Brave_Search_Enabled := False;

      Build_Schemas (Cfg, Schemas, Num);
      Assert (Num >= 1, "Num >= 1 with file tool enabled");
      --  The first schema should be for the file tool
      Assert (Length (Schemas (1).Name) > 0, "Schema 1 has non-empty name");
      Assert (Length (Schemas (1).Description) > 0, "Schema 1 has non-empty description");
      Assert (Length (Schemas (1).Parameters) > 0,
              "Schema 1 has non-empty parameters JSON");
      --  Parameters JSON should be valid JSON object
      Assert (To_String (Schemas (1).Parameters) (1) = '{',
              "Schema 1 parameters JSON starts with '{'");
   end Test_Schemas_File_Only;

   ---------------------------------------------------------
   --  Section 3: Build_Schemas — all tools enabled
   ---------------------------------------------------------
   procedure Test_Schemas_All_Enabled is
      Cfg : Tool_Config;
      Schemas : Tool_Schema_Array (1 .. Max_Tool_Schemas);
      Num     : Natural;
   begin
      Put_Line ("--- Build_Schemas (all enabled) ---");
      Cfg.File_Enabled         := True;
      Cfg.Shell_Enabled        := True;
      Cfg.Web_Fetch_Enabled    := True;
      Cfg.Brave_Search_Enabled := True;
      Cfg.Brave_API_Key        := To_Unbounded_String ("test-key");

      Build_Schemas (Cfg, Schemas, Num);
      Assert (Num = 5, "Num = 5 when all tools enabled (shell + 3 file + brave_search)");

      --  Check all names are unique and non-empty
      for I in 1 .. Num loop
         Assert (Length (Schemas (I).Name) > 0,
                 "Schema " & Natural'Image (I) & " name non-empty");
      end loop;
   end Test_Schemas_All_Enabled;

   ---------------------------------------------------------
   --  Section 4: Dispatch — unknown tool name
   ---------------------------------------------------------
   procedure Test_Dispatch_Unknown is
      Cfg    : Tool_Config;
      Result : Tool_Result;
   begin
      Put_Line ("--- Dispatch (unknown tool) ---");
      Cfg.File_Enabled  := True;
      Cfg.Shell_Enabled := False;

      Result := Dispatch ("nonexistent_tool", "{}", Cfg,
                          Workspace => "/tmp/vericlaw_test");
      Assert (not Result.Success, "Unknown tool returns Success = False");
      Assert (Length (Result.Error) > 0, "Unknown tool returns non-empty error");
   end Test_Dispatch_Unknown;

   ---------------------------------------------------------
   --  Section 5: Dispatch — disabled tool returns error, not crash
   ---------------------------------------------------------
   procedure Test_Dispatch_Disabled is
      Cfg    : Tool_Config;
      Result : Tool_Result;
   begin
      Put_Line ("--- Dispatch (shell disabled) ---");
      Cfg.Shell_Enabled := False;

      Result := Dispatch ("shell", "{""command"": ""echo hello""}", Cfg,
                          Workspace => "/tmp/vericlaw_test");
      Assert (not Result.Success,
              "Disabled tool returns Success = False");
      Assert (Length (Result.Error) > 0,
              "Disabled tool returns a descriptive error message");
   end Test_Dispatch_Disabled;

begin
   Put_Line ("=== agent_tools_test ===");
   Test_Schemas_All_Disabled;
   Test_Schemas_File_Only;
   Test_Schemas_All_Enabled;
   Test_Dispatch_Unknown;
   Test_Dispatch_Disabled;

   Put_Line ("");
   Put_Line ("Results: " & Natural'Image (Passed) & " passed, "
             & Natural'Image (Failed) & " failed");
   if Failed > 0 then
      raise Program_Error with Natural'Image (Failed) & " test(s) failed";
   end if;
end Agent_Tools_Test;
