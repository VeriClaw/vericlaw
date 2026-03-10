with AWS.Server;
with AWS.Response;
with AWS.Response.Set;
with AWS.Status;
with AWS.Messages;
with AWS.Config;
with AWS.Config.Set;
with Ada.Calendar;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Build_Info;
with Config.JSON_Parser;    use Config.JSON_Parser;
with Channels.Telegram;
with Channels.Signal;
with Agent.Context;
with Agent.Loop_Pkg;
with Metrics;
with Plugins.Loader;

package body HTTP.Server
  with SPARK_Mode => Off
is
   use Config.Schema;
   use type Agent.Context.Role;

   WS : AWS.Server.HTTP;

   --  Shared state accessed by request handlers.
   type Mem_Ptr is access all Memory.SQLite.Memory_Handle;

   Shared_Cfg     : Config.Schema.Agent_Config;
   Shared_Mem_Ptr : Mem_Ptr := null;

   Start_Time : Ada.Calendar.Time;

   --  -----------------------------------------------------------------------
   --  Local helpers
   --  -----------------------------------------------------------------------

   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   function Kind_To_String (K : Channel_Kind) return String is
   begin
      case K is
         when CLI      => return "cli";
         when Telegram => return "telegram";
         when Signal   => return "signal";
         when WhatsApp => return "whatsapp";
         when Discord  => return "discord";
         when Slack    => return "slack";
         when Email    => return "email";
         when IRC      => return "irc";
         when Matrix   => return "matrix";
         when Mattermost => return "mattermost";
      end case;
   end Kind_To_String;

   function Bool_Image (B : Boolean) return String is
   begin
      if B then return "true"; else return "false"; end if;
   end Bool_Image;

   --  -----------------------------------------------------------------------
   --  Per-IP fixed-window rate limiter (thread-safe via protected object)
   --  -----------------------------------------------------------------------

   Window_Seconds : constant Duration := 60.0;
   Max_Per_Window : constant Natural  := 120;

   type Rate_Entry is record
      IP           : String (1 .. 45);  --  max IPv6 string length
      IP_Len       : Natural := 0;
      Count        : Natural := 0;
      Window_Start : Ada.Calendar.Time;
   end record;
   Max_Rate_Entries : constant := 256;
   type Rate_Entry_Array is array (1 .. Max_Rate_Entries) of Rate_Entry;

   protected Rate_Limiter is
      procedure Check (IP : String; Allowed : out Boolean);
   private
      Entries     : Rate_Entry_Array;
      Num_Entries : Natural := 0;
   end Rate_Limiter;

   protected body Rate_Limiter is
      procedure Check (IP : String; Allowed : out Boolean) is
         use type Ada.Calendar.Time;
         Now       : constant Ada.Calendar.Time := Ada.Calendar.Clock;
         IP_Padded : String (1 .. 45) := (others => ' ');
         Len       : constant Natural :=
           Natural'Min (IP'Length, 45);
      begin
         IP_Padded (1 .. Len) := IP (IP'First .. IP'First + Len - 1);

         for I in 1 .. Num_Entries loop
            if Entries (I).IP_Len = Len
              and then Entries (I).IP (1 .. Len) = IP_Padded (1 .. Len)
            then
               if Now - Entries (I).Window_Start > Window_Seconds then
                  Entries (I).Window_Start := Now;
                  Entries (I).Count := 1;
                  Allowed := True;
               elsif Entries (I).Count < Max_Per_Window then
                  Entries (I).Count := Entries (I).Count + 1;
                  Allowed := True;
               else
                  Allowed := False;
               end if;
               return;
            end if;
         end loop;

         --  New IP — add entry if space remains; allow either way.
         if Num_Entries < Max_Rate_Entries then
            Num_Entries := Num_Entries + 1;
            Entries (Num_Entries).IP := IP_Padded;
            Entries (Num_Entries).IP_Len := Len;
            Entries (Num_Entries).Count := 1;
            Entries (Num_Entries).Window_Start := Now;
         end if;
         Allowed := True;
      end Check;
   end Rate_Limiter;

   --  -----------------------------------------------------------------------
   --  Request dispatcher
   --  -----------------------------------------------------------------------

   function Dispatch
     (Request : AWS.Status.Data) return AWS.Response.Data
   is
      URI    : constant String := AWS.Status.URI (Request);
      Method : constant String := AWS.Status.Method (Request);
      Body_S : constant String := AWS.Status.Payload (Request);

      function Starts_With (Value, Prefix : String) return Boolean is
      begin
         return Value'Length >= Prefix'Length
           and then Value (Value'First .. Value'First + Prefix'Length - 1) =
             Prefix;
      end Starts_With;

      function Is_Localhost return Boolean is
         Addr : constant String := AWS.Status.Peername (Request);
      begin
         return Addr = "127.0.0.1" or else Addr = "::1";
      end Is_Localhost;

      function Allowed_CORS_Origin return String is
         Origin : constant String := AWS.Status.Origin (Request);
      begin
         if Origin = "http://localhost"
           or else Origin = "http://127.0.0.1"
           or else Origin = "http://[::1]"
           or else Starts_With (Origin, "http://localhost:")
           or else Starts_With (Origin, "http://127.0.0.1:")
           or else Starts_With (Origin, "http://[::1]:")
         then
            return Origin;
         end if;

         return "";
      end Allowed_CORS_Origin;

      CORS_Origin : constant String := Allowed_CORS_Origin;

      procedure Restore_Conversation
        (Session_ID : String;
         Conv       : in out Agent.Context.Conversation)
      is
         Loaded : Agent.Context.Conversation;
      begin
         Set_Unbounded_String (Conv.Session_ID, Session_ID);

         if Shared_Mem_Ptr = null
           or else not Memory.SQLite.Is_Open (Shared_Mem_Ptr.all)
         then
            return;
         end if;

         Memory.SQLite.Load_History
           (Shared_Mem_Ptr.all,
            Session_ID,
            Shared_Cfg.Memory.Max_History,
            Loaded);

          if Loaded.Msg_Count = 0 then
             return;
          end if;

          if Loaded.Messages (1).Role = Agent.Context.System_Role then
             Conv := Loaded;
             Set_Unbounded_String (Conv.Session_ID, Session_ID);
             return;
          end if;

          --  Rebuild history with the system prompt first so the browser chat
          --  can reuse a stable session_id without changing provider behavior.
          Agent.Context.Append_Message
            (Conv,
             Agent.Context.System_Role,
             To_String (Shared_Cfg.System_Prompt),
             Limit => Shared_Cfg.Memory.Max_History);

          declare
             Capacity    : constant Natural :=
               Natural (Shared_Cfg.Memory.Max_History);
             Start_Index : Positive := 1;
          begin
             if Loaded.Msg_Count > Capacity - 1 then
                Start_Index :=
                  Positive (Loaded.Msg_Count - (Capacity - 1) + 1);
             end if;

             for I in Start_Index .. Loaded.Msg_Count loop
                if Loaded.Messages (I).Role /= Agent.Context.System_Role then
                   Agent.Context.Append_Message
                     (Conv,
                      Loaded.Messages (I).Role,
                      To_String (Loaded.Messages (I).Content),
                      Name  => To_String (Loaded.Messages (I).Name),
                      Limit => Shared_Cfg.Memory.Max_History);
                end if;
             end loop;
          end;
      end Restore_Conversation;

      function Raw_Dispatch return AWS.Response.Data is
      begin
         if Method = "OPTIONS" then
            declare
               Allowed_Headers : constant String :=
                 AWS.Status.Access_Control_Request_Headers (Request);
               R : AWS.Response.Data :=
                 AWS.Response.Acknowledge
                   ((if CORS_Origin'Length > 0
                     then AWS.Messages.S200
                     else AWS.Messages.S403));
            begin
               if CORS_Origin'Length > 0 then
                  AWS.Response.Set.Add_Header
                    (R, "Access-Control-Allow-Origin", CORS_Origin);
                  AWS.Response.Set.Add_Header (R, "Vary", "Origin");
                  AWS.Response.Set.Add_Header
                    (R, "Access-Control-Allow-Methods", "GET, POST, OPTIONS");
                  AWS.Response.Set.Add_Header
                    (R,
                     "Access-Control-Allow-Headers",
                     (if Allowed_Headers'Length > 0
                      then Allowed_Headers
                      else "Content-Type"));
                  AWS.Response.Set.Add_Header
                    (R, "Access-Control-Max-Age", "600");
               end if;

               return R;
            end;
         end if;

          --  Per-IP rate limiting (skip /health)
         if URI /= "/health" then
            declare
               Allowed : Boolean;
            begin
               Rate_Limiter.Check (AWS.Status.Peername (Request), Allowed);
               if not Allowed then
                  return AWS.Response.Build
                    ("application/json",
                     "{""error"":""rate limit exceeded""}",
                     AWS.Messages.S429);
               end if;
            end;
         end if;

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

         --  Localhost guard for operator API endpoints
          if not Is_Localhost
            and then
              (URI = "/api/status"
               or else URI = "/api/channels"
               or else URI = "/api/plugins"
               or else URI = "/api/metrics/summary")
          then
             return AWS.Response.Build
               ("application/json",
               "{""error"":""forbidden""}",
               AWS.Messages.S403);
          end if;

         --  GET /api/status
         if URI = "/api/status" and then Method = "GET" then
            declare
               use type Ada.Calendar.Time;
               Elapsed : constant Duration :=
                 Ada.Calendar.Clock - Start_Time;
               Uptime   : constant Natural  := Natural (Elapsed);
               Active   : Natural           := 0;
               Registry : constant Plugins.Loader.Plugin_Registry :=
                 Plugins.Loader.Runtime_Registry;
            begin
               for I in 1 .. Shared_Cfg.Num_Channels loop
                  if Shared_Cfg.Channels (I).Enabled then
                     Active := Active + 1;
                  end if;
               end loop;
                return AWS.Response.Build
                  ("application/json",
                   "{""status"":""running"",""version"":"""
                    & Build_Info.Version & ""","
                    & """uptime_s"":" & Img (Uptime) & ","
                    & """channels_active"":" & Img (Active) & ","
                     & """extensibility_model"":"""
                     & Plugins.Loader.Extensibility_Model & ""","
                     & """local_plugin_mode"":"""
                     & Plugins.Loader.Local_Plugin_Mode & ""","
                     & """local_plugin_load_policy"":"""
                     & Plugins.Loader.Local_Load_Policy & ""","
                     & """mcp_bridge_configured"":"
                     & Bool_Image (Length (Shared_Cfg.Tools.MCP_Bridge_URL) > 0)
                     & ","
                     & """plugins_discovered"":" & Img (Registry.Num_Loaded) & ","
                     & """plugins_loaded"":" &
                       Img (Plugins.Loader.Loaded_Plugin_Count (Registry)) & ","
                     & """plugins_denied"":" &
                       Img (Plugins.Loader.Denied_Plugin_Count (Registry)) & ","
                     & """plugins_errors"":" &
                       Img (Plugins.Loader.Error_Plugin_Count (Registry))
                     & "}",
                     AWS.Messages.S200);
            end;
         end if;

         --  GET /api/channels
          if URI = "/api/channels" and then Method = "GET" then
             declare
                Result : Unbounded_String;
             begin
               Set_Unbounded_String (Result, "{""channels"":[");
               for I in 1 .. Shared_Cfg.Num_Channels loop
                  if I > 1 then
                     Append (Result, ",");
                  end if;
                  Append (Result,
                    "{""kind"":"""
                    & Kind_To_String (Shared_Cfg.Channels (I).Kind) & ""","
                    & """enabled"":"
                    & Bool_Image (Shared_Cfg.Channels (I).Enabled) & ","
                    & """max_rps"":"
                    & Img (Natural (Shared_Cfg.Channels (I).Max_RPS)) & "}");
               end loop;
               Append (Result, "]}");
               return AWS.Response.Build
                  ("application/json", To_String (Result), AWS.Messages.S200);
             end;
          end if;

          --  GET /api/plugins
          if URI = "/api/plugins" and then Method = "GET" then
             return AWS.Response.Build
               ("application/json",
                "{""extensibility_model"":"""
                & Plugins.Loader.Extensibility_Model & ""","
                & """local_plugin_mode"":"""
                & Plugins.Loader.Local_Plugin_Mode & ""","
                & """local_plugin_load_policy"":"""
                & Plugins.Loader.Local_Load_Policy & ""","
                & """mcp_bridge_configured"":"
                & Bool_Image (Length (Shared_Cfg.Tools.MCP_Bridge_URL) > 0)
                & ","
                & """local_plugins"":"
                & Plugins.Loader.Runtime_Registry_JSON
                & "}",
                AWS.Messages.S200);
          end if;

          --  GET /api/metrics/summary
          if URI = "/api/metrics/summary" and then Method = "GET" then
            declare
               Prov_Req : constant Natural :=
                 Metrics.Get_Counter ("provider_requests_total", "*");
               Prov_Err : constant Natural :=
                 Metrics.Get_Counter ("provider_errors_total", "*");
               Tool_C   : constant Natural :=
                 Metrics.Get_Counter ("tool_calls_total", "*");
            begin
               return AWS.Response.Build
                 ("application/json",
                  "{""provider_requests_total"":" & Img (Prov_Req) & ","
                  & """provider_errors_total"":" & Img (Prov_Err) & ","
                  & """tool_calls_total"":" & Img (Tool_C) & "}",
                  AWS.Messages.S200);
            end;
          end if;

          --  POST /api/chat — non-streaming chat completion
         if URI = "/api/chat" and then Method = "POST" then
            if not Is_Localhost then
               return AWS.Response.Build
                 ("application/json",
                  "{""error"":""forbidden""}",
                  AWS.Messages.S403);
            end if;

            declare
               PR : constant Config.JSON_Parser.Parse_Result :=
                 Config.JSON_Parser.Parse (Body_S);
            begin
               if not PR.Valid
                 or else not Config.JSON_Parser.Has_Key (PR.Root, "message")
               then
                  return AWS.Response.Build
                    ("application/json",
                     "{""error"":""missing 'message' field""}",
                     AWS.Messages.S400);
               end if;

                declare
                   Msg   : constant String :=
                     Config.JSON_Parser.Get_String (PR.Root, "message");
                   SID   : constant String :=
                     (if Config.JSON_Parser.Has_Key (PR.Root, "session_id")
                      then Config.JSON_Parser.Get_String (PR.Root, "session_id")
                      else "gateway");
                   Conv  : Agent.Context.Conversation;
                   Reply : Agent.Loop_Pkg.Agent_Reply;
                begin
                   Restore_Conversation (SID, Conv);
                   Reply := Agent.Loop_Pkg.Process_Message
                     (Msg, Conv, Shared_Cfg, Shared_Mem_Ptr.all);

                   if Reply.Success then
                      return AWS.Response.Build
                       ("application/json",
                        "{""content"":" & Config.JSON_Parser.Escape_JSON_String
                          (To_String (Reply.Content)) & "}",
                        AWS.Messages.S200);
                   else
                     return AWS.Response.Build
                       ("application/json",
                        "{""error"":" & Config.JSON_Parser.Escape_JSON_String
                          (To_String (Reply.Error)) & "}",
                        AWS.Messages.S500);
                   end if;
                end;
            end;
         end if;

         --  POST /api/chat/stream — SSE-framed chat completion.
         --  Today this is buffered pseudo-SSE: the provider path may stream
         --  internally, but AWS still returns one completed HTTP response.
         --  Keep the wire format explicit so browser clients can be honest
         --  about the limitation instead of faking token-by-token output.
         if URI = "/api/chat/stream" and then Method = "POST" then
            if not Is_Localhost then
               return AWS.Response.Build
                  ("application/json",
                   "{""error"":""forbidden""}",
                  AWS.Messages.S403);
            end if;

            declare
               PR : constant Config.JSON_Parser.Parse_Result :=
                 Config.JSON_Parser.Parse (Body_S);
            begin
               if not PR.Valid
                 or else not Config.JSON_Parser.Has_Key (PR.Root, "message")
               then
                  return AWS.Response.Build
                    ("application/json",
                     "{""error"":""missing 'message' field""}",
                     AWS.Messages.S400);
               end if;

                declare
                   Msg   : constant String :=
                     Config.JSON_Parser.Get_String (PR.Root, "message");
                   SID   : constant String :=
                     (if Config.JSON_Parser.Has_Key (PR.Root, "session_id")
                      then Config.JSON_Parser.Get_String (PR.Root, "session_id")
                      else "gateway");
                   Conv  : Agent.Context.Conversation;
                   Reply : Agent.Loop_Pkg.Agent_Reply;
                   SSE   : Unbounded_String;
                begin
                   Restore_Conversation (SID, Conv);
                   Reply := Agent.Loop_Pkg.Process_Message_Streaming
                     (Msg, Conv, Shared_Cfg, Shared_Mem_Ptr.all);

                   --  Build buffered SSE payload: one data event with the full
                   --  content, then a [DONE] sentinel.
                   if Reply.Success then
                      Append (SSE, "data: {""content"":");
                      Append (SSE, Config.JSON_Parser.Escape_JSON_String
                        (To_String (Reply.Content)));
                      Append (SSE, "}" & ASCII.LF & ASCII.LF);
                     Append (SSE, "data: [DONE]" & ASCII.LF & ASCII.LF);
                   else
                     Append (SSE, "data: {""error"":");
                     Append (SSE, Config.JSON_Parser.Escape_JSON_String
                       (To_String (Reply.Error)));
                     Append (SSE, "}" & ASCII.LF & ASCII.LF);
                   end if;

                   declare
                      R : AWS.Response.Data :=
                        AWS.Response.Build
                          ("text/event-stream",
                           To_String (SSE),
                           AWS.Messages.S200);
                   begin
                      AWS.Response.Set.Add_Header
                        (R, "X-VeriClaw-Stream-Mode", "buffered-sse");
                      return R;
                   end;
                end;
            end;
         end if;

         --  404 for everything else
         return AWS.Response.Build
           ("application/json",
            "{""error"":""not found""}",
            AWS.Messages.S404);
      end Raw_Dispatch;

      R : AWS.Response.Data := Raw_Dispatch;
   begin
       AWS.Response.Set.Add_Header (R, "X-Content-Type-Options", "nosniff");
       AWS.Response.Set.Add_Header (R, "X-Frame-Options", "DENY");
       AWS.Response.Set.Add_Header (R, "Cache-Control", "no-store");
       if Method /= "OPTIONS" and then CORS_Origin'Length > 0 then
          AWS.Response.Set.Add_Header
            (R, "Access-Control-Allow-Origin", CORS_Origin);
          AWS.Response.Set.Add_Header (R, "Vary", "Origin");
          AWS.Response.Set.Add_Header
            (R, "Access-Control-Expose-Headers", "X-VeriClaw-Stream-Mode");
       end if;
       return R;
   end Dispatch;

   procedure Run
     (Cfg : Config.Schema.Agent_Config;
      Mem : aliased in out Memory.SQLite.Memory_Handle)
   is
      AWS_Cfg : AWS.Config.Object := AWS.Config.Get_Current;
      Host    : constant String := To_String (Cfg.Gateway.Bind_Host);
      Port    : constant Positive := Cfg.Gateway.Bind_Port;
   begin
      Start_Time := Ada.Calendar.Clock;
      Shared_Cfg := Cfg;
      Shared_Mem_Ptr := Mem'Unchecked_Access;

      AWS.Config.Set.Server_Host (AWS_Cfg, Host);
      AWS.Config.Set.Server_Port (AWS_Cfg, Port);
      AWS.Config.Set.Max_Connection (AWS_Cfg, Cfg.Gateway.Max_Connections);
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
