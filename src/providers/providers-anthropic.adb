with HTTP.Client;
with Config.JSON_Parser; use Config.JSON_Parser;

package body Providers.Anthropic is

   Anthropic_API_URL : constant String := "https://api.anthropic.com";
   Anthropic_Version : constant String := "2023-06-01";

   function Create (Cfg : Provider_Config) return Anthropic_Provider is
      P : Anthropic_Provider;
   begin
      P.API_Key    := Cfg.API_Key;
      P.Model      := Cfg.Model;
      P.Max_Tokens := Cfg.Max_Tokens;
      P.Timeout_Ms := Cfg.Timeout_Ms;
      if Length (P.Model) = 0 then
         Set_Unbounded_String (P.Model, "claude-3-5-sonnet-20241022");
      end if;
      return P;
   end Create;

   function Name (Provider : Anthropic_Provider) return String is
     ("anthropic:" & To_String (Provider.Model));

   function Build_Request_Body
     (Provider  : Anthropic_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return String
   is
      Root       : JSON_Value_Type := Build_Object;
      Msgs       : JSON_Value_Type := Build_Array;
      System_Txt : Unbounded_String;
      Msgs_Raw   : constant Agent.Context.Message_Array :=
        Agent.Context.Format_For_Provider (Conv);
   begin
      Set_Field (Root, "model",      To_String (Provider.Model));
      Set_Field (Root, "max_tokens", Provider.Max_Tokens);

      --  Anthropic separates system prompt from messages.
      for I in Msgs_Raw'Range loop
         if Msgs_Raw (I).Role = Agent.Context.System_Role then
            Append (System_Txt, To_String (Msgs_Raw (I).Content));
         else
            declare
               M    : JSON_Value_Type := Build_Object;
               Role : constant String :=
                 (case Msgs_Raw (I).Role is
                  when Agent.Context.User        => "user",
                  when Agent.Context.Assistant   => "assistant",
                  when Agent.Context.Tool_Result => "user",  -- wrapped below
                  when others                    => "user");
            begin
               if Msgs_Raw (I).Role = Agent.Context.Tool_Result then
                  --  tool_result is wrapped in a "user" message with content array.
                  declare
                     Content_Arr : JSON_Value_Type := Build_Array;
                     TR          : JSON_Value_Type := Build_Object;
                  begin
                     Set_Field (TR, "type",        "tool_result");
                     Set_Field (TR, "tool_use_id",
                       To_String (Msgs_Raw (I).Name));
                     Set_Field (TR, "content",
                       To_String (Msgs_Raw (I).Content));
                     Append_Array (Content_Arr, TR);
                     Set_Field (M, "role",    "user");
                     Set_Field (M, "content", Content_Arr);
                  end;
               else
                  Set_Field (M, "role",    Role);
                  Set_Field (M, "content",
                    To_String (Msgs_Raw (I).Content));
               end if;
               Append_Array (Msgs, M);
            end;
         end if;
      end loop;

      if Length (System_Txt) > 0 then
         Set_Field (Root, "system", To_String (System_Txt));
      end if;
      Set_Field (Root, "messages", Msgs);

      --  Tools
      if Num_Tools > 0 then
         declare
            Tools_JSON : JSON_Value_Type := Build_Array;
         begin
            for I in 1 .. Num_Tools loop
               declare
                  T_Obj  : JSON_Value_Type := Build_Object;
                  Params : Parse_Result;
               begin
                  Set_Field (T_Obj, "name",
                    To_String (Tools (I).Name));
                  Set_Field (T_Obj, "description",
                    To_String (Tools (I).Description));
                  Params := Parse (To_String (Tools (I).Parameters));
                  if Params.Valid then
                     Set_Field (T_Obj, "input_schema", Params.Root);
                  end if;
                  Append_Array (Tools_JSON, T_Obj);
               end;
            end loop;
            Set_Field (Root, "tools", Tools_JSON);
         end;
      end if;

      return To_JSON_String (Root);
   end Build_Request_Body;

   function Chat
     (Provider  : in out Anthropic_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response
   is
      URL       : constant String := Anthropic_API_URL & "/v1/messages";
      Hdrs      : constant HTTP.Client.Header_Array :=
        (1 => (Name  => To_Unbounded_String ("x-api-key"),
               Value => Provider.API_Key),
         2 => (Name  => To_Unbounded_String ("anthropic-version"),
               Value => To_Unbounded_String (Anthropic_Version)));
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

         --  Response content is an array of content blocks.
         if Has_Key (PR.Root, "content") then
            declare
               Blocks : constant JSON_Value_Type :=
                 Get_Object (PR.Root, "content");
            begin
               for I in 1 .. Integer (Blocks.Length) loop
                  declare
                     Block : constant JSON_Value_Type := Blocks.Get (I);
                     BType : constant String :=
                       Get_String (Block, "type");
                  begin
                     if BType = "text" then
                        Append (Result.Content,
                          Get_String (Block, "text"));
                     elsif BType = "tool_use" then
                        exit when Result.Num_Tool_Calls >= Max_Tool_Calls;
                        Result.Num_Tool_Calls :=
                          Result.Num_Tool_Calls + 1;
                        Set_Unbounded_String
                          (Result.Tool_Calls
                             (Result.Num_Tool_Calls).ID,
                           Get_String (Block, "id"));
                        Set_Unbounded_String
                          (Result.Tool_Calls
                             (Result.Num_Tool_Calls).Name,
                           Get_String (Block, "name"));
                        Set_Unbounded_String
                          (Result.Tool_Calls
                             (Result.Num_Tool_Calls).Arguments,
                           To_JSON_String (Get_Object (Block, "input")));
                     end if;
                  end;
               end loop;
            end;
         end if;

         Set_Unbounded_String
           (Result.Stop_Reason, Get_String (PR.Root, "stop_reason"));

         if Has_Key (PR.Root, "usage") then
            declare
               U : constant JSON_Value_Type :=
                 Get_Object (PR.Root, "usage");
            begin
               Result.Input_Tokens  :=
                 Get_Integer (U, "input_tokens");
               Result.Output_Tokens :=
                 Get_Integer (U, "output_tokens");
            end;
         end if;

         Result.Success := True;
      end;
      return Result;
   end Chat;

end Providers.Anthropic;
