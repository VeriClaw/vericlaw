with Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HTTP.Client;
with Config.JSON_Parser; use Config.JSON_Parser;
with Config.Schema;      use Config.Schema;
with Config.Loader;
with Config.Reload;
with Agent.Context;
with Agent.Loop_Pkg;
with Ada.Strings.Fixed;  use Ada.Strings.Fixed;
with Channels.Rate_Limit;

package body Channels.Matrix is

   --  Client-side dedup: track last 100 message IDs.
   Max_Seen_IDs : constant := 100;
   type Seen_Index is mod Max_Seen_IDs;
   type Seen_Array is array (Seen_Index) of Unbounded_String;
   Seen_IDs  : Seen_Array;
   Seen_Next : Seen_Index := 0;

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
         if Cfg.Channels (I).Kind = Config.Schema.Matrix then
            return Cfg.Channels (I);
         end if;
      end loop;
      return (Kind => Config.Schema.Matrix, others => <>);
   end Get_Chan_Config;

   function Send_Message
     (Bridge_URL : String;
      Room       : String;
      Text       : String) return Boolean
   is
      Body_Obj : JSON_Value_Type := Build_Object;
      Resp     : HTTP.Client.Response;
   begin
      Set_Field (Body_Obj, "room", Room);
      Set_Field (Body_Obj, "text", Text);

      Resp := HTTP.Client.Post_JSON
        (URL       => Bridge_URL & "/sessions/matrix/messages",
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
        Get_Chan_Config (Current_Cfg);
      Bridge_URL  : Unbounded_String :=
        Chan_Cfg.Bridge_URL;
   begin
      if not Chan_Cfg.Enabled or else Length (Bridge_URL) = 0 then
         Ada.Text_IO.Put_Line ("Matrix: not configured, skipping.");
         return;
      end if;

      Ada.Text_IO.Put_Line
        ("Matrix: polling " & To_String (Bridge_URL) & " ...");

      loop
         --  Check for SIGHUP-triggered config reload.
         if Config.Reload.Is_Requested then
            declare
               New_CR : constant Config.Loader.Load_Result :=
                 Config.Loader.Load;
            begin
               if New_CR.Success then
                  Current_Cfg := New_CR.Config;
                  Chan_Cfg    := Get_Chan_Config (Current_Cfg);
                  Bridge_URL  := Chan_Cfg.Bridge_URL;
                  Ada.Text_IO.Put_Line ("Config reloaded.");
               end if;
            end;
            Config.Reload.Acknowledge;
         end if;

         declare
            BU   : constant String := To_String (Bridge_URL);
            Resp : constant HTTP.Client.Response :=
              HTTP.Client.Get
                (URL        => BU & "/sessions/matrix/messages?limit=10",
                 Headers    => (1 .. 0 => <>),
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
                           Item   : constant JSON_Value_Type :=
                             Array_Item (Root_Arr, I);
                           Msg_ID : constant String :=
                             Get_String (Item, "id");
                           Sender : constant String :=
                             Get_String (Item, "from");
                           Room   : constant String :=
                             Get_String (Item, "room");
                           Text   : constant String :=
                             Get_String (Item, "text");
                        begin
                           --  Skip already-processed messages.
                           if Was_Seen (Msg_ID) then
                              goto Next_Item;
                           end if;
                           Mark_Seen (Msg_ID);

                           if Sender'Length > 0 and then Text'Length > 0 then
                              --  Allowlist check.
                              declare
                                 Allowlist : constant String :=
                                   To_String (Chan_Cfg.Allowlist);
                              begin
                                 if Allowlist'Length = 0 then
                                    goto Next_Item;
                                 end if;
                                 if Allowlist /= "*"
                                   and then Index (Allowlist, Sender) = 0
                                 then
                                    goto Next_Item;
                                 end if;
                              end;

                              --  Rate limit: enforce Max_RPS per sender.
                              if not Channels.Rate_Limit.Check
                                ("matrix:" & Sender, Chan_Cfg.Max_RPS)
                              then
                                 goto Next_Item;
                              end if;

                              declare
                                 Conv  : Agent.Context.Conversation;
                                 Reply : Agent.Loop_Pkg.Agent_Reply;
                              begin
                                 Set_Unbounded_String
                                   (Conv.Session_ID,
                                    "matrix:" & Room & ":" & Sender);
                                 Set_Unbounded_String
                                   (Conv.Channel, "matrix:" & Room);

                                 if Memory.SQLite.Is_Open (Mem) then
                                    Memory.SQLite.Load_History
                                      (Mem,
                                       "matrix:" & Room & ":" & Sender,
                                       Current_Cfg.Memory.Max_History, Conv);
                                 end if;

                                 Reply :=
                                   Agent.Loop_Pkg.Process_Message
                                     (User_Input => Text,
                                      Conv       => Conv,
                                      Cfg        => Current_Cfg,
                                      Mem        => Mem);

                                 if Reply.Success then
                                    if not Send_Message
                                      (BU, Room,
                                       To_String (Reply.Content))
                                    then
                                       Ada.Text_IO.Put_Line
                                         ("Matrix: send failed to " & Room);
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

end Channels.Matrix;
