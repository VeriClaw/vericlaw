with AWS.Server;
with AWS.Response;
with AWS.Status;
with AWS.Messages;
with AWS.Config;
with AWS.Config.Set;
with Ada.Text_IO;
with Config.JSON_Parser;
with Config.Schema;      use Config.Schema;
with Channels.Telegram;
with Channels.Signal;
with Channels.WhatsApp;
with Metrics;

pragma SPARK_Mode (Off);
package body HTTP.Server is

   WS : AWS.Server.HTTP;

   --  Shared state accessed by request handlers.
   type Mem_Ptr is access all Memory.SQLite.Memory_Handle;

   Shared_Cfg     : Config.Schema.Agent_Config;
   Shared_Mem_Ptr : Mem_Ptr := null;

   --  -----------------------------------------------------------------------
   --  Request dispatcher
   --  -----------------------------------------------------------------------

   function Dispatch
     (Request : AWS.Status.Data) return AWS.Response.Data
   is
      URI    : constant String := AWS.Status.URI (Request);
      Method : constant String := AWS.Status.Method (Request);
      Body_S : constant String := AWS.Status.Payload (Request);
   begin
      --  Health check
      if URI = "/health" and then Method = "GET" then
         return AWS.Response.Build
           ("application/json",
            "{""status"":""ok"",""service"":""vericlaw""}",
            AWS.Messages.S200);
      end if;

      --  Telegram webhook
      if URI = "/webhook/telegram" and then Method = "POST" then
         declare
            Reply_Text : constant String :=
              Channels.Telegram.Process_Update
                (Body_S, Shared_Cfg, Shared_Mem_Ptr.all);
            --  Reply text is sent proactively by the handler; return 200.
         begin
            if Reply_Text'Length > 0 then
               --  Extract chat_id from body to send reply.
               declare
                  PR      : constant Config.JSON_Parser.Parse_Result :=
                    Config.JSON_Parser.Parse (Body_S);
                  Chat_ID : Unbounded_String;
               begin
                  if PR.Valid
                    and then Config.JSON_Parser.Has_Key (PR.Root, "message")
                  then
                     declare
                        Msg  : constant Config.JSON_Parser.JSON_Value_Type :=
                          Config.JSON_Parser.Get_Object (PR.Root, "message");
                        Chat : constant Config.JSON_Parser.JSON_Value_Type :=
                          Config.JSON_Parser.Get_Object (Msg, "chat");
                     begin
                        Set_Unbounded_String
                          (Chat_ID,
                           Config.JSON_Parser.Get_String (Chat, "id"));
                     end;
                  end if;

                  if Length (Chat_ID) > 0 then
                     for I in 1 .. Shared_Cfg.Num_Channels loop
                        if Shared_Cfg.Channels (I).Kind =
                          Config.Schema.Telegram
                        then
                           declare
                              Token : constant String :=
                                To_String
                                  (Shared_Cfg.Channels (I).Token);
                           begin
                              if not Channels.Telegram.Send_Message
                                (Token, To_String (Chat_ID), Reply_Text)
                              then
                                 Ada.Text_IO.Put_Line
                                   ("Webhook: Telegram send failed");
                              end if;
                           end;
                           exit;
                        end if;
                     end loop;
                  end if;
               end;
            end if;
         end;
         return AWS.Response.Build
           ("application/json",
            "{""ok"":true}",
            AWS.Messages.S200);
      end if;

      --  Signal webhook (signal-cli can push to a URL)
      if URI = "/webhook/signal" and then Method = "POST" then
         declare
            Chan_Cfg : Config.Schema.Channel_Config;
         begin
            for I in 1 .. Shared_Cfg.Num_Channels loop
               if Shared_Cfg.Channels (I).Kind = Config.Schema.Signal then
                  Chan_Cfg := Shared_Cfg.Channels (I);
                  exit;
               end if;
            end loop;

            declare
               Reply_Text : constant String :=
                 Channels.Signal.Process_Message_JSON
                   (Body_S, Shared_Cfg, Shared_Mem_Ptr.all);
            begin
               if Reply_Text'Length > 0 then
                  declare
                     PR     : constant Config.JSON_Parser.Parse_Result :=
                       Config.JSON_Parser.Parse (Body_S);
                     Source : Unbounded_String;
                  begin
                     if PR.Valid then
                        declare
                           Env : constant Config.JSON_Parser.JSON_Value_Type :=
                             Config.JSON_Parser.Get_Object (PR.Root, "envelope");
                        begin
                           Set_Unbounded_String
                             (Source,
                              Config.JSON_Parser.Get_String (Env, "source"));
                        end;
                     end if;

                     if Length (Source) > 0 then
                        declare
                           OK : Boolean;
                           pragma Unreferenced (OK);
                        begin
                           OK := Channels.Signal.Send_Message
                             (To_String (Chan_Cfg.Bridge_URL),
                              To_String (Chan_Cfg.Token),
                              To_String (Source),
                              Reply_Text);
                        end;
                     end if;
                  end;
               end if;
            end;
         end;
         return AWS.Response.Build
           ("application/json",
            "{""ok"":true}", AWS.Messages.S200);
      end if;

      --  Prometheus metrics
      if URI = "/metrics" and then Method = "GET" then
         return AWS.Response.Build
           ("text/plain; version=0.0.4",
            Metrics.Render,
            AWS.Messages.S200);
      end if;

      --  404 for everything else
      return AWS.Response.Build
        ("application/json",
         "{""error"":""not found""}",
         AWS.Messages.S404);
   end Dispatch;

   procedure Run
     (Cfg : Config.Schema.Agent_Config;
      Mem : aliased in out Memory.SQLite.Memory_Handle)
   is
      AWS_Cfg : AWS.Config.Object := AWS.Config.Get_Current;
      Host    : constant String := To_String (Cfg.Gateway.Bind_Host);
      Port    : constant Positive := Cfg.Gateway.Bind_Port;
   begin
      Shared_Cfg := Cfg;
      Shared_Mem_Ptr := Mem'Unchecked_Access;

      AWS.Config.Set.Server_Host (AWS_Cfg, Host);
      AWS.Config.Set.Server_Port (AWS_Cfg, Port);
      AWS.Config.Set.Max_Connection (AWS_Cfg, 64);
      AWS.Config.Set.Session (AWS_Cfg, False);

      Ada.Text_IO.Put_Line
        ("Gateway: listening on " & Host & ":" & Positive'Image (Port));

      AWS.Server.Start (WS, Dispatch'Access, AWS_Cfg);
      AWS.Server.Wait (AWS.Server.Q_Key_Pressed);
   end Run;

   procedure Stop is
   begin
      AWS.Server.Shutdown (WS);
   end Stop;

end HTTP.Server;
