with Ada.Environment_Variables;
with Ada.Directories;
with Ada.Text_IO;
with Config.JSON_Parser;    use Config.JSON_Parser;
with Config.Provider_Aliases;
with Terminal.Style;

package body Config.Loader
  with SPARK_Mode => Off
is

   function Home_Dir return String is
      Home : constant String :=
        Ada.Environment_Variables.Value ("HOME", "");
   begin
      return Home;
   end Home_Dir;

   function Default_Config_Path return String is
   begin
      return Home_Dir & "/" & Default_Config_Dir & "/" & Default_Config_File;
   end Default_Config_Path;

   --  Validate that a string field does not contain control characters
   --  or obvious injection patterns.
   function Is_Safe_String (S : String) return Boolean is
   begin
      for C of S loop
         --  Reject control characters (except space and common whitespace).
         if Character'Pos (C) < 32 and then C /= ASCII.LF
           and then C /= ASCII.CR and then C /= ASCII.HT
         then
            return False;
         end if;
      end loop;
      return True;
   end Is_Safe_String;

   --  Validate that a URL string looks reasonable (no control chars, starts
   --  with http:// or https://, bounded length).
   function Is_Safe_URL (S : String) return Boolean is
      Max_URL_Length : constant := 2048;
   begin
      if S'Length = 0 then return True; end if;  -- empty is OK (optional field)
      if S'Length > Max_URL_Length then return False; end if;
      if not Is_Safe_String (S) then return False; end if;
      if S'Length >= 7 and then S (S'First .. S'First + 6) = "http://" then
         return True;
      end if;
      if S'Length >= 8 and then S (S'First .. S'First + 7) = "https://" then
         return True;
      end if;
      return False;
   end Is_Safe_URL;

   procedure Parse_Provider
     (V    : JSON_Value_Type;
      Dest : out Provider_Config)
   is
      Kind_Str : constant String := Get_String (V, "kind", "openai");
   begin
      if Kind_Str = "anthropic" then
         Dest.Kind := Anthropic;
      elsif Kind_Str = "azure_foundry" then
         Dest.Kind := Azure_Foundry;
      elsif Kind_Str = "openai_compatible" then
         Dest.Kind := OpenAI_Compatible;
      elsif Kind_Str = "gemini" then
         Dest.Kind := Gemini;
      else
         Dest.Kind := OpenAI;
      end if;

      Set_Unbounded_String (Dest.API_Key,     Get_String (V, "api_key"));
      Set_Unbounded_String (Dest.Base_URL,    Get_String (V, "base_url"));
      Set_Unbounded_String (Dest.Model,       Get_String (V, "model"));
      Set_Unbounded_String (Dest.Deployment,  Get_String (V, "deployment"));
      Set_Unbounded_String (Dest.API_Version, Get_String (V, "api_version"));

      declare
         MT : constant Integer := Get_Integer (V, "max_tokens", 4096);
         TM : constant Integer := Get_Integer (V, "timeout_ms", 60_000);
      begin
         if MT > 0 then Dest.Max_Tokens := Positive (MT); end if;
         if TM > 0 then Dest.Timeout_Value := Positive (TM); end if;
      end;
   end Parse_Provider;

   procedure Parse_Channel
     (V    : JSON_Value_Type;
      Dest : out Channel_Config)
   is
      Kind_Str : constant String := Get_String (V, "kind", "cli");
   begin
      if Kind_Str = "telegram" then
         Dest.Kind := Telegram;
      elsif Kind_Str = "signal" then
         Dest.Kind := Signal;
      elsif Kind_Str = "whatsapp" then
         Dest.Kind := WhatsApp;
      elsif Kind_Str = "discord" then
         Dest.Kind := Discord;
      elsif Kind_Str = "slack" then
         Dest.Kind := Slack;
      elsif Kind_Str = "email" then
         Dest.Kind := Email;
      elsif Kind_Str = "irc" then
         Dest.Kind := IRC;
      elsif Kind_Str = "matrix" then
         Dest.Kind := Matrix;
      elsif Kind_Str = "mattermost" then
         Dest.Kind := Mattermost;
      else
         Dest.Kind := CLI;
      end if;

      Dest.Enabled := Get_Boolean (V, "enabled", False);
      Set_Unbounded_String (Dest.Token,      Get_String (V, "token"));
      Set_Unbounded_String (Dest.Bridge_URL, Get_String (V, "bridge_url"));
      Set_Unbounded_String (Dest.Allowlist,  Get_String (V, "allowlist"));

      declare
         RPS : constant Integer := Get_Integer (V, "max_rps", 5);
      begin
         if RPS > 0 then Dest.Max_RPS := Positive (RPS); end if;
      end;
   end Parse_Channel;

   function Parse_Config (Source : String) return Load_Result is
      PR     : constant Parse_Result := Parse (Source);
      Result : Load_Result;
   begin
      if not PR.Valid then
         Result.Error := PR.Error;
         return Result;
      end if;

      Result.Config := Default_Config;

      declare
         Root : constant JSON_Value_Type := PR.Root;
      begin
         --  Agent identity
         declare
            N : constant String := Get_String (Root, "agent_name");
            S : constant String := Get_String (Root, "system_prompt");
         begin
            if N'Length > 0 then
               Set_Unbounded_String (Result.Config.Agent_Name, N);
            end if;
            if S'Length > 0 then
               Set_Unbounded_String (Result.Config.System_Prompt, S);
            end if;
         end;

         --  Providers array
         if Has_Key (Root, "providers") then
            declare
               PA_Val : constant JSON_Value_Type := Get_Object (Root, "providers");
               PA     : constant JSON_Array_Type := Value_To_Array (PA_Val);
               Idx    : Provider_Index := 1;
            begin
               for I in 1 .. Array_Length (PA) loop
                  pragma Warnings
                    (Off,
                     "condition can only be True if invalid values present");
                  exit when Idx > Max_Providers;
                  pragma Warnings
                    (On,
                     "condition can only be True if invalid values present");
                  Parse_Provider (Array_Item (PA, I), Result.Config.Providers (Idx));
                  Idx := Idx + 1;
               end loop;
               if Idx > 1 then
                  Result.Config.Num_Providers := Idx - 1;
               end if;
            end;
         end if;

         --  Channels array
         if Has_Key (Root, "channels") then
            declare
               CA_Val : constant JSON_Value_Type := Get_Object (Root, "channels");
               CA     : constant JSON_Array_Type := Value_To_Array (CA_Val);
               Idx    : Channel_Index := 1;
            begin
               for I in 1 .. Array_Length (CA) loop
                  pragma Warnings
                    (Off,
                     "condition can only be True if invalid values present");
                  exit when Idx > Max_Channels;
                  pragma Warnings
                    (On,
                     "condition can only be True if invalid values present");
                  Parse_Channel (Array_Item (CA, I), Result.Config.Channels (Idx));
                  Idx := Idx + 1;
               end loop;
               if Idx > 1 then
                  Result.Config.Num_Channels := Idx - 1;
               end if;
            end;
         end if;

         --  Tools
         if Has_Key (Root, "tools") then
            declare
               T : constant JSON_Value_Type := Get_Object (Root, "tools");
            begin
               Result.Config.Tools.Shell_Enabled :=
                 Get_Boolean (T, "shell", False);
               Result.Config.Tools.File_Enabled :=
                 Get_Boolean (T, "file", True);
               Result.Config.Tools.Web_Fetch_Enabled :=
                 Get_Boolean (T, "web_fetch", False);
               Result.Config.Tools.Git_Enabled :=
                 Get_Boolean (T, "git", True);
               Result.Config.Tools.Brave_Search_Enabled :=
                 Get_Boolean (T, "brave_search", False);
               Set_Unbounded_String
                 (Result.Config.Tools.Brave_API_Key,
                  Get_String (T, "brave_api_key"));
                Set_Unbounded_String
                  (Result.Config.Tools.MCP_Bridge_URL,
                   Get_String (T, "mcp_bridge_url"));
                Set_Unbounded_String
                  (Result.Config.Tools.Plugin_Directory,
                   Get_String (T, "plugin_directory"));
                Set_Unbounded_String
                  (Result.Config.Tools.Browser_Bridge_URL,
                   Get_String (T, "browser_bridge_url"));
               Result.Config.Tools.RAG_Enabled :=
                 Get_Boolean (T, "rag_enabled", False);
               Set_Unbounded_String
                 (Result.Config.Tools.RAG_Embed_Base_URL,
                  Get_String (T, "rag_embed_base_url"));
            end;
         end if;

         --  Memory
         if Has_Key (Root, "memory") then
            declare
               M : constant JSON_Value_Type := Get_Object (Root, "memory");
            begin
               Set_Unbounded_String
                 (Result.Config.Memory.DB_Path, Get_String (M, "db_path"));
                declare
                   MH : constant Integer :=
                     Get_Integer (M, "max_history",
                                  Integer (Default_Max_History));
                begin
                   if Has_Key (M, "max_history") then
                      if MH in Integer (History_Limit'First)
                        .. Integer (History_Limit'Last)
                      then
                         Result.Config.Memory.Max_History :=
                           History_Limit (MH);
                      else
                         Set_Unbounded_String
                           (Result.Error,
                            "Memory max_history must be between"
                            & Integer'Image (Integer (History_Limit'First))
                            & " and"
                            & Integer'Image (Integer (History_Limit'Last)));
                         return Result;
                      end if;
                   end if;
                end;
               Result.Config.Memory.Facts_Enabled :=
                 Get_Boolean (M, "facts_enabled", True);
               declare
                  Rd : constant Integer :=
                    Get_Integer (M, "session_retention_days", 30);
               begin
                  if Rd >= 0 then
                     Result.Config.Memory.Session_Retention_Days := Natural (Rd);
                  end if;
               end;
               declare
                  Cp : constant Integer :=
                    Get_Integer (M, "compact_at_pct", 0);
               begin
                  if Cp in 0 .. 100 then
                     Result.Config.Memory.Compact_At_Pct :=
                       Config.Schema.Compact_Pct (Cp);
                  end if;
               end;
            end;
         end if;

         --  Gateway
         if Has_Key (Root, "gateway") then
            declare
               G : constant JSON_Value_Type := Get_Object (Root, "gateway");
               H : constant String := Get_String (G, "bind_host", "127.0.0.1");
               P : constant Integer := Get_Integer (G, "bind_port", 8787);
            begin
               Set_Unbounded_String (Result.Config.Gateway.Bind_Host, H);
               if P > 0 then
                  Result.Config.Gateway.Bind_Port := Positive (P);
               end if;
               declare
                  MC : constant Integer :=
                    Get_Integer (G, "max_connections", 64);
               begin
                  if MC > 0 then
                     Result.Config.Gateway.Max_Connections := Positive (MC);
                  end if;
               end;
               Set_Unbounded_String
                 (Result.Config.Gateway.TLS_Cert,
                  Get_String (G, "tls_cert"));
               Set_Unbounded_String
                 (Result.Config.Gateway.TLS_Key,
                  Get_String (G, "tls_key"));
            end;
         end if;

         --  Observability
         if Has_Key (Root, "observability") then
            declare
               O : constant JSON_Value_Type :=
                 Get_Object (Root, "observability");
            begin
               Set_Unbounded_String
                 (Result.Config.Observability.OTLP_Endpoint,
                  Get_String (O, "otlp_endpoint"));
            end;
         end if;
      end;

      --  Post-parse validation: reject unsafe values.
      for I in 1 .. Result.Config.Num_Providers loop
         declare
            P : constant Provider_Config := Result.Config.Providers (I);
         begin
            if not Is_Safe_String (To_String (P.Model)) then
               Set_Unbounded_String
                 (Result.Error, "Provider model contains invalid characters");
               return Result;
            end if;
            if Length (P.Base_URL) > 0
              and then not Is_Safe_URL (To_String (P.Base_URL))
            then
               Set_Unbounded_String
                 (Result.Error, "Provider base_url is invalid: "
                  & To_String (P.Base_URL));
               return Result;
            end if;
         end;
      end loop;

      for I in 1 .. Result.Config.Num_Channels loop
         declare
            Ch : constant Channel_Config := Result.Config.Channels (I);
         begin
            if Length (Ch.Bridge_URL) > 0
              and then not Is_Safe_URL (To_String (Ch.Bridge_URL))
            then
               Set_Unbounded_String
                 (Result.Error, "Channel bridge_url is invalid: "
                  & To_String (Ch.Bridge_URL));
               return Result;
            end if;
            if not Is_Safe_String (To_String (Ch.Allowlist)) then
               Set_Unbounded_String
                 (Result.Error, "Channel allowlist contains invalid characters");
               return Result;
            end if;
         end;
      end loop;

      if Length (Result.Config.Gateway.Bind_Host) > 0
        and then not Is_Safe_String
          (To_String (Result.Config.Gateway.Bind_Host))
      then
         Set_Unbounded_String
           (Result.Error, "Gateway bind_host contains invalid characters");
         return Result;
      end if;

       if Length (Result.Config.Observability.OTLP_Endpoint) > 0
         and then not Is_Safe_URL
           (To_String (Result.Config.Observability.OTLP_Endpoint))
       then
         Set_Unbounded_String
           (Result.Error, "Observability otlp_endpoint is invalid");
         return Result;
       end if;

       if Length (Result.Config.Tools.Plugin_Directory) > 0
         and then not Is_Safe_String
           (To_String (Result.Config.Tools.Plugin_Directory))
       then
          Set_Unbounded_String
            (Result.Error, "Tools plugin_directory contains invalid characters");
          return Result;
       end if;

       Result.Success := True;
       return Result;
   end Parse_Config;

   function Load_From (Path : String) return Load_Result is
      Result : Load_Result;
   begin
      if not Ada.Directories.Exists (Path) then
         Set_Unbounded_String (Result.Error, "Config file not found: " & Path);
         return Result;
      end if;

      declare
         File    : Ada.Text_IO.File_Type;
         Content : Unbounded_String;
         Line    : String (1 .. 4096);
         Last    : Natural;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
         while not Ada.Text_IO.End_Of_File (File) loop
            Ada.Text_IO.Get_Line (File, Line, Last);
            Append (Content, Line (1 .. Last));
            Append (Content, ASCII.LF);
         end loop;
         Ada.Text_IO.Close (File);
         return Parse_Config (To_String (Content));
      exception
         when others =>
            if Ada.Text_IO.Is_Open (File) then
               Ada.Text_IO.Close (File);
            end if;
            Set_Unbounded_String
              (Result.Error, "Error reading config: " & Path);
            return Result;
      end;
   end Load_From;

   function Load return Load_Result is
      Env_Path : constant String :=
        Ada.Environment_Variables.Value ("VERICLAW_CONFIG", "");
      Path     : constant String :=
        (if Env_Path'Length > 0 then Env_Path
         else Default_Config_Path);
   begin
      return Load_From (Path);
   end Load;

   procedure Write_Default_Config (Path : String) is
      Dir  : constant String := Ada.Directories.Containing_Directory (Path);
      File : Ada.Text_IO.File_Type;
   begin
      if not Ada.Directories.Exists (Dir) then
         Ada.Directories.Create_Directory (Dir);
      end if;

      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, "{");
      Ada.Text_IO.Put_Line (File, "  ""agent_name"": ""VeriClaw"",");
      Ada.Text_IO.Put_Line (File, "  ""system_prompt"": ""You are VeriClaw, a helpful AI assistant."",");
      Ada.Text_IO.Put_Line (File, "  ""providers"": [");
      Ada.Text_IO.Put_Line (File, "    {");
      Ada.Text_IO.Put_Line (File, "      ""kind"": ""openai"",");
      Ada.Text_IO.Put_Line (File, "      ""api_key"": ""sk-..."",");
      Ada.Text_IO.Put_Line (File, "      ""model"": ""gpt-4o""");
      Ada.Text_IO.Put_Line (File, "    }");
      Ada.Text_IO.Put_Line (File, "  ],");
      Ada.Text_IO.Put_Line (File, "  ""channels"": [");
      Ada.Text_IO.Put_Line (File, "    { ""kind"": ""cli"", ""enabled"": true }");
      Ada.Text_IO.Put_Line (File, "  ],");
      Ada.Text_IO.Put_Line (File, "  ""tools"": {");
      Ada.Text_IO.Put_Line (File, "    ""file"": true,");
      Ada.Text_IO.Put_Line (File, "    ""shell"": false,");
      Ada.Text_IO.Put_Line (File, "    ""web_fetch"": false,");
      Ada.Text_IO.Put_Line (File, "    ""brave_search"": false");
      Ada.Text_IO.Put_Line (File, "  },");
      Ada.Text_IO.Put_Line (File, "  ""memory"": {");
      Ada.Text_IO.Put_Line (File, "    ""max_history"": 50,");
      Ada.Text_IO.Put_Line (File, "    ""facts_enabled"": true,");
      Ada.Text_IO.Put_Line (File, "    ""session_retention_days"": 30");
      Ada.Text_IO.Put_Line (File, "  },");
      Ada.Text_IO.Put_Line (File, "  ""gateway"": {");
      Ada.Text_IO.Put_Line (File, "    ""bind_host"": ""127.0.0.1"",");
      Ada.Text_IO.Put_Line (File, "    ""bind_port"": 8787");
      Ada.Text_IO.Put_Line (File, "  }");
      Ada.Text_IO.Put_Line (File, "}");
      Ada.Text_IO.Close (File);
   end Write_Default_Config;

   procedure Run_Onboard (Path : String) is
      use Ada.Text_IO;

      procedure Prompt (Label : String; Default : String; Result : out String;
                        Last_Out : out Natural) is
         Buf : String (1 .. 256);
         L   : Natural;
      begin
         if Default'Length > 0 then
            Put (Label & " [" & Default & "]: ");
         else
            Put (Label & ": ");
         end if;
         Get_Line (Buf, L);
         if L = 0 and then Default'Length > 0 then
            Result (Result'First .. Result'First + Default'Length - 1) := Default;
            Last_Out := Default'Length;
         else
            Result (Result'First .. Result'First + L - 1) := Buf (1 .. L);
            Last_Out := L;
         end if;
      end Prompt;

      Dir            : constant String :=
        Ada.Directories.Containing_Directory (Path);
      Provider_Buf   : String (1 .. 256);
      API_Key_Buf    : String (1 .. 256);
      Model_Buf      : String (1 .. 256);
      Agent_Name_Buf : String (1 .. 256);
      Channel_Buf    : String (1 .. 256);
      Token_Buf      : String (1 .. 256);
      Bridge_Buf     : String (1 .. 256);
      Extra_Buf      : String (1 .. 256);
      Base_URL_Buf   : String (1 .. 256);
      PL, KL, ML, NL, CL, TL : Natural;
      BL, EL         : Natural;
      UL             : Natural := 0;
      Is_Ollama : Boolean := False;
   begin
      New_Line;
      Put_Line (Terminal.Style.Banner);
      New_Line;
      Put_Line (Terminal.Style.Heading ("Setup Wizard"));
      New_Line;
      Put_Line ("Choose your LLM provider:");
      Put_Line ("  1  openai           (OpenAI GPT-4o, requires API key)");
      Put_Line ("  2  anthropic         (Claude 3.5, requires API key)");
      Put_Line ("  3  ollama            (local LLM, no key needed)");
      Put_Line ("  4  openai_compatible (Azure, Groq, OpenRouter, etc.)");
      Put_Line
        ("  5  gemini            (Google Gemini 2.0 Flash,"
         & " requires API key)");
      New_Line;
      Prompt ("Provider", "openai", Provider_Buf, PL);

      --  Normalise numeric shortcuts to names.
      if PL = 1 and then Provider_Buf (1) = '1' then
         Provider_Buf (1 .. 6) := "openai"; PL := 6;
      elsif PL = 1 and then Provider_Buf (1) = '2' then
         Provider_Buf (1 .. 9) := "anthropic"; PL := 9;
      elsif PL = 1 and then Provider_Buf (1) = '3' then
         Provider_Buf (1 .. 6) := "ollama"; PL := 6;
      elsif PL = 1 and then Provider_Buf (1) = '4' then
         Provider_Buf (1 .. 17) := "openai_compatible"; PL := 17;
      elsif PL = 1 and then Provider_Buf (1) = '5' then
         Provider_Buf (1 .. 6) := "gemini"; PL := 6;
      end if;
      Put_Line ("  " & Terminal.Style.Check & " Provider: " & Provider_Buf (1 .. PL));

      Is_Ollama := PL >= 6 and then Provider_Buf (1 .. 6) = "ollama";

      if Is_Ollama then
         Prompt ("Ollama model", "llama3.2", Model_Buf, ML);
         KL := 0;
      else
         if PL >= 9 and then Provider_Buf (1 .. 9) = "anthropic" then
            Prompt ("Anthropic API key", "", API_Key_Buf, KL);
            Prompt ("Model", "claude-3-5-sonnet-20241022", Model_Buf, ML);
         elsif PL >= 6 and then Provider_Buf (1 .. 6) = "gemini" then
            Prompt ("Gemini API key", "", API_Key_Buf, KL);
            Prompt ("Model", "gemini-2.0-flash", Model_Buf, ML);
         elsif PL >= 17
           and then Provider_Buf (1 .. 17) = "openai_compatible"
         then
            New_Line;
            Put_Line ("  Popular OpenAI-compatible providers:");
            Put_Line ("    1  "
              & Terminal.Style.Cmd ("groq") & "        "
              & Terminal.Style.Muted
                  ("(Groq Cloud — fast inference)"));
            Put_Line ("    2  "
              & Terminal.Style.Cmd ("mistral") & "     "
              & Terminal.Style.Muted ("(Mistral AI)"));
            Put_Line ("    3  "
              & Terminal.Style.Cmd ("deepseek") & "    "
              & Terminal.Style.Muted ("(DeepSeek)"));
            Put_Line ("    4  "
              & Terminal.Style.Cmd ("xai") & "         "
              & Terminal.Style.Muted ("(xAI / Grok)"));
            Put_Line ("    5  "
              & Terminal.Style.Cmd ("openrouter") & "  "
              & Terminal.Style.Muted
                  ("(OpenRouter — multi-model gateway)"));
            Put_Line ("    6  "
              & Terminal.Style.Cmd ("perplexity") & "  "
              & Terminal.Style.Muted ("(Perplexity AI)"));
            Put_Line ("    7  "
              & Terminal.Style.Cmd ("together") & "    "
              & Terminal.Style.Muted ("(Together AI)"));
            Put_Line ("    8  "
              & Terminal.Style.Cmd ("fireworks") & "   "
              & Terminal.Style.Muted ("(Fireworks AI)"));
            Put_Line ("    9  "
              & Terminal.Style.Cmd ("cerebras") & "    "
              & Terminal.Style.Muted ("(Cerebras)"));
            Put_Line ("    0  "
              & Terminal.Style.Cmd ("custom") & "      "
              & Terminal.Style.Muted ("(Enter URL manually)"));
            New_Line;
            Prompt ("Choice", "1", Extra_Buf, EL);

            if EL = 1
              and then Extra_Buf (1) in '1' .. '9'
            then
               declare
                  use Config.Provider_Aliases;
                  Idx   : constant Alias_Index :=
                    Alias_Index
                      (Character'Pos (Extra_Buf (1))
                       - Character'Pos ('0'));
                  A     : constant Alias_Info := Get_Alias (Idx);
                  Info  : Alias_Info;
                  Found : Boolean;
               begin
                  Lookup
                    (A.Name (1 .. A.Name_Length),
                     Info, Found);
                  if Found then
                     Base_URL_Buf (1 .. Info.URL_Length) :=
                       Info.Base_URL (1 .. Info.URL_Length);
                     UL := Info.URL_Length;
                     Model_Buf (1 .. Info.Model_Length) :=
                       Info.Default_Model
                         (1 .. Info.Model_Length);
                     ML := Info.Model_Length;
                     if Info.Needs_Key then
                        Prompt ("API key", "",
                                API_Key_Buf, KL);
                     else
                        KL := 0;
                     end if;
                     Put_Line
                       ("  " & Terminal.Style.Check
                        & " Provider: "
                        & Info.Name
                            (1 .. Info.Name_Length)
                        & " ("
                        & Info.Base_URL
                            (1 .. Info.URL_Length)
                        & ")");
                  else
                     Prompt ("API key (or leave blank)",
                             "", API_Key_Buf, KL);
                     Prompt ("Base URL",
                             "http://localhost:8080",
                             Base_URL_Buf, UL);
                     Prompt ("Model", "default",
                             Model_Buf, ML);
                  end if;
               end;
            else
               Prompt ("API key (or leave blank)", "",
                       API_Key_Buf, KL);
               Prompt ("Base URL",
                       "http://localhost:8080",
                       Base_URL_Buf, UL);
               Prompt ("Model", "default",
                       Model_Buf, ML);
            end if;
         else
            Prompt ("OpenAI API key", "", API_Key_Buf, KL);
            Prompt ("Model", "gpt-4o", Model_Buf, ML);
         end if;
      end if;

      New_Line;
      Prompt ("Agent name", "VeriClaw", Agent_Name_Buf, NL);

      New_Line;
      Put_Line ("Choose your primary channel:");
      Put_Line ("  1  cli       (interactive terminal — default)");
      Put_Line ("  2  telegram  (Telegram bot, requires bot token)");
      Put_Line ("  3  signal    (Signal via signal-cli bridge)");
      Put_Line ("  4  whatsapp  (WhatsApp via wa-bridge)");
      Put_Line ("  5  discord   (Discord bot, requires bot token)");
      Put_Line ("  6  slack     (Slack app, requires bot + app tokens)");
      Put_Line ("  7  email     (Email via IMAP/SMTP bridge)");
      Put_Line ("  8  irc       (IRC via irc-bridge)");
      Put_Line ("  9  matrix    (Matrix via matrix-bridge)");
      Put_Line ("  10 mattermost (Mattermost via mattermost-bridge)");
      New_Line;
      Prompt ("Channel", "cli", Channel_Buf, CL);

      if CL = 1 and then Channel_Buf (1) in '1' .. '9' then
         case Channel_Buf (1) is
            when '1' => Channel_Buf (1 .. 3) := "cli"; CL := 3;
            when '2' => Channel_Buf (1 .. 8) := "telegram"; CL := 8;
            when '3' => Channel_Buf (1 .. 6) := "signal"; CL := 6;
            when '4' => Channel_Buf (1 .. 8) := "whatsapp"; CL := 8;
            when '5' => Channel_Buf (1 .. 7) := "discord"; CL := 7;
            when '6' => Channel_Buf (1 .. 5) := "slack"; CL := 5;
            when '7' => Channel_Buf (1 .. 5) := "email"; CL := 5;
            when '8' => Channel_Buf (1 .. 3) := "irc"; CL := 3;
            when '9' => Channel_Buf (1 .. 6) := "matrix"; CL := 6;
            when others => null;
         end case;
      elsif CL = 2
        and then Channel_Buf (1) = '1'
        and then Channel_Buf (2) = '0'
      then
         Channel_Buf (1 .. 10) := "mattermost"; CL := 10;
      end if;
      Put_Line ("  " & Terminal.Style.Check & " Channel: " & Channel_Buf (1 .. CL));

      TL := 0;
      BL := 0;
      if CL >= 8 and then Channel_Buf (1 .. 8) = "telegram" then
         Prompt ("Telegram bot token", "", Token_Buf, TL);
      elsif CL >= 8 and then Channel_Buf (1 .. 8) = "whatsapp" then
         Prompt ("Bridge URL", "http://localhost:3000", Bridge_Buf, BL);
      elsif CL >= 6 and then Channel_Buf (1 .. 6) = "signal" then
         Prompt ("Signal bridge URL", "http://localhost:8080",
           Bridge_Buf, BL);
      elsif CL >= 7 and then Channel_Buf (1 .. 7) = "discord" then
         Prompt ("Discord bot token", "", Token_Buf, TL);
      elsif CL >= 5 and then Channel_Buf (1 .. 5) = "slack" then
         Prompt ("Slack bot token", "", Token_Buf, TL);
         Prompt ("Slack app token", "", Bridge_Buf, BL);
      elsif CL >= 5 and then Channel_Buf (1 .. 5) = "email" then
         Prompt ("IMAP host", "", Extra_Buf, EL);
         Prompt ("SMTP host", "", Bridge_Buf, BL);
         Prompt ("Email user", "", Token_Buf, TL);
         --  Combine IMAP/SMTP hosts into a single bridge_url value.
         if EL > 0 and BL > 0 then
            declare
               Combined : constant String :=
                 "imap://" & Extra_Buf (1 .. EL)
                 & ";smtp://" & Bridge_Buf (1 .. BL);
            begin
               Bridge_Buf (1 .. Combined'Length) := Combined;
               BL := Combined'Length;
            end;
         end if;
      elsif CL >= 3 and then Channel_Buf (1 .. 3) = "irc" then
         Prompt ("IRC server", "", Extra_Buf, EL);
         Prompt ("Nick", "", Token_Buf, TL);
         Prompt ("Channel", "#general", Bridge_Buf, BL);
         --  Combine server and channel into bridge_url.
         if EL > 0 then
            declare
               URL : constant String :=
                 "irc://" & Extra_Buf (1 .. EL)
                 & "/" & Bridge_Buf (1 .. BL);
            begin
               Bridge_Buf (1 .. URL'Length) := URL;
               BL := URL'Length;
            end;
         end if;
      elsif CL >= 6 and then Channel_Buf (1 .. 6) = "matrix" then
         Prompt ("Homeserver URL", "https://matrix.org",
           Bridge_Buf, BL);
         Prompt ("Access token", "", Token_Buf, TL);
      elsif CL >= 10
        and then Channel_Buf (1 .. 10) = "mattermost"
      then
         Prompt ("Bridge URL", "http://localhost:3008",
           Bridge_Buf, BL);
         Prompt ("Bot token", "", Token_Buf, TL);
      end if;

      --  Create directory if needed.
      if not Ada.Directories.Exists (Dir) then
         Ada.Directories.Create_Directory (Dir);
      end if;

      --  Write config.
      declare
         File : Ada.Text_IO.File_Type;
         function Q (S : String; L : Natural) return String is
           ("""" & S (S'First .. S'First + L - 1) & """");
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
         Put_Line (File, "{");
         Put_Line (File, "  ""agent_name"": " & Q (Agent_Name_Buf, NL) & ",");
         Put_Line (File, "  ""system_prompt"": ""You are "
           & Agent_Name_Buf (1 .. NL) & ", a helpful AI assistant."",");
         Put_Line (File, "  ""providers"": [");
         Put_Line (File, "    {");
         if Is_Ollama then
            Put_Line (File, "      ""kind"": ""openai_compatible"",");
            Put_Line (File, "      ""base_url"": ""http://localhost:11434"",");
            Put_Line (File, "      ""api_key"": """",");
            Put_Line (File, "      ""model"": " & Q (Model_Buf, ML));
         elsif PL >= 17 and then
           Provider_Buf (1 .. 17) = "openai_compatible"
         then
            Put_Line (File, "      ""kind"": ""openai_compatible"",");
            if UL > 0 then
               Put_Line (File, "      ""base_url"": "
                 & Q (Base_URL_Buf, UL) & ",");
            end if;
            if KL > 0 then
               Put_Line (File, "      ""api_key"": "
                 & Q (API_Key_Buf, KL) & ",");
            end if;
            Put_Line (File, "      ""model"": "
              & Q (Model_Buf, ML));
         else
            Put_Line (File, "      ""kind"": """ & Provider_Buf (1 .. PL) & """,");
            Put_Line (File, "      ""api_key"": " & Q (API_Key_Buf, KL) & ",");
            Put_Line (File, "      ""model"": " & Q (Model_Buf, ML));
         end if;
         Put_Line (File, "    }");
         Put_Line (File, "  ],");
         Put_Line (File, "  ""channels"": [");
         Put_Line (File, "    {");
         Put_Line (File, "      ""kind"": """ & Channel_Buf (1 .. CL) & """,");
         declare
            Has_Fields : constant Boolean := TL > 0 or BL > 0;
         begin
            Put_Line (File, "      ""enabled"": true"
              & (if Has_Fields then "," else ""));
            if TL > 0 then
               Put_Line (File, "      ""token"": " & Q (Token_Buf, TL)
                 & (if BL > 0 then "," else ""));
            end if;
            if BL > 0 then
               Put_Line (File, "      ""bridge_url"": "
                 & Q (Bridge_Buf, BL));
            end if;
         end;
         Put_Line (File, "    }");
         Put_Line (File, "  ],");
         Put_Line (File, "  ""tools"": {");
         Put_Line (File, "    ""file"": true,");
         Put_Line (File, "    ""shell"": false,");
         Put_Line (File, "    ""web_fetch"": false,");
         Put_Line (File, "    ""brave_search"": false");
         Put_Line (File, "  },");
         Put_Line (File, "  ""memory"": {");
         Put_Line (File, "    ""max_history"": 50,");
         Put_Line (File, "    ""facts_enabled"": true,");
         Put_Line (File, "    ""session_retention_days"": 30");
         Put_Line (File, "  },");
         Put_Line (File, "  ""gateway"": {");
         Put_Line (File, "    ""bind_host"": ""127.0.0.1"",");
         Put_Line (File, "    ""bind_port"": 8787");
         Put_Line (File, "  }");
         Put_Line (File, "}");
         Ada.Text_IO.Close (File);
      end;


      New_Line;
      Put_Line (Terminal.Style.Check & " Config written to " & Terminal.Style.Brand (Path));
      New_Line;
      Put_Line (Terminal.Style.Heading ("Next steps:"));
      Put_Line ("  1. " & Terminal.Style.Cmd ("vericlaw doctor") & "   — verify your setup");
      Put_Line ("  2. " & Terminal.Style.Cmd ("vericlaw chat") & "     — start chatting");
      Put_Line ("  3. " & Terminal.Style.Cmd ("vericlaw gateway") & "  — run multi-channel daemon");
      New_Line;
   end Run_Onboard;

   -----------------------------------------------------------------------
   --  Run_Config_Edit — interactive editor for an existing config
   -----------------------------------------------------------------------

   procedure Run_Config_Edit
     (Path : String;
      Cfg  : Config.Schema.Agent_Config)
   is
      use Ada.Text_IO;

      procedure Prompt
        (Label    : String;
         Default  : String;
         Result   : out String;
         Last_Out : out Natural)
      is
         Buf : String (1 .. 256);
         L   : Natural;
      begin
         if Default'Length > 0 then
            Put (Label & " [" & Default & "]: ");
         else
            Put (Label & ": ");
         end if;
         Get_Line (Buf, L);
         if L = 0 and then Default'Length > 0 then
            Result (Result'First ..
              Result'First + Default'Length - 1) := Default;
            Last_Out := Default'Length;
         else
            Result (Result'First ..
              Result'First + L - 1) := Buf (1 .. L);
            Last_Out := L;
         end if;
      end Prompt;

      P            : Provider_Config renames Cfg.Providers (1);
      Ch           : Channel_Config  renames Cfg.Channels (1);
      Kind_Img     : constant String :=
        Provider_Kind'Image (P.Kind);
      Model_Str    : constant String :=
        To_String (P.Model);
      Key_Str      : constant String :=
        To_String (P.API_Key);
      Chan_Img     : constant String :=
        Channel_Kind'Image (Ch.Kind);
      Agent_Str    : constant String :=
        To_String (Cfg.Agent_Name);

      --  Mutable copies used while editing.
      Provider_Buf   : String (1 .. 256);
      PL             : Natural := Kind_Img'Length;
      API_Key_Buf    : String (1 .. 256);
      KL             : Natural := Key_Str'Length;
      Model_Buf      : String (1 .. 256);
      ML             : Natural := Model_Str'Length;
      Agent_Name_Buf : String (1 .. 256);
      NL             : Natural := Agent_Str'Length;
      Channel_Buf    : String (1 .. 256);
      CL             : Natural := Chan_Img'Length;
      Base_URL_Buf   : String (1 .. 256);
      UL             : Natural := 0;

      --  Placeholders for channel credentials
      Token_Buf      : String (1 .. 256);
      TL             : Natural := 0;
      Bridge_Buf     : String (1 .. 256);
      BL             : Natural := 0;

      Choice_Buf     : String (1 .. 256);
      Choice_Len     : Natural;
      Done           : Boolean := False;

      Is_Ollama      : Boolean := False;

      function Lower (S : String) return String is
         R : String := S;
      begin
         for I in R'Range loop
            if R (I) in 'A' .. 'Z' then
               R (I) :=
                 Character'Val
                   (Character'Pos (R (I)) + 32);
            end if;
         end loop;
         return R;
      end Lower;

      Dir : constant String :=
        Ada.Directories.Containing_Directory (Path);

      Tok_Str : constant String :=
        To_String (Ch.Token);
      Br_Str  : constant String :=
        To_String (Ch.Bridge_URL);
      BU_Str  : constant String :=
        To_String (P.Base_URL);
   begin
      --  Seed mutable buffers from the loaded config.
      Provider_Buf (1 .. PL) := Lower (Kind_Img);
      API_Key_Buf  (1 .. KL) := Key_Str;
      Model_Buf    (1 .. ML) := Model_Str;
      Agent_Name_Buf (1 .. NL) := Agent_Str;
      Channel_Buf  (1 .. CL) := Lower (Chan_Img);
      if BU_Str'Length > 0 then
         Base_URL_Buf (1 .. BU_Str'Length) := BU_Str;
         UL := BU_Str'Length;
      end if;
      if Tok_Str'Length > 0 then
         Token_Buf (1 .. Tok_Str'Length) := Tok_Str;
         TL := Tok_Str'Length;
      end if;
      if Br_Str'Length > 0 then
         Bridge_Buf (1 .. Br_Str'Length) := Br_Str;
         BL := Br_Str'Length;
      end if;

      Is_Ollama := PL >= 6
        and then Provider_Buf (1 .. 6) = "ollama";

      New_Line;
      Put_Line
        (Terminal.Style.Heading ("Current configuration:"));
      Put_Line ("  provider : "
        & Provider_Buf (1 .. PL)
        & " (" & Model_Buf (1 .. ML) & ")");
      Put_Line ("  channels : "
        & Channel_Index'Image (Cfg.Num_Channels)
        & " (" & Channel_Buf (1 .. CL) & ")");
      Put_Line ("  agent    : "
        & Agent_Name_Buf (1 .. NL));
      New_Line;

      while not Done loop
         Put_Line
           (Terminal.Style.Heading
              ("What would you like to change?"));
         Put_Line ("  1  provider"
           & "    Change LLM provider or model");
         Put_Line ("  2  api-key"
           & "     Update API key");
         Put_Line ("  3  model"
           & "       Change model");
         Put_Line ("  4  channels"
           & "    Add or change channels");
         Put_Line ("  5  agent-name"
           & "  Change agent name");
         Put_Line ("  6  done"
           & "        Save and exit");
         New_Line;

         Prompt ("Choice", "6", Choice_Buf, Choice_Len);

         if Choice_Len = 1 and then Choice_Buf (1) = '1' then
            Prompt ("Provider", Provider_Buf (1 .. PL),
              Provider_Buf, PL);
            Is_Ollama := PL >= 6
              and then Provider_Buf (1 .. 6) = "ollama";
            Put_Line ("  " & Terminal.Style.Check
              & " Provider: " & Provider_Buf (1 .. PL));

         elsif Choice_Len = 1
           and then Choice_Buf (1) = '2'
         then
            Prompt ("API key", "", API_Key_Buf, KL);
            Put_Line ("  " & Terminal.Style.Check
              & " API key updated");

         elsif Choice_Len = 1
           and then Choice_Buf (1) = '3'
         then
            Prompt ("Model", Model_Buf (1 .. ML),
              Model_Buf, ML);
            Put_Line ("  " & Terminal.Style.Check
              & " Model: " & Model_Buf (1 .. ML));

         elsif Choice_Len = 1
           and then Choice_Buf (1) = '4'
         then
            Prompt ("Channel", Channel_Buf (1 .. CL),
              Channel_Buf, CL);
            Put_Line ("  " & Terminal.Style.Check
              & " Channel: " & Channel_Buf (1 .. CL));

         elsif Choice_Len = 1
           and then Choice_Buf (1) = '5'
         then
            Prompt ("Agent name",
              Agent_Name_Buf (1 .. NL),
              Agent_Name_Buf, NL);
            Put_Line ("  " & Terminal.Style.Check
              & " Agent: "
              & Agent_Name_Buf (1 .. NL));

         elsif Choice_Len = 1
           and then Choice_Buf (1) = '6'
         then
            Done := True;

         elsif Choice_Len >= 4
           and then Choice_Buf (1 .. 4) = "done"
         then
            Done := True;

         else
            Put_Line
              (Terminal.Style.Warn ("Invalid choice"));
         end if;

         New_Line;
      end loop;

      --  Create directory if needed.
      if not Ada.Directories.Exists (Dir) then
         Ada.Directories.Create_Directory (Dir);
      end if;

      --  Write config (same format as Run_Onboard).
      declare
         File : Ada.Text_IO.File_Type;
         function Q (S : String; L : Natural)
           return String
         is ("""" & S (S'First .. S'First + L - 1)
             & """");
      begin
         Ada.Text_IO.Create
           (File, Ada.Text_IO.Out_File, Path);
         Put_Line (File, "{");
         Put_Line (File,
           "  ""agent_name"": "
           & Q (Agent_Name_Buf, NL) & ",");
         Put_Line (File,
           "  ""system_prompt"": ""You are "
           & Agent_Name_Buf (1 .. NL)
           & ", a helpful AI assistant."",");
         Put_Line (File, "  ""providers"": [");
         Put_Line (File, "    {");
         if Is_Ollama then
            Put_Line (File,
              "      ""kind"": ""openai_compatible"",");
            Put_Line (File,
              "      ""base_url"":"
              & " ""http://localhost:11434"",");
            Put_Line (File,
              "      ""api_key"": """",");
            Put_Line (File,
              "      ""model"": "
              & Q (Model_Buf, ML));
         elsif PL >= 17
           and then Provider_Buf (1 .. 17)
                    = "openai_compatible"
         then
            Put_Line (File,
              "      ""kind"":"
              & " ""openai_compatible"",");
            if UL > 0 then
               Put_Line (File,
                 "      ""base_url"": "
                 & Q (Base_URL_Buf, UL) & ",");
            end if;
            if KL > 0 then
               Put_Line (File,
                 "      ""api_key"": "
                 & Q (API_Key_Buf, KL) & ",");
            end if;
            Put_Line (File,
              "      ""model"": "
              & Q (Model_Buf, ML));
         else
            Put_Line (File,
              "      ""kind"": """
              & Provider_Buf (1 .. PL) & """,");
            Put_Line (File,
              "      ""api_key"": "
              & Q (API_Key_Buf, KL) & ",");
            Put_Line (File,
              "      ""model"": "
              & Q (Model_Buf, ML));
         end if;
         Put_Line (File, "    }");
         Put_Line (File, "  ],");
         Put_Line (File, "  ""channels"": [");
         Put_Line (File, "    {");
         Put_Line (File,
           "      ""kind"": """
           & Channel_Buf (1 .. CL) & """,");
         declare
            Has_Fields : constant Boolean :=
              TL > 0 or BL > 0;
         begin
            Put_Line (File,
              "      ""enabled"": true"
              & (if Has_Fields then "," else ""));
            if TL > 0 then
               Put_Line (File,
                 "      ""token"": "
                 & Q (Token_Buf, TL)
                 & (if BL > 0 then "," else ""));
            end if;
            if BL > 0 then
               Put_Line (File,
                 "      ""bridge_url"": "
                 & Q (Bridge_Buf, BL));
            end if;
         end;
         Put_Line (File, "    }");
         Put_Line (File, "  ],");
         Put_Line (File, "  ""tools"": {");
         Put_Line (File, "    ""file"": true,");
         Put_Line (File,
           "    ""shell"": false,");
         Put_Line (File,
           "    ""web_fetch"": false,");
         Put_Line (File,
           "    ""brave_search"": false");
         Put_Line (File, "  },");
         Put_Line (File, "  ""memory"": {");
         Put_Line (File,
           "    ""max_history"": 50,");
         Put_Line (File,
           "    ""facts_enabled"": true,");
         Put_Line (File,
           "    ""session_retention_days"": 30");
         Put_Line (File, "  },");
         Put_Line (File, "  ""gateway"": {");
         Put_Line (File,
           "    ""bind_host"":"
           & " ""127.0.0.1"",");
         Put_Line (File,
           "    ""bind_port"": 8787");
         Put_Line (File, "  }");
         Put_Line (File, "}");
         Ada.Text_IO.Close (File);
      end;

      New_Line;
      Put_Line (Terminal.Style.Check
        & " Config updated at "
        & Terminal.Style.Brand (Path));
      New_Line;
   end Run_Config_Edit;

end Config.Loader;
