with HTTP.Client;
with Config.JSON_Parser; use Config.JSON_Parser;
with Agent.Context;      use Agent.Context;
with Ada.Text_IO;
with Logging;

package body Providers.OpenAI_Compatible
  with SPARK_Mode => Off
is

   --  -----------------------------------------------------------------------
   --  Streaming accumulation state (package-level; CLI-only, non-concurrent).
   --  -----------------------------------------------------------------------
   Compat_Accumulated  : Unbounded_String;
   Compat_Stop_Reason  : Unbounded_String;

   procedure Compat_SSE_Parse (Line : String);

   procedure Compat_SSE_Parse (Line : String) is
      Prefix : constant String := "data: ";
   begin
      if Line'Length > Prefix'Length
        and then Line (Line'First .. Line'First + Prefix'Length - 1) = Prefix
      then
         declare
            Payload : constant String :=
              Line (Line'First + Prefix'Length .. Line'Last);
         begin
            if Payload = "[DONE]" then return; end if;
            declare
               PR : constant Parse_Result := Parse (Payload);
            begin
               if PR.Valid and then Has_Key (PR.Root, "choices") then
                  declare
                     Choices     : constant JSON_Value_Type :=
                       Get_Object (PR.Root, "choices");
                     Choices_Arr : constant JSON_Array_Type :=
                       Value_To_Array (Choices);
                  begin
                     if Array_Length (Choices_Arr) > 0 then
                        declare
                           First : constant JSON_Value_Type :=
                             Array_Item (Choices_Arr, 1);
                        begin
                           if Has_Key (First, "delta") then
                              declare
                                 Delta_Obj : constant JSON_Value_Type :=
                                   Get_Object (First, "delta");
                                 Content   : constant String :=
                                   Get_String (Delta_Obj, "content");
                              begin
                                 if Content'Length > 0 then
                                    Ada.Text_IO.Put (Content);
                                    Append (Compat_Accumulated, Content);
                                 end if;
                              end;
                           end if;
                           declare
                              FR : constant String :=
                                Get_String (First, "finish_reason");
                           begin
                              if FR'Length > 0 then
                                 Set_Unbounded_String
                                   (Compat_Stop_Reason, FR);
                              end if;
                           end;
                        end;
                     end if;
                  end;
               end if;
            end;
         end;
      end if;
   exception
      when others =>
         Logging.Debug ("Malformed SSE chunk discarded");
   end Compat_SSE_Parse;

   function Create (Cfg : Provider_Config) return OpenAI_Compat_Provider is
      P : OpenAI_Compat_Provider;
   begin
      P.API_Key     := Cfg.API_Key;
      P.Base_URL    := Cfg.Base_URL;
      P.Model       := Cfg.Model;
      P.Deployment  := Cfg.Deployment;
      P.API_Version := Cfg.API_Version;
      P.Max_Tokens  := Cfg.Max_Tokens;
      P.Timeout_Ms  := Cfg.Timeout_Value;
      P.Is_Azure    := (Cfg.Kind = Azure_Foundry);

      if Length (P.Model) = 0 and then not P.Is_Azure then
         Set_Unbounded_String (P.Model, "gpt-4o");
      end if;
      return P;
   end Create;

   function Name (Provider : OpenAI_Compat_Provider) return String is
     ((if Provider.Is_Azure then "azure:" else "compat:")
      & (if Length (Provider.Deployment) > 0
         then To_String (Provider.Deployment)
         else To_String (Provider.Model)));

   function Build_Endpoint (Provider : OpenAI_Compat_Provider) return String is
   begin
      if Provider.Is_Azure then
         --  Azure AI Foundry format:
         --  {base_url}/openai/deployments/{deployment}/chat/completions
         --    ?api-version={api_version}
         return To_String (Provider.Base_URL)
           & "/openai/deployments/"
           & To_String (Provider.Deployment)
           & "/chat/completions?api-version="
           & To_String (Provider.API_Version);
      else
         return To_String (Provider.Base_URL) & "/v1/chat/completions";
      end if;
   end Build_Endpoint;

   function Build_Request_Body
     (Provider  : OpenAI_Compat_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return String
   is
      Root     : JSON_Value_Type := Build_Object;
      Msgs     : JSON_Value_Type := Build_Array;
      Msgs_Raw : constant Agent.Context.Message_Array :=
        Agent.Context.Format_For_Provider (Conv);
   begin
      --  Azure uses deployment name instead of model field in some cases,
      --  but the model field is still accepted and harmless to include.
      Set_Field (Root, "model",
        (if Length (Provider.Deployment) > 0
         then To_String (Provider.Deployment)
         else To_String (Provider.Model)));
      Set_Field (Root, "max_tokens", Provider.Max_Tokens);

      for I in Msgs_Raw'Range loop
         declare
            M    : JSON_Value_Type := Build_Object;
            Role : constant String :=
              (case Msgs_Raw (I).Role is
               when Agent.Context.System_Role  => "system",
               when Agent.Context.User         => "user",
               when Agent.Context.Assistant    => "assistant",
               when Agent.Context.Tool_Result  => "tool");
         begin
            Set_Field (M, "role",    Role);
            Set_Field (M, "content", To_String (Msgs_Raw (I).Content));
            if Msgs_Raw (I).Role = Agent.Context.Tool_Result then
               Set_Field (M, "tool_call_id",
                 To_String (Msgs_Raw (I).Name));
            end if;
            Append_Array (Msgs, M);
         end;
      end loop;
      Set_Field (Root, "messages", Msgs);

      if Num_Tools > 0 then
         declare
            Tools_JSON : JSON_Value_Type := Build_Array;
         begin
            for I in 1 .. Num_Tools loop
               declare
                  Tool_Obj : JSON_Value_Type := Build_Object;
                  Fn_Obj   : JSON_Value_Type := Build_Object;
                  Params   : Parse_Result;
               begin
                  Set_Field (Tool_Obj, "type", "function");
                  Set_Field (Fn_Obj, "name",
                    To_String (Tools (I).Name));
                  Set_Field (Fn_Obj, "description",
                    To_String (Tools (I).Description));
                  Params := Parse (To_String (Tools (I).Parameters));
                  if Params.Valid then
                     Set_Field (Fn_Obj, "parameters", Params.Root);
                  end if;
                  Set_Field (Tool_Obj, "function", Fn_Obj);
                  Append_Array (Tools_JSON, Tool_Obj);
               end;
            end loop;
            Set_Field (Root, "tools", Tools_JSON);
            Set_Field (Root, "tool_choice", "auto");
         end;
      end if;

      return To_JSON_String (Root);
   end Build_Request_Body;

   function Chat
     (Provider  : in out OpenAI_Compat_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response
   is
      URL      : constant String := Build_Endpoint (Provider);
      Auth_Val : constant String :=
        (if Provider.Is_Azure
         then To_String (Provider.API_Key)  -- Azure uses api-key header
         else "Bearer " & To_String (Provider.API_Key));
      Auth_Hdr_Name : constant String :=
        (if Provider.Is_Azure then "api-key" else "Authorization");
      Hdrs     : constant HTTP.Client.Header_Array :=
        [1 => (Name  => To_Unbounded_String (Auth_Hdr_Name),
               Value => To_Unbounded_String (Auth_Val))];
      Body_Str  : constant String :=
        Build_Request_Body (Provider, Conv, Tools, Num_Tools);
      Http_Resp : constant HTTP.Client.Response :=
        HTTP.Client.Post_JSON
          (URL        => URL,
           Headers    => Hdrs,
           Body_JSON  => Body_Str,
           Timeout_Ms => Provider.Timeout_Ms);

      Result : Provider_Response;
   begin
      if not HTTP.Client.Is_Success (Http_Resp) then
         Set_Unbounded_String
           (Result.Error,
            "HTTP " & Http_Resp.Status_Code'Image & ": "
            & To_String (Http_Resp.Error));
         return Result;
      end if;

      declare
         PR : constant Parse_Result :=
           Parse (To_String (Http_Resp.Body_Text));
      begin
         if not PR.Valid then
            Set_Unbounded_String (Result.Error, "Invalid JSON response");
            return Result;
         end if;

         if Has_Key (PR.Root, "choices") then
            declare
               Choices : constant JSON_Value_Type :=
                 Get_Object (PR.Root, "choices");
               Choices_Arr : constant JSON_Array_Type := Value_To_Array (Choices);
               First       : constant JSON_Value_Type := Array_Item (Choices_Arr, 1);
               Msg     : constant JSON_Value_Type :=
                 Get_Object (First, "message");
            begin
               Set_Unbounded_String
                 (Result.Content, Get_String (Msg, "content"));
               Set_Unbounded_String
                 (Result.Stop_Reason,
                  Get_String (First, "finish_reason"));
               --  Parse tool_calls
               if Has_Key (Msg, "tool_calls") then
                  declare
                     TC_Array : constant JSON_Value_Type :=
                       Get_Object (Msg, "tool_calls");
                  begin
                     declare
                        TC_Arr : constant JSON_Array_Type :=
                          Value_To_Array (TC_Array);
                     begin
                        for I in 1 .. Array_Length (TC_Arr) loop
                           exit when Result.Num_Tool_Calls >=
                             Max_Tool_Calls;
                           declare
                              TC : constant JSON_Value_Type :=
                                Array_Item (TC_Arr, I);
                              Fn : constant JSON_Value_Type :=
                                Get_Object (TC, "function");
                           begin
                              Result.Num_Tool_Calls :=
                                Result.Num_Tool_Calls + 1;
                              Set_Unbounded_String
                                (Result.Tool_Calls
                                   (Result.Num_Tool_Calls).ID,
                                 Get_String (TC, "id"));
                              Set_Unbounded_String
                                (Result.Tool_Calls
                                   (Result.Num_Tool_Calls).Name,
                                 Get_String (Fn, "name"));
                              Set_Unbounded_String
                                (Result.Tool_Calls
                                   (Result.Num_Tool_Calls).Arguments,
                                 Get_String (Fn, "arguments"));
                           end;
                        end loop;
                     end;
                  end;
               end if;
            end;
         end if;

         if Has_Key (PR.Root, "usage") then
            declare
               U : constant JSON_Value_Type :=
                 Get_Object (PR.Root, "usage");
            begin
               Result.Input_Tokens  :=
                 Get_Integer (U, "prompt_tokens");
               Result.Output_Tokens :=
                 Get_Integer (U, "completion_tokens");
            end;
         end if;

         Result.Success := True;
      end;
      return Result;
   end Chat;

   function Chat_Streaming
     (Provider  : in out OpenAI_Compat_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response
   is
      URL       : constant String := Build_Endpoint (Provider);
      Auth_Val  : constant String :=
        (if Provider.Is_Azure
         then To_String (Provider.API_Key)
         else "Bearer " & To_String (Provider.API_Key));
      Auth_Hdr_Name : constant String :=
        (if Provider.Is_Azure then "api-key" else "Authorization");
      Hdrs      : constant HTTP.Client.Header_Array :=
        [1 => (Name  => To_Unbounded_String (Auth_Hdr_Name),
               Value => To_Unbounded_String (Auth_Val))];

      --  Build request body with stream=true.
      Root     : JSON_Value_Type := Build_Object;
      Msgs     : JSON_Value_Type := Build_Array;
      Msgs_Raw : constant Agent.Context.Message_Array :=
        Agent.Context.Format_For_Provider (Conv);

      Result    : Provider_Response;
      Http_Resp : HTTP.Client.Response;
   begin
      --  Reset streaming accumulation state.
      Set_Unbounded_String (Compat_Accumulated, "");
      Set_Unbounded_String (Compat_Stop_Reason, "");

      Set_Field (Root, "model",
        (if Length (Provider.Deployment) > 0
         then To_String (Provider.Deployment)
         else To_String (Provider.Model)));
      Set_Field (Root, "max_tokens", Provider.Max_Tokens);
      Set_Field (Root, "stream", True);

      for I in Msgs_Raw'Range loop
         declare
            M    : JSON_Value_Type := Build_Object;
            Role : constant String :=
              (case Msgs_Raw (I).Role is
               when Agent.Context.System_Role  => "system",
               when Agent.Context.User         => "user",
               when Agent.Context.Assistant    => "assistant",
               when Agent.Context.Tool_Result  => "tool");
         begin
            Set_Field (M, "role",    Role);
            Set_Field (M, "content", To_String (Msgs_Raw (I).Content));
            if Msgs_Raw (I).Role = Agent.Context.Tool_Result then
               Set_Field (M, "tool_call_id",
                 To_String (Msgs_Raw (I).Name));
            end if;
            Append_Array (Msgs, M);
         end;
      end loop;
      Set_Field (Root, "messages", Msgs);

      Http_Resp := HTTP.Client.Post_JSON_Streaming
        (URL        => URL,
         Headers    => Hdrs,
         Body_JSON  => To_JSON_String (Root),
         On_Chunk   => Compat_SSE_Parse'Access,
         Timeout_Ms => Provider.Timeout_Ms);

      if not HTTP.Client.Is_Success (Http_Resp) then
         Set_Unbounded_String
           (Result.Error, "OpenAI-compatible streaming HTTP error:"
            & Natural'Image (Http_Resp.Status_Code));
         return Result;
      end if;

      Ada.Text_IO.New_Line;
      Result.Content     := Compat_Accumulated;
      Result.Stop_Reason := Compat_Stop_Reason;
      Result.Success     := True;
      return Result;
   end Chat_Streaming;

end Providers.OpenAI_Compatible;
