with Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HTTP.Client;
with Config.JSON_Parser; use Config.JSON_Parser;
with Config.Schema;      use Config.Schema;
with Agent.Context;
with Agent.Loop_Pkg;
with Ada.Strings.Fixed;  use Ada.Strings.Fixed;
with Channels.Rate_Limit;

pragma SPARK_Mode (Off);
package body Channels.Slack is

   --  Client-side dedup: track last 100 message IDs to guard against
   --  re-delivery if the bridge buffer is not fully drained each poll.
   Max_Seen_IDs : constant := 100;
   type Seen_Index is mod Max_Seen_IDs;
   type Seen_Array is array (Seen_Index) of Unbounded_String;
   Seen_IDs   : Seen_Array;
   Seen_Next  : Seen_Index := 0;

   function Was_Seen (Msg_ID : String) return Boolean is
   begin
      for S of Seen_IDs loop
         if To_String (S) = Msg_ID then
            return True;
         end if;
      end loop;
      return False;
   end Was_Seen;

   procedure Mark_Seen (Msg_ID : String) is
   begin
      Set_Unbounded_String (Seen_IDs (Seen_Next), Msg_ID);
      Seen_Next := Seen_Next + 1;
   end Mark_Seen;

   function Get_Chan_Config
     (Cfg : Config.Schema.Agent_Config)
      return Config.Schema.Channel_Config
   is
   begin
      for I in 1 .. Cfg.Num_Channels loop
         if Cfg.Channels (I).Kind = Config.Schema.Slack then
            return Cfg.Channels (I);
         end if;
      end loop;
      return (Kind => Config.Schema.Slack, others => <>);
   end Get_Chan_Config;

   function Send_Message
     (Bridge_URL : String;
      Chan_ID    : String;
      Text       : String;
      Thread_TS  : String) return Boolean
   is
      Body_Obj : JSON_Value_Type := Build_Object;
      Resp     : HTTP.Client.Response;
   begin
      Set_Field (Body_Obj, "channel",   Chan_ID);
      Set_Field (Body_Obj, "text",      Text);
      Set_Field (Body_Obj, "thread_ts", Thread_TS);

      Resp := HTTP.Client.Post_JSON
        (URL       => Bridge_URL & "/sessions/slack/messages",
         Headers   => (1 .. 0 => <>),
         Body_JSON => To_JSON_String (Body_Obj));

      return HTTP.Client.Is_Success (Resp);
   end Send_Message;

   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle)
   is
      Chan_Cfg   : constant Config.Schema.Channel_Config :=
        Get_Chan_Config (Cfg);
      Bridge_URL : constant String := To_String (Chan_Cfg.Bridge_URL);
   begin
      if not Chan_Cfg.Enabled or else Bridge_URL'Length = 0 then
         Ada.Text_IO.Put_Line ("Slack: not configured, skipping.");
         return;
      end if;

      Ada.Text_IO.Put_Line ("Slack: polling " & Bridge_URL & " ...");

      loop
         declare
            Resp : constant HTTP.Client.Response :=
              HTTP.Client.Get
                (URL       => Bridge_URL & "/sessions/slack/messages?limit=10",
                 Headers   => (1 .. 0 => <>),
                 Timeout_Ms => 10_000);
         begin
            if HTTP.Client.Is_Success (Resp) then
               declare
                  PR : constant Parse_Result :=
                    Parse (To_String (Resp.Body_Text));
               begin
                  if PR.Valid then
                     declare
                        Root_Arr : constant JSON_Array_Type :=
                          Value_To_Array (PR.Root);
                     begin
                        for I in 1 .. Array_Length (Root_Arr) loop
                        declare
                           Item      : constant JSON_Value_Type :=
                             Array_Item (Root_Arr, I);
                           Msg_ID    : constant String :=
                             Get_String (Item, "id");
                           From_User : constant String :=
                             Get_String (Item, "from");
                           Chan_ID   : constant String :=
                             Get_String (Item, "channel");
                           Text      : constant String :=
                             Get_String (Item, "text");
                           Thread_TS : constant String :=
                             Get_String (Item, "thread_ts");
                        begin
                           --  Skip already-processed messages (client-side dedup)
                           if Was_Seen (Msg_ID) then
                              goto Next_Item;
                           end if;
                           Mark_Seen (Msg_ID);

                           if Text'Length > 0 then
                              --  Allowlist check
                              declare
                                 Allowlist : constant String :=
                                   To_String (Chan_Cfg.Allowlist);
                              begin
                                 if Allowlist'Length = 0 then
                                    goto Next_Item;
                                 end if;
                                 if Allowlist /= "*"
                                   and then Index (Allowlist, From_User) = 0
                                 then
                                    goto Next_Item;
                                 end if;
                              end;

                              --  Rate limit: enforce Max_RPS per user.
                              if not Channels.Rate_Limit.Check
                                ("slack:" & From_User, Chan_Cfg.Max_RPS)
                              then
                                 goto Next_Item;
                              end if;

                              declare
                                 Conv  : Agent.Context.Conversation;
                                 Reply : Agent.Loop_Pkg.Agent_Reply;
                              begin
                                 Set_Unbounded_String
                                   (Conv.Session_ID, "slack:" & From_User);
                                 Set_Unbounded_String
                                   (Conv.Channel, "slack:" & Chan_ID);

                                 if Memory.SQLite.Is_Open (Mem) then
                                    Memory.SQLite.Load_History
                                      (Mem, "slack:" & From_User,
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
                                      (Bridge_URL, Chan_ID,
                                       To_String (Reply.Content), Thread_TS)
                                    then
                                       Ada.Text_IO.Put_Line
                                         ("Slack: send failed to "
                                          & Chan_ID);
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
         delay 2.0;
      end loop;
   end Run_Polling;

end Channels.Slack;
