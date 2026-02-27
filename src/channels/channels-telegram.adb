with Ada.Text_IO;
with Ada.Strings.Fixed;   use Ada.Strings.Fixed;
with HTTP.Client;
with Config.JSON_Parser;  use Config.JSON_Parser;
with Config.Schema;       use Config.Schema;
with Config.Loader;
with Config.Reload;
with Agent.Context;
with Agent.Loop_Pkg;
with Channels.Security;   -- SPARK security policy checks
with Channels.Rate_Limit;
with Metrics;
with Audit.Syslog;

package body Channels.Telegram is

   Telegram_API : constant String := "https://api.telegram.org/bot";

   function Bot_URL (Token : String) return String is
     (Telegram_API & Token);

   function Send_Message
     (Bot_Token : String;
      Chat_ID   : String;
      Text      : String) return Boolean
   is
      --  Split long messages (Telegram limit: 4096 chars).
      Max_Chunk : constant := 4000;
      Offset    : Natural := 0;
   begin
      while Offset < Text'Length loop
         declare
            Chunk_End : constant Natural :=
              Natural'Min (Offset + Max_Chunk, Text'Length);
            Chunk     : constant String :=
              Text (Text'First + Offset .. Text'First + Chunk_End - 1);

            Body_Obj  : JSON_Value_Type := Build_Object;
            Hdrs      : constant HTTP.Client.Header_Array :=
              (1 => (Name  => To_Unbounded_String ("Content-Type"),
                     Value => To_Unbounded_String ("application/json")));
            Resp      : HTTP.Client.Response;
         begin
            Set_Field (Body_Obj, "chat_id", Chat_ID);
            Set_Field (Body_Obj, "text",    Chunk);
            Set_Field (Body_Obj, "parse_mode", "Markdown");

            Resp := HTTP.Client.Post_JSON
              (URL       => Bot_URL (Bot_Token) & "/sendMessage",
               Headers   => Hdrs,
               Body_JSON => To_JSON_String (Body_Obj));

            if not HTTP.Client.Is_Success (Resp) then
               return False;
            end if;
         end;
         Offset := Offset + Max_Chunk;
      end loop;
      return True;
   end Send_Message;

   function Process_Update
     (Update_JSON : String;
      Cfg         : Config.Schema.Agent_Config;
      Mem         : Memory.SQLite.Memory_Handle) return String
   is
      PR      : constant Parse_Result := Parse (Update_JSON);
      Result  : Unbounded_String;
   begin
      if not PR.Valid then
         return "";
      end if;

      --  Only handle "message" updates with text.
      if not Has_Key (PR.Root, "message") then
         return "";
      end if;

      declare
         Msg         : constant JSON_Value_Type :=
           Get_Object (PR.Root, "message");
         Text        : constant String := Get_String (Msg, "text");
         Chat        : constant JSON_Value_Type := Get_Object (Msg, "chat");
         Chat_ID     : constant String := Get_String (Chat, "id");
         From        : constant JSON_Value_Type := Get_Object (Msg, "from");
         User_ID     : constant String := Get_String (From, "id");
         Is_Operator : Boolean := False;
      begin
         if Text'Length = 0 then
            return "";
         end if;

         --  Allowlist check via SPARK security policy.
         --  Find the Telegram channel config.
         declare
            Chan_Cfg : Config.Schema.Channel_Config;
            Found    : Boolean := False;
         begin
            for I in 1 .. Cfg.Num_Channels loop
               if Cfg.Channels (I).Kind = Config.Schema.Telegram then
                  Chan_Cfg := Cfg.Channels (I);
                  Found := True;
                  exit;
               end if;
            end loop;

            if not Found or else not Chan_Cfg.Enabled then
               return "";
            end if;

            --  Check if user_id is in allowlist (empty allowlist = deny all).
            declare
               Allowlist   : constant String :=
                 To_String (Chan_Cfg.Allowlist);
               Comma       : constant Natural := Index (Allowlist, ",");
               First_Entry : constant String :=
                 (if Comma > 0 then Allowlist (Allowlist'First .. Comma - 1)
                  else Allowlist);
            begin
               if Allowlist'Length = 0 then
                  Audit.Syslog.Log_Event
                    ("access_denied", User_ID, "telegram",
                     "no allowlist configured");
                  return "";  -- deny all when no allowlist configured
               end if;
               if Allowlist /= "*"
                 and then Index (Allowlist, User_ID) = 0
               then
                  Audit.Syslog.Log_Event
                    ("access_denied", User_ID, "telegram",
                     "user not in allowlist");
                  return "";  -- user not in allowlist
               end if;
               --  Operator = first allowlist entry; guest = open-access users.
               Is_Operator := Allowlist /= "*" and then User_ID = First_Entry;
            end;

            --  Rate limit: enforce Max_RPS per user session.
            if not Channels.Rate_Limit.Check
              ("tg:" & Chat_ID, Chan_Cfg.Max_RPS)
            then
               return "";  -- silently drop rate-exceeded messages
            end if;
         end;

         --  Process via agent loop.
         declare
            Sess  : constant String :=
              (if Is_Operator then "tg:" & Chat_ID
               else "guest-tg-" & Chat_ID);
            Conv  : Agent.Context.Conversation;
            Reply : Agent.Loop_Pkg.Agent_Reply;
         begin
            Set_Unbounded_String (Conv.Session_ID, Sess);
            Set_Unbounded_String (Conv.Channel, "telegram:" & Chat_ID);

            --  Load existing history for this session.
            if Memory.SQLite.Is_Open (Mem) then
               Memory.SQLite.Load_History
                 (Mem, Sess, Cfg.Memory.Max_History, Conv);
            end if;

            Metrics.Increment ("requests_total", "telegram");
            Audit.Syslog.Log_Event ("message_received", User_ID, "telegram");

            if Is_Operator then
               Reply := Agent.Loop_Pkg.Process_Message
                 (User_Input => Text,
                  Conv       => Conv,
                  Cfg        => Cfg,
                  Mem        => Mem);
            else
               declare
                  Guest_Cfg : Agent_Config := Cfg;
               begin
                  Set_Unbounded_String
                    (Guest_Cfg.System_Prompt,
                     To_String (Cfg.System_Prompt)
                     & " [Note: You are speaking with a guest user."
                     & " Keep responses helpful but brief.]");
                  Reply := Agent.Loop_Pkg.Process_Message
                    (User_Input => Text,
                     Conv       => Conv,
                     Cfg        => Guest_Cfg,
                     Mem        => Mem);
               end;
            end if;

            if Reply.Success then
               return To_String (Reply.Content);
            else
               Metrics.Increment ("errors_total", "telegram");
               return "Sorry, I encountered an error. Please try again.";
            end if;
         end;
      end;
   end Process_Update;

   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle)
   is
      --  Find Telegram channel config.
      Current_Cfg : Config.Schema.Agent_Config := Cfg;
      Bot_Token   : Unbounded_String;
      Found       : Boolean := False;
   begin
      for I in 1 .. Current_Cfg.Num_Channels loop
         if Current_Cfg.Channels (I).Kind = Config.Schema.Telegram
           and then Current_Cfg.Channels (I).Enabled
         then
            Bot_Token := Current_Cfg.Channels (I).Token;
            Found := True;
            exit;
         end if;
      end loop;

      if not Found or else Length (Bot_Token) = 0 then
         Ada.Text_IO.Put_Line
           ("Telegram: no bot token configured, skipping.");
         return;
      end if;

      Ada.Text_IO.Put_Line
        ("Telegram: starting long-polling loop...");

      declare
         Offset : Integer := 0;
      begin
         loop
            --  Check for SIGHUP-triggered config reload.
            if Config.Reload.Is_Requested then
               declare
                  New_CR : constant Config.Loader.Load_Result :=
                    Config.Loader.Load;
               begin
                  if New_CR.Success then
                     Current_Cfg := New_CR.Config;
                     Ada.Text_IO.Put_Line ("Config reloaded.");
                     for I in 1 .. Current_Cfg.Num_Channels loop
                        if Current_Cfg.Channels (I).Kind =
                          Config.Schema.Telegram
                          and then Current_Cfg.Channels (I).Enabled
                        then
                           Bot_Token := Current_Cfg.Channels (I).Token;
                           exit;
                        end if;
                     end loop;
                  end if;
               end;
               Config.Reload.Acknowledge;
            end if;

            declare
               Token : constant String := To_String (Bot_Token);
               URL   : constant String :=
                 Bot_URL (Token)
                 & "/getUpdates?offset="
                 & Integer'Image (Offset)
                 & "&timeout=30";
               Resp  : constant HTTP.Client.Response :=
                 HTTP.Client.Get
                   (URL        => URL,
                    Headers    => (1 .. 0 => <>),
                    Timeout_Ms => 35_000);
            begin
               if HTTP.Client.Is_Success (Resp) then
                  declare
                     PR : constant Parse_Result :=
                       Parse (To_String (Resp.Body_Text));
                  begin
                     if PR.Valid and then Has_Key (PR.Root, "result") then
                        declare
                           Updates : constant JSON_Value_Type :=
                             Get_Object (PR.Root, "result");
                        begin
                           declare
                              Upd_Arr : constant JSON_Array_Type :=
                                Value_To_Array (Updates);
                           begin
                              for I in 1 .. Array_Length (Upd_Arr) loop
                              declare
                                 Update    : constant JSON_Value_Type :=
                                   Array_Item (Upd_Arr, I);
                                 Update_ID : constant Integer :=
                                   Get_Integer (Update, "update_id");
                                 Reply_Text : constant String :=
                                   Process_Update
                                     (To_JSON_String (Update),
                                      Current_Cfg, Mem);
                              begin
                                 if Reply_Text'Length > 0 then
                                    declare
                                       Msg     : constant JSON_Value_Type :=
                                         Get_Object (Update, "message");
                                       Chat    : constant JSON_Value_Type :=
                                         Get_Object (Msg, "chat");
                                       Chat_ID : constant String :=
                                         Get_String (Chat, "id");
                                    begin
                                       if not Send_Message
                                         (Token, Chat_ID, Reply_Text)
                                       then
                                          Ada.Text_IO.Put_Line
                                            ("Telegram: send failed for "
                                             & Chat_ID);
                                       end if;
                                    end;
                                 end if;
                                 Offset := Update_ID + 1;
                              end;
                              end loop;
                           end;
                        end;
                     end if;
                  end;
               end if;
            end;
         end loop;
      end;
   end Run_Polling;

end Channels.Telegram;
