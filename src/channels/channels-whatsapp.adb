with Ada.Text_IO;
with HTTP.Client;
with Config.JSON_Parser; use Config.JSON_Parser;
with Agent.Context;
with Agent.Loop_Pkg;
with Ada.Strings.Fixed;  use Ada.Strings.Fixed;

package body Channels.WhatsApp is

   Default_Session : constant String := "quasar";

   function Get_Chan_Config
     (Cfg : Config.Schema.Agent_Config)
      return Config.Schema.Channel_Config
   is
   begin
      for I in 1 .. Cfg.Num_Channels loop
         if Cfg.Channels (I).Kind = Config.Schema.WhatsApp then
            return Cfg.Channels (I);
         end if;
      end loop;
      return (Kind => Config.Schema.WhatsApp, others => <>);
   end Get_Chan_Config;

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
      Chan_Cfg   : constant Config.Schema.Channel_Config :=
        Get_Chan_Config (Cfg);
      Bridge_URL : constant String := To_String (Chan_Cfg.Bridge_URL);
   begin
      if not Chan_Cfg.Enabled or else Bridge_URL'Length = 0 then
         Ada.Text_IO.Put_Line ("WhatsApp: not configured, skipping.");
         return;
      end if;

      Ada.Text_IO.Put_Line ("WhatsApp: polling " & Bridge_URL & " ...");

      loop
         declare
            Resp : constant HTTP.Client.Response :=
              HTTP.Client.Get
                (URL       => Bridge_URL & "/sessions/"
                  & Default_Session & "/messages?limit=10",
                 Headers   => (1 .. 0 => <>),
                 Timeout_Ms => 10_000);
         begin
            if HTTP.Client.Is_Success (Resp) then
               declare
                  PR : constant Parse_Result :=
                    Parse (To_String (Resp.Body_Text));
               begin
                  if PR.Valid then
                     for I in 1 .. Integer (PR.Root.Length) loop
                        declare
                           Item    : constant JSON_Value_Type :=
                             PR.Root.Get (I);
                           Chat_ID : constant String :=
                             Get_String (Item, "from");
                           Text    : constant String :=
                             Get_String
                               (Get_Object (Item, "body"), "text");
                           From_Me : constant Boolean :=
                             Get_Boolean (Item, "fromMe", False);
                        begin
                           if not From_Me and then Text'Length > 0 then
                              --  Allowlist check
                              declare
                                 Allowlist : constant String :=
                                   To_String (Chan_Cfg.Allowlist);
                              begin
                                 if Allowlist'Length = 0 then
                                    goto Next_Item;
                                 end if;
                                 if Allowlist /= "*"
                                   and then Index (Allowlist, Chat_ID) = 0
                                 then
                                    goto Next_Item;
                                 end if;
                              end;

                              declare
                                 Conv  : Agent.Context.Conversation;
                                 Reply : Agent.Loop_Pkg.Agent_Reply;
                              begin
                                 Set_Unbounded_String
                                   (Conv.Session_ID, "wa:" & Chat_ID);
                                 Set_Unbounded_String
                                   (Conv.Channel, "whatsapp:" & Chat_ID);

                                 if Mem.Open then
                                    Memory.SQLite.Load_History
                                      (Mem, "wa:" & Chat_ID,
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
                                      (Bridge_URL, Default_Session,
                                       Chat_ID, To_String (Reply.Content))
                                    then
                                       Ada.Text_IO.Put_Line
                                         ("WhatsApp: send failed to "
                                          & Chat_ID);
                                    end if;
                                 end if;
                              end;
                           end if;
                           <<Next_Item>>
                        end;
                     end loop;
                  end if;
               end;
            end if;
         end;
         delay 2.0;
      end loop;
   end Run_Polling;

end Channels.WhatsApp;
