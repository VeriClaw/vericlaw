with HTTP.Client;
with Config.JSON_Parser; use Config.JSON_Parser;
with Agent.Context;      use Agent.Context;
with Ada.Text_IO;
with Logging;

package body Providers.Gemini
  with SPARK_Mode => Off
is

   Gemini_Base_URL : constant String :=
     "https://generativelanguage.googleapis.com/v1beta/models/";

   function Create (Cfg : Provider_Config) return Gemini_Provider is
      P : Gemini_Provider;
   begin
      P.API_Key    := Cfg.API_Key;
      P.Model      := Cfg.Model;
      P.Max_Tokens := Cfg.Max_Tokens;
      P.Timeout_Ms := Cfg.Timeout_Value;
      if Length (P.Model) = 0 then
         Set_Unbounded_String (P.Model, "gemini-2.0-flash");
      end if;
      return P;
   end Create;

   function Name (Provider : Gemini_Provider) return String is
     ("gemini:" & To_String (Provider.Model));

   --  Build the Gemini generateContent request body.
   function Build_Request_Body
     (Provider  : Gemini_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return String
   is
      Root       : JSON_Value_Type := Build_Object;
      Contents   : JSON_Value_Type := Build_Array;
      System_Txt : Unbounded_String;
      Msgs_Raw   : constant Agent.Context.Message_Array :=
        Agent.Context.Format_For_Provider (Conv);
   begin
      --  generationConfig
      declare
         Gen_Config : JSON_Value_Type := Build_Object;
      begin
         Set_Field (Gen_Config, "maxOutputTokens", Provider.Max_Tokens);
         Set_Field (Root, "generationConfig", Gen_Config);
      end;

      --  Build contents array; extract system message separately.
      for I in Msgs_Raw'Range loop
         if Msgs_Raw (I).Role = Agent.Context.System_Role then
            Append (System_Txt, To_String (Msgs_Raw (I).Content));
         else
            declare
               M     : JSON_Value_Type := Build_Object;
               Parts : JSON_Value_Type := Build_Array;
            begin
               if Msgs_Raw (I).Role = Agent.Context.Tool_Result then
                  --  Gemini tool result: role="function",
                  --  parts=[{functionResponse:{name:...,response:{output:...}}}]
                  declare
                     FR_Part : JSON_Value_Type := Build_Object;
                     FR      : JSON_Value_Type := Build_Object;
                     FR_Resp : JSON_Value_Type := Build_Object;
                  begin
                     Set_Field (FR_Resp, "output",
                       To_String (Msgs_Raw (I).Content));
                     Set_Field (FR, "name",
                       To_String (Msgs_Raw (I).Name));
                     Set_Field (FR, "response", FR_Resp);
                     Set_Field (FR_Part, "functionResponse", FR);
                     Append_Array (Parts, FR_Part);
                     Set_Field (M, "role", "function");
                  end;
               else
                  declare
                     Text_Part : JSON_Value_Type := Build_Object;
                     Role      : constant String :=
                       (case Msgs_Raw (I).Role is
                        when Agent.Context.User      => "user",
                        when Agent.Context.Assistant => "model",
                        when others                  => "user");
                  begin
                     Set_Field (Text_Part, "text",
                       To_String (Msgs_Raw (I).Content));
                     Append_Array (Parts, Text_Part);
                     Set_Field (M, "role", Role);
                  end;
               end if;
               Set_Field (M, "parts", Parts);
               Append_Array (Contents, M);
            end;
         end if;
      end loop;

      --  systemInstruction (separate from contents in Gemini API)
      if Length (System_Txt) > 0 then
         declare
            SI       : JSON_Value_Type := Build_Object;
            SI_Part  : JSON_Value_Type := Build_Object;
            SI_Parts : JSON_Value_Type := Build_Array;
         begin
            Set_Field (SI_Part, "text", To_String (System_Txt));
            Append_Array (SI_Parts, SI_Part);
            Set_Field (SI, "parts", SI_Parts);
            Set_Field (Root, "systemInstruction", SI);
         end;
      end if;

      Set_Field (Root, "contents", Contents);

      --  Tools → functionDeclarations
      if Num_Tools > 0 then
         declare
            Tools_Arr : JSON_Value_Type := Build_Array;
            Tool_Obj  : JSON_Value_Type := Build_Object;
            Fn_Decls  : JSON_Value_Type := Build_Array;
         begin
            for I in 1 .. Num_Tools loop
               declare
                  Fn_Obj : JSON_Value_Type := Build_Object;
                  Params : Parse_Result;
               begin
                  Set_Field (Fn_Obj, "name",
                    To_String (Tools (I).Name));
                  Set_Field (Fn_Obj, "description",
                    To_String (Tools (I).Description));
                  Params := Parse (To_String (Tools (I).Parameters));
                  if Params.Valid then
                     Set_Field (Fn_Obj, "parameters", Params.Root);
                  end if;
                  Append_Array (Fn_Decls, Fn_Obj);
               end;
            end loop;
            Set_Field (Tool_Obj, "functionDeclarations", Fn_Decls);
            Append_Array (Tools_Arr, Tool_Obj);
            Set_Field (Root, "tools", Tools_Arr);
         end;
      end if;

      return To_JSON_String (Root);
   end Build_Request_Body;

   function Chat
     (Provider  : in out Gemini_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response
   is
      --  API key passed as query param, no Authorization header needed.
      URL      : constant String :=
        Gemini_Base_URL
        & To_String (Provider.Model)
        & ":generateContent?key="
        & To_String (Provider.API_Key);
      No_Hdrs  : constant HTTP.Client.Header_Array (1 .. 0) := (others => <>);
      Body_Str : constant String :=
        Build_Request_Body (Provider, Conv, Tools, Num_Tools);

      Http_Resp : constant HTTP.Client.Response :=
        HTTP.Client.Post_JSON
          (URL        => URL,
           Headers    => No_Hdrs,
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

         --  candidates[0].content.parts
         if Has_Key (PR.Root, "candidates") then
            declare
               Cands     : constant JSON_Value_Type :=
                 Get_Object (PR.Root, "candidates");
               Cands_Arr : constant JSON_Array_Type :=
                 Value_To_Array (Cands);
               First     : constant JSON_Value_Type :=
                 Array_Item (Cands_Arr, 1);
               Content   : constant JSON_Value_Type :=
                 Get_Object (First, "content");
               Parts     : constant JSON_Value_Type :=
                 Get_Object (Content, "parts");
               Parts_Arr : constant JSON_Array_Type :=
                 Value_To_Array (Parts);
            begin
               Set_Unbounded_String
                 (Result.Stop_Reason, Get_String (First, "finishReason"));

               for I in 1 .. Array_Length (Parts_Arr) loop
                     declare
                        Part : constant JSON_Value_Type :=
                          Array_Item (Parts_Arr, I);
                     begin
                        if Has_Key (Part, "text") then
                           Append (Result.Content, Get_String (Part, "text"));
                        elsif Has_Key (Part, "functionCall") then
                           exit when Result.Num_Tool_Calls >= Max_Tool_Calls;
                           declare
                              FC : constant JSON_Value_Type :=
                                Get_Object (Part, "functionCall");
                              FN : constant String :=
                                Get_String (FC, "name");
                           begin
                              Result.Num_Tool_Calls :=
                                Result.Num_Tool_Calls + 1;
                              --  Gemini uses function name as call ID.
                              Set_Unbounded_String
                                (Result.Tool_Calls
                                   (Result.Num_Tool_Calls).ID, FN);
                              Set_Unbounded_String
                                (Result.Tool_Calls
                                   (Result.Num_Tool_Calls).Name, FN);
                              --  args is a JSON object; serialise to string.
                              Set_Unbounded_String
                                (Result.Tool_Calls
                                   (Result.Num_Tool_Calls).Arguments,
                                 To_JSON_String (Get_Object (FC, "args")));
                           end;
                        end if;
                     end;
               end loop;
            end;
         end if;

         --  usageMetadata
         if Has_Key (PR.Root, "usageMetadata") then
            declare
               U : constant JSON_Value_Type :=
                 Get_Object (PR.Root, "usageMetadata");
            begin
               Result.Input_Tokens  :=
                 Get_Integer (U, "promptTokenCount");
               Result.Output_Tokens :=
                 Get_Integer (U, "candidatesTokenCount");
            end;
         end if;

         Result.Success := True;
      end;
      return Result;
   end Chat;

   function Chat_Streaming
     (Provider  : in out Gemini_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response
   is
      --  Gemini streaming endpoint uses streamGenerateContent with SSE.
      URL      : constant String :=
        Gemini_Base_URL
        & To_String (Provider.Model)
        & ":streamGenerateContent?alt=sse&key="
        & To_String (Provider.API_Key);
      No_Hdrs  : constant HTTP.Client.Header_Array (1 .. 0) := (others => <>);
      Body_Str : constant String :=
        Build_Request_Body (Provider, Conv, Tools, Num_Tools);

      Result        : Provider_Response;
      Accumulated   : Unbounded_String;
      Http_Resp     : HTTP.Client.Response;

      procedure On_SSE_Line (Line : String) is
         --  Gemini SSE sends "data: {json}" lines.
         Prefix : constant String := "data: ";
      begin
         if Line'Length > Prefix'Length
           and then Line (Line'First .. Line'First + Prefix'Length - 1) = Prefix
         then
            declare
               Payload : constant String :=
                 Line (Line'First + Prefix'Length .. Line'Last);
               PR : constant Parse_Result := Parse (Payload);
            begin
               if PR.Valid and then Has_Key (PR.Root, "candidates") then
                  declare
                     Cands     : constant JSON_Value_Type :=
                       Get_Object (PR.Root, "candidates");
                     Cands_Arr : constant JSON_Array_Type :=
                       Value_To_Array (Cands);
                  begin
                     if Array_Length (Cands_Arr) > 0 then
                        declare
                           First     : constant JSON_Value_Type :=
                             Array_Item (Cands_Arr, 1);
                           Content   : constant JSON_Value_Type :=
                             Get_Object (First, "content");
                           Parts     : constant JSON_Value_Type :=
                             Get_Object (Content, "parts");
                           Parts_Arr : constant JSON_Array_Type :=
                             Value_To_Array (Parts);
                        begin
                           for I in 1 .. Array_Length (Parts_Arr) loop
                                 declare
                                    Part : constant JSON_Value_Type :=
                                      Array_Item (Parts_Arr, I);
                                 begin
                                    if Has_Key (Part, "text") then
                                       declare
                                          Chunk : constant String :=
                                            Get_String (Part, "text");
                                       begin
                                          Ada.Text_IO.Put (Chunk);
                                          Append (Accumulated, Chunk);
                                       end;
                                    elsif Has_Key (Part, "functionCall") then
                                       if Result.Num_Tool_Calls < Max_Tool_Calls then
                                          declare
                                             FC : constant JSON_Value_Type :=
                                               Get_Object (Part, "functionCall");
                                             FN : constant String :=
                                               Get_String (FC, "name");
                                          begin
                                             Result.Num_Tool_Calls :=
                                               Result.Num_Tool_Calls + 1;
                                             Set_Unbounded_String
                                               (Result.Tool_Calls
                                                  (Result.Num_Tool_Calls).ID, FN);
                                             Set_Unbounded_String
                                               (Result.Tool_Calls
                                                  (Result.Num_Tool_Calls).Name, FN);
                                             Set_Unbounded_String
                                               (Result.Tool_Calls
                                                  (Result.Num_Tool_Calls).Arguments,
                                                To_JSON_String
                                                  (Get_Object (FC, "args")));
                                          end;
                                       end if;
                                    end if;
                                 end;
                           end loop;

                           if Has_Key (First, "finishReason") then
                              Set_Unbounded_String
                                (Result.Stop_Reason,
                                 Get_String (First, "finishReason"));
                           end if;
                        end;
                     end if;
                  end;
               end if;

               if PR.Valid and then Has_Key (PR.Root, "usageMetadata") then
                  declare
                     U : constant JSON_Value_Type :=
                       Get_Object (PR.Root, "usageMetadata");
                  begin
                     Result.Input_Tokens  :=
                       Get_Integer (U, "promptTokenCount");
                     Result.Output_Tokens :=
                       Get_Integer (U, "candidatesTokenCount");
                  end;
               end if;
            end;
         end if;
      exception
         when others =>
            Logging.Debug ("Malformed SSE chunk discarded");
      end On_SSE_Line;
   begin
      Http_Resp := HTTP.Client.Post_JSON_Streaming
        (URL        => URL,
         Headers    => No_Hdrs,
         Body_JSON  => Body_Str,
         On_Chunk   => On_SSE_Line'Access,
         Timeout_Ms => Provider.Timeout_Ms);

      if not HTTP.Client.Is_Success (Http_Resp) then
         Set_Unbounded_String
           (Result.Error, "Gemini streaming HTTP error:"
            & Natural'Image (Http_Resp.Status_Code));
         return Result;
      end if;

      Ada.Text_IO.New_Line;
      Result.Content := Accumulated;
      Result.Success := True;
      return Result;
   end Chat_Streaming;

end Providers.Gemini;
