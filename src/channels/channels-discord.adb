with Logging;
with Ada.Exceptions; use Ada.Exceptions;
with HTTP.Client;
with Config.JSON_Parser; use Config.JSON_Parser;
with Agent.Context;
with Agent.Loop_Pkg;
with Ada.Strings.Fixed;  use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Channels.Bridge_Polling;
with Channels.Security;
with Channels.Rate_Limit;
with Channels.Message_Dedup;
package body Channels.Discord
  with SPARK_Mode => Off
is
   use Config.Schema;

   Seen : Channels.Message_Dedup.Dedup_Buffer;

   function Send_Message
     (Bridge_URL : String;
      Channel_ID : String;
      Content    : String;
      Reply_To   : String) return Boolean
   is
      Body_Obj : JSON_Value_Type := Build_Object;
      Resp     : HTTP.Client.Response;
   begin
      Set_Field (Body_Obj, "channel_id", Channel_ID);
      Set_Field (Body_Obj, "content",    Content);
      Set_Field (Body_Obj, "reply_to",   Reply_To);

      Resp := HTTP.Client.Post_JSON
        (URL       => Bridge_URL & "/sessions/discord/messages",
         Headers   => [1 .. 0 => <>],
         Body_JSON => To_JSON_String (Body_Obj));

      return HTTP.Client.Is_Success (Resp);
   end Send_Message;

   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle)
   is
      Chan_Cfg   : constant Config.Schema.Channel_Config :=
        Find_Channel (Cfg, Config.Schema.Discord);
      Bridge_URL : constant String := To_String (Chan_Cfg.Bridge_URL);
      Poll_State : Channels.Bridge_Polling.Backoff_State;
   begin
      if not Chan_Cfg.Enabled or else Bridge_URL'Length = 0 then
         Logging.Info ("Discord: not configured, skipping.");
         return;
      end if;

      Channels.Bridge_Polling.Initialize
        (Poll_State, Base_Delay => 2.0, Max_Delay => 30.0);

      Logging.Info ("Discord: polling " & Bridge_URL & " ...");

      loop
         declare
            Poll_Succeeded : Boolean := False;
         begin
            declare
               Resp : constant HTTP.Client.Response :=
                 HTTP.Client.Get
                   (URL        => Bridge_URL
                      & "/sessions/discord/messages?limit=10",
                    Headers    => [1 .. 0 => <>],
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
                                 Item       : constant JSON_Value_Type :=
                                   Array_Item (Root_Arr, I);
                                 Msg_ID     : constant String :=
                                   Get_String (Item, "id");
                                 From       : constant String :=
                                   Get_String (Item, "from");
                                 Channel_ID : constant String :=
                                   Get_String (Item, "channel_id");
                                 Guild_ID   : constant String :=
                                   Get_String (Item, "guild_id");
                                 Text       : constant String :=
                                   Get_String (Item, "content");
                              begin
                                 --  Skip already-processed messages (client-side dedup)
                                 if Channels.Message_Dedup.Was_Seen (Seen, Msg_ID) then
                                    goto Next_Item;
                                 end if;
                                 Channels.Message_Dedup.Mark_Seen (Seen, Msg_ID);

                                 if Text'Length > 0 then
                                    --  Allowlist check via SPARK-proved policy.
                                    declare
                                       Allowlist : constant String :=
                                         To_String (Chan_Cfg.Allowlist);
                                       Matches   : constant Boolean :=
                                         Allowlist = "*"
                                         or else Index (Allowlist, From) > 0;
                                    begin
                                       if not Channels.Security.Allowlist_Allows
                                         (Channel           =>
                                            Channels.Security.Discord_Channel,
                                          Allowlist_Size    => Allowlist'Length,
                                          Candidate_Matches => Matches)
                                       then
                                          goto Next_Item;
                                       end if;
                                    end;

                                    --  Rate limit: enforce Max_RPS per user.
                                    if not Channels.Rate_Limit.Check
                                      ("discord:" & From, Chan_Cfg.Max_RPS)
                                    then
                                       goto Next_Item;
                                    end if;

                                    declare
                                       Session_ID : constant String :=
                                         "discord-" & Guild_ID & "-" & Channel_ID;
                                       Conv  : Agent.Context.Conversation;
                                       Reply : Agent.Loop_Pkg.Agent_Reply;
                                    begin
                                       Set_Unbounded_String
                                         (Conv.Session_ID, Session_ID);
                                       Set_Unbounded_String
                                         (Conv.Channel,
                                          "discord:" & Guild_ID & ":" & Channel_ID);

                                       if Memory.SQLite.Is_Open (Mem) then
                                          Memory.SQLite.Load_History
                                            (Mem, Session_ID,
                                             Cfg.Memory.Max_History, Conv);
                                       end if;

                                       Reply :=
                                         Agent.Loop_Pkg.Process_Message
                                           (User_Input => Text,
                                            Conv       => Conv,
                                            Cfg        => Cfg,
                                            Mem        => Mem);

                                       if Reply.Success then
                                          if not Send_Message
                                            (Bridge_URL, Channel_ID,
                                             To_String (Reply.Content), Msg_ID)
                                          then
                                             Logging.Error
                                               ("Discord: send failed to channel "
                                                & Channel_ID);
                                          end if;
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
                 ("Discord: poll error: " & Exception_Message (E));
               Channels.Bridge_Polling.Record_Failure (Poll_State);
         end;
         delay Channels.Bridge_Polling.Current_Delay (Poll_State);
      end loop;
   end Run_Polling;

end Channels.Discord;
