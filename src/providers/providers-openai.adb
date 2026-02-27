with Ada.Text_IO;
with HTTP.Client;
with Metrics;
with Config.JSON_Parser; use Config.JSON_Parser;
with Agent.Context;      use Agent.Context;

pragma SPARK_Mode (Off);
package body Providers.OpenAI is

   OpenAI_Default_URL : constant String := "https://api.openai.com";

   --  -----------------------------------------------------------------------
   --  Streaming accumulation state (package-level; CLI-only, non-concurrent).
   --  -----------------------------------------------------------------------
   OpenAI_Accum_Content : Unbounded_String;
   OpenAI_Finish_Reason : Unbounded_String;
   OpenAI_Has_Tool      : Boolean := False;
   OpenAI_Tool_ID       : Unbounded_String;
   OpenAI_Tool_Name     : Unbounded_String;
   OpenAI_Tool_Args     : Unbounded_String;

   --  SSE line parser called by the HTTP streaming callback.
   procedure OpenAI_SSE_Parse (Line : String);

   procedure OpenAI_SSE_Parse (Line : String) is
   begin
      --  Ignore empty lines and non-data lines.
      if Line'Length < 6 then return; end if;
      if Line (Line'First .. Line'First + 5) /= "data: " then return; end if;

      declare
         JSON_Part : constant String := Line (Line'First + 6 .. Line'Last);
      begin
         if JSON_Part = "[DONE]" then return; end if;

         declare
            PR : constant Parse_Result := Parse (JSON_Part);
         begin
            if not PR.Valid then return; end if;

            if Has_Key (PR.Root, "choices") then
               declare
                  Choices     : constant JSON_Value_Type :=
                    Get_Object (PR.Root, "choices");
                  Choices_Arr : constant JSON_Array_Type :=
                    Value_To_Array (Choices);
               begin
                  if Array_Length (Choices_Arr) >= 1 then
                     declare
                        Choice : constant JSON_Value_Type :=
                          Array_Item (Choices_Arr, 1);
                     begin
                        --  Capture finish_reason when present.
                        declare
                           FR : constant String :=
                             Get_String (Choice, "finish_reason");
                        begin
                           if FR'Length > 0 then
                              Set_Unbounded_String (OpenAI_Finish_Reason, FR);
                           end if;
                        end;

                        if Has_Key (Choice, "delta") then
                           declare
                              D : constant JSON_Value_Type :=
                                Get_Object (Choice, "delta");
                           begin
                              --  Text content token.
                              declare
                                 Token : constant String :=
                                   Get_String (D, "content");
                              begin
                                 if Token'Length > 0 then
                                    Ada.Text_IO.Put (Token);
                                    Ada.Text_IO.Flush;
                                    Append (OpenAI_Accum_Content, Token);
                                 end if;
                              end;

                              --  Tool call fragments.
                              if Has_Key (D, "tool_calls") then
                                 declare
                                    TC_Val : constant JSON_Value_Type :=
                                      Get_Object (D, "tool_calls");
                                    TC_Arr : constant JSON_Array_Type :=
                                      Value_To_Array (TC_Val);
                                 begin
                                    if Array_Length (TC_Arr) >= 1 then
                                       declare
                                          TC : constant JSON_Value_Type :=
                                            Array_Item (TC_Arr, 1);
                                       begin
                                          OpenAI_Has_Tool := True;
                                          declare
                                             TID : constant String :=
                                               Get_String (TC, "id");
                                          begin
                                             if TID'Length > 0 then
                                                Set_Unbounded_String
                                                  (OpenAI_Tool_ID, TID);
                                             end if;
                                          end;
                                          if Has_Key (TC, "function") then
                                             declare
                                                Fn : constant JSON_Value_Type :=
                                                  Get_Object (TC, "function");
                                                TN : constant String :=
                                                  Get_String (Fn, "name");
                                                TA : constant String :=
                                                  Get_String (Fn, "arguments");
                                             begin
                                                if TN'Length > 0 then
                                                   Set_Unbounded_String
                                                     (OpenAI_Tool_Name, TN);
                                                end if;
                                                Append (OpenAI_Tool_Args, TA);
                                             end;
                                          end if;
                                       end;
                                    end if;
                                 end;
                              end if;
                           end;
                        end if;
                     end;
                  end if;
               end;
            end if;
         end;
      end;
   exception
      when others =>
         --  Cannot propagate Ada exceptions through C (libcurl) stack frames.
         --  Discard malformed SSE chunk; streaming continues on next callback.
         Metrics.Increment ("provider_stream_errors", "openai");
   end OpenAI_SSE_Parse;

   function Create (Cfg : Provider_Config) return OpenAI_Provider is
      P : OpenAI_Provider;
   begin
      P.API_Key    := Cfg.API_Key;
      P.Model      := Cfg.Model;
      P.Max_Tokens := Cfg.Max_Tokens;
      P.Timeout_Ms := Cfg.Timeout_Ms;

      if Length (Cfg.Base_URL) > 0 then
         P.Base_URL := Cfg.Base_URL;
      else
         Set_Unbounded_String (P.Base_URL, OpenAI_Default_URL);
      end if;

      if Length (P.Model) = 0 then
         Set_Unbounded_String (P.Model, "gpt-4o");
      end if;
      return P;
   end Create;

   function Name (Provider : OpenAI_Provider) return String is
     ("openai:" & To_String (Provider.Model));

   --  Build the JSON request body.
   function Build_Request_Body
     (Provider  : OpenAI_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural;
      Stream    : Boolean := False) return String
   is
      Root  : JSON_Value_Type := Build_Object;
      Msgs  : JSON_Value_Type := Build_Array;
      Msgs_Raw : constant Agent.Context.Message_Array :=
        Agent.Context.Format_For_Provider (Conv);
   begin
      Set_Field (Root, "model",      To_String (Provider.Model));
      Set_Field (Root, "max_tokens", Provider.Max_Tokens);

      --  Messages
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
               Set_Field (M, "tool_call_id", To_String (Msgs_Raw (I).Name));
            end if;
            Append_Array (Msgs, M);
         end;
      end loop;
      Set_Field (Root, "messages", Msgs);

      --  Tools (if any)
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

      if Stream then
         Set_Field (Root, "stream", True);
      end if;

      return To_JSON_String (Root);
   end Build_Request_Body;

   --  Parse tool_calls array from response.
   procedure Parse_Tool_Calls
     (Resp_Root : JSON_Value_Type;
      Result    : in out Provider_Response)
   is
   begin
      if not Has_Key (Resp_Root, "tool_calls") then
         return;
      end if;
      declare
         TC_Array : constant JSON_Value_Type :=
           Get_Object (Resp_Root, "tool_calls");
      begin
         declare
            TC_Arr : constant JSON_Array_Type :=
              Value_To_Array (TC_Array);
         begin
            for I in 1 .. Array_Length (TC_Arr) loop
            exit when Result.Num_Tool_Calls >= Max_Tool_Calls;
            declare
               TC_Item  : constant JSON_Value_Type := Array_Item (TC_Arr, I);
               Fn       : constant JSON_Value_Type :=
                 Get_Object (TC_Item, "function");
            begin
               Result.Num_Tool_Calls := Result.Num_Tool_Calls + 1;
               Set_Unbounded_String
                 (Result.Tool_Calls (Result.Num_Tool_Calls).ID,
                  Get_String (TC_Item, "id"));
               Set_Unbounded_String
                 (Result.Tool_Calls (Result.Num_Tool_Calls).Name,
                  Get_String (Fn, "name"));
               Set_Unbounded_String
                 (Result.Tool_Calls (Result.Num_Tool_Calls).Arguments,
                  Get_String (Fn, "arguments"));
            end;
         end loop;
      end;
   end;
   end Parse_Tool_Calls;

   function Chat
     (Provider  : in out OpenAI_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response
   is
      URL      : constant String :=
        To_String (Provider.Base_URL) & "/v1/chat/completions";
      Auth_Hdr : constant HTTP.Client.Header :=
        (Name  => To_Unbounded_String ("Authorization"),
         Value => To_Unbounded_String
           ("Bearer " & To_String (Provider.API_Key)));
      Hdrs     : constant HTTP.Client.Header_Array := (1 => Auth_Hdr);
      Body_Str : constant String :=
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

         --  choices[0].message
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
                 (Result.Stop_Reason, Get_String (First, "finish_reason"));
               Parse_Tool_Calls (Msg, Result);
            end;
         end if;

         --  usage
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
     (Provider  : in out OpenAI_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response
   is
      URL      : constant String :=
        To_String (Provider.Base_URL) & "/v1/chat/completions";
      Auth_Hdr : constant HTTP.Client.Header :=
        (Name  => To_Unbounded_String ("Authorization"),
         Value => To_Unbounded_String
           ("Bearer " & To_String (Provider.API_Key)));
      Hdrs     : constant HTTP.Client.Header_Array := (1 => Auth_Hdr);
      Body_Str : constant String :=
        Build_Request_Body (Provider, Conv, Tools, Num_Tools, Stream => True);

      Http_Resp : HTTP.Client.Response;
      Result    : Provider_Response;
   begin
      --  Reset streaming accumulation state.
      Set_Unbounded_String (OpenAI_Accum_Content, "");
      Set_Unbounded_String (OpenAI_Finish_Reason, "");
      Set_Unbounded_String (OpenAI_Tool_ID,       "");
      Set_Unbounded_String (OpenAI_Tool_Name,     "");
      Set_Unbounded_String (OpenAI_Tool_Args,     "");
      OpenAI_Has_Tool := False;

      Http_Resp := HTTP.Client.Post_JSON_Streaming
        (URL        => URL,
         Headers    => Hdrs,
         Body_JSON  => Body_Str,
         On_Chunk   => OpenAI_SSE_Parse'Access,
         Timeout_Ms => Provider.Timeout_Ms);

      if not HTTP.Client.Is_Success (Http_Resp) then
         Set_Unbounded_String
           (Result.Error,
            "HTTP " & Http_Resp.Status_Code'Image & ": "
            & To_String (Http_Resp.Error));
         return Result;
      end if;

      Result.Content    := OpenAI_Accum_Content;
      Result.Stop_Reason := OpenAI_Finish_Reason;
      Result.Success    := True;

      if OpenAI_Has_Tool then
         Result.Num_Tool_Calls := 1;
         Result.Tool_Calls (1).ID        := OpenAI_Tool_ID;
         Result.Tool_Calls (1).Name      := OpenAI_Tool_Name;
         Result.Tool_Calls (1).Arguments := OpenAI_Tool_Args;
         Set_Unbounded_String (Result.Stop_Reason, "tool_calls");
      end if;

      return Result;
   end Chat_Streaming;

end Providers.OpenAI;
