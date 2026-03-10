with Logging;
with Ada.Exceptions; use Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HTTP.Client;
with Config.JSON_Parser; use Config.JSON_Parser;
with Config.Loader;
with Config.Reload;
with Agent.Context;
with Agent.Loop_Pkg;
with Ada.Strings.Fixed;  use Ada.Strings.Fixed;
with Channels.Bridge_Polling;
with Channels.Rate_Limit;
with Channels.Message_Dedup;
with Metrics;

package body Channels.WhatsApp
  with SPARK_Mode => Off
is
   use Config.Schema;

   Default_Session : constant String := "vericlaw";

   Seen : Channels.Message_Dedup.Dedup_Buffer;

   function Send_Message
     (Bridge_URL : String;
      Session_ID : String;
      Chat_ID    : String;
      Message    : String) return Boolean
   is
      Body_Obj : JSON_Value_Type := Build_Object;
      Resp     : HTTP.Client.Response;
   begin
      Set_Field (Body_Obj, "chatId",  Chat_ID);
      Set_Field (Body_Obj, "message", Message);

      Resp := HTTP.Client.Post_JSON
        (URL       => Bridge_URL & "/sessions/" & Session_ID & "/messages",
         Headers   => (1 .. 0 => <>),
         Body_JSON => To_JSON_String (Body_Obj));

      return HTTP.Client.Is_Success (Resp);
   end Send_Message;

   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle)
   is
      Current_Cfg : Config.Schema.Agent_Config := Cfg;
      Chan_Cfg    : Config.Schema.Channel_Config :=
        Find_Channel (Current_Cfg, Config.Schema.WhatsApp);
      Bridge_URL  : Unbounded_String :=
        Chan_Cfg.Bridge_URL;
      Poll_State  : Channels.Bridge_Polling.Backoff_State;
   begin
      if not Chan_Cfg.Enabled or else Length (Bridge_URL) = 0 then
         Logging.Warning ("WhatsApp: not configured, skipping.");
         return;
      end if;

      Channels.Bridge_Polling.Initialize
        (Poll_State, Base_Delay => 2.0, Max_Delay => 30.0);

      Logging.Info ("WhatsApp: polling " & To_String (Bridge_URL) & " ...");

      loop
         --  Check for SIGHUP-triggered config reload.
         if Config.Reload.Is_Requested then
            declare
               New_CR : constant Config.Loader.Load_Result :=
                 Config.Loader.Load;
            begin
               if New_CR.Success then
                  Current_Cfg := New_CR.Config;
                  Chan_Cfg    := Find_Channel (Current_Cfg, Config.Schema.WhatsApp);
                  Bridge_URL  := Chan_Cfg.Bridge_URL;
                  Logging.Info ("Config reloaded.");
               end if;
            end;
            Config.Reload.Acknowledge;
         end if;

         declare
            Poll_Succeeded : Boolean := False;
         begin
            declare
               BU   : constant String := To_String (Bridge_URL);
               Resp : constant HTTP.Client.Response :=
                 HTTP.Client.Get
                   (URL        => BU & "/sessions/"
                     & Default_Session & "/messages?limit=10",
                    Headers    => (1 .. 0 => <>),
                    Timeout_Ms => 10_000);
            begin
               if HTTP.Client.Is_Success (Resp) then
                  declare
                     PR : constant Parse_Result :=
                       Parse (To_String (Resp.Body_Text));
                  begin
                     if PR.Valid then
                        Poll_Succeeded := True;
                        declare
                           Root_Arr : constant JSON_Array_Type :=
                             Value_To_Array (PR.Root);
                        begin
                           for I in 1 .. Array_Length (Root_Arr) loop
                              declare
                                 Item        : constant JSON_Value_Type :=
                                   Array_Item (Root_Arr, I);
                                 Msg_ID      : constant String :=
                                   Get_String (Item, "id");
                                 Chat_ID     : constant String :=
                                   Get_String (Item, "from");
                                 Text        : constant String :=
                                   Get_String (Item, "body");
                                 From_Me     : constant Boolean :=
                                   Get_Boolean (Item, "fromMe", False);
                                 Is_Operator : Boolean := False;
                              begin
                                 --  Skip already-processed messages (client-side dedup)
                                 if Channels.Message_Dedup.Was_Seen (Seen, Msg_ID) then
                                    goto Next_Item;
                                 end if;
                                 Channels.Message_Dedup.Mark_Seen (Seen, Msg_ID);

                                 if not From_Me and then Text'Length > 0 then
                                    --  Allowlist check
                                    declare
                                       Allowlist   : constant String :=
                                         To_String (Chan_Cfg.Allowlist);
                                       Comma       : constant Natural :=
                                         Index (Allowlist, ",");
                                       First_Entry : constant String :=
                                         (if Comma > 0
                                          then Allowlist (Allowlist'First .. Comma - 1)
                                          else Allowlist);
                                    begin
                                       if Allowlist'Length = 0 then
                                          goto Next_Item;
                                       end if;
                                       if Allowlist /= "*"
                                         and then Index (Allowlist, Chat_ID) = 0
                                       then
                                          goto Next_Item;
                                       end if;
                                       --  Operator = first allowlist entry; guest = open-access users.
                                       Is_Operator :=
                                         Allowlist /= "*" and then Chat_ID = First_Entry;
                                    end;

                                    --  Rate limit: enforce Max_RPS per session.
                                    if not Channels.Rate_Limit.Check
                                      ("wa:" & Chat_ID, Chan_Cfg.Max_RPS)
                                    then
                                       goto Next_Item;
                                    end if;

                                    declare
                                       Sess  : constant String :=
                                         (if Is_Operator
                                          then "wa:" & Chat_ID
                                          else "guest-wa-" & Chat_ID);
                                       Conv  : Agent.Context.Conversation;
                                       Reply : Agent.Loop_Pkg.Agent_Reply;
                                    begin
                                       Set_Unbounded_String
                                         (Conv.Session_ID, Sess);
                                       Set_Unbounded_String
                                         (Conv.Channel, "whatsapp:" & Chat_ID);

                                       if Memory.SQLite.Is_Open (Mem) then
                                          Memory.SQLite.Load_History
                                            (Mem, Sess,
                                             Current_Cfg.Memory.Max_History, Conv);
                                       end if;

                                       Metrics.Increment ("requests_total", "whatsapp");

                                       if Is_Operator then
                                          Reply :=
                                            Agent.Loop_Pkg.Process_Message
                                              (User_Input => Text,
                                               Conv       => Conv,
                                               Cfg        => Current_Cfg,
                                               Mem        => Mem);
                                       else
                                          declare
                                             Guest_Cfg : Agent_Config := Current_Cfg;
                                          begin
                                             Set_Unbounded_String
                                               (Guest_Cfg.System_Prompt,
                                                To_String (Current_Cfg.System_Prompt)
                                                & " [Note: You are speaking with a"
                                                & " guest user. Keep responses"
                                                & " helpful but brief.]");
                                             Reply :=
                                               Agent.Loop_Pkg.Process_Message
                                                 (User_Input => Text,
                                                  Conv       => Conv,
                                                  Cfg        => Guest_Cfg,
                                                  Mem        => Mem);
                                          end;
                                       end if;

                                       if Reply.Success then
                                          if not Send_Message
                                            (BU, Default_Session,
                                             Chat_ID, To_String (Reply.Content))
                                          then
                                             Logging.Error
                                               ("WhatsApp: send failed to "
                                                & Chat_ID);
                                          end if;
                                       else
                                          Metrics.Increment ("errors_total", "whatsapp");
                                       end if;
                                    end;
                                 end if;
                                 <<Next_Item>>
                              end;
                           end loop;
                        end;
                     end if;
                  end;
               end if;
            end;

            if Poll_Succeeded then
               Channels.Bridge_Polling.Record_Success (Poll_State);
            else
               Channels.Bridge_Polling.Record_Failure (Poll_State);
            end if;
         exception
            when E : others =>
               Logging.Warning
                 ("WhatsApp: poll error: " & Exception_Message (E));
               Channels.Bridge_Polling.Record_Failure (Poll_State);
         end;
         delay Channels.Bridge_Polling.Current_Delay (Poll_State);
      end loop;
   end Run_Polling;

end Channels.WhatsApp;
