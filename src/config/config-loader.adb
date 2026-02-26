with Ada.Environment_Variables;
with Ada.Directories;
with Ada.Text_IO;
with Config.JSON_Parser;    use Config.JSON_Parser;

package body Config.Loader is

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
         if TM > 0 then Dest.Timeout_Ms := Positive (TM); end if;
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
                  exit when Idx > Max_Providers;
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
                  exit when Idx > Max_Channels;
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
               Result.Config.Tools.Brave_Search_Enabled :=
                 Get_Boolean (T, "brave_search", False);
               Set_Unbounded_String
                 (Result.Config.Tools.Brave_API_Key,
                  Get_String (T, "brave_api_key"));
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
                  MH : constant Integer := Get_Integer (M, "max_history", 50);
               begin
                  if MH > 0 then
                     Result.Config.Memory.Max_History := Positive (MH);
                  end if;
               end;
               Result.Config.Memory.Facts_Enabled :=
                 Get_Boolean (M, "facts_enabled", True);
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
               Set_Unbounded_String
                 (Result.Config.Gateway.TLS_Cert,
                  Get_String (G, "tls_cert"));
               Set_Unbounded_String
                 (Result.Config.Gateway.TLS_Key,
                  Get_String (G, "tls_key"));
            end;
         end if;
      end;

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
         when E : others =>
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
        Ada.Environment_Variables.Value ("QUASAR_CONFIG", "");
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
      Ada.Text_IO.Put_Line (File, "  ""agent_name"": ""Quasar"",");
      Ada.Text_IO.Put_Line (File, "  ""system_prompt"": ""You are Quasar, a helpful AI assistant."",");
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
      Ada.Text_IO.Put_Line (File, "    ""facts_enabled"": true");
      Ada.Text_IO.Put_Line (File, "  },");
      Ada.Text_IO.Put_Line (File, "  ""gateway"": {");
      Ada.Text_IO.Put_Line (File, "    ""bind_host"": ""127.0.0.1"",");
      Ada.Text_IO.Put_Line (File, "    ""bind_port"": 8787");
      Ada.Text_IO.Put_Line (File, "  }");
      Ada.Text_IO.Put_Line (File, "}");
      Ada.Text_IO.Close (File);
   end Write_Default_Config;

end Config.Loader;
