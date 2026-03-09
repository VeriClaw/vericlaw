with Logging;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with HTTP.Client;
with Config.JSON_Parser; use Config.JSON_Parser;
with Config.Loader;
with Config.Reload;
with Agent.Context;
with Agent.Loop_Pkg;
with Ada.Strings.Fixed;  use Ada.Strings.Fixed;
with Channels.Rate_Limit;
with Metrics;

package body Channels.Signal
  with SPARK_Mode => Off
is
   use Config.Schema;

   function Send_Message
     (Bridge_URL  : String;
      Sender      : String;
      Recipient   : String;
      Message     : String) return Boolean
   is
      --  signal-cli REST: POST /v1/send
      Body_Obj  : JSON_Value_Type := Build_Object;
      Recips    : JSON_Value_Type := Build_Array;
      Resp      : HTTP.Client.Response;
   begin
      Append_Array (Recips, Recipient);
      Set_Field (Body_Obj, "message",    Message);
      Set_Field (Body_Obj, "number",     Sender);
      Set_Field (Body_Obj, "recipients", Recips);

      Resp := HTTP.Client.Post_JSON
        (URL       => Bridge_URL & "/v1/send",
         Headers   => [1 .. 0 => <>],
         Body_JSON => To_JSON_String (Body_Obj));

      return HTTP.Client.Is_Success (Resp);
   end Send_Message;

   function Process_Message_JSON
     (Msg_JSON : String;
      Cfg      : Config.Schema.Agent_Config;
      Mem      : Memory.SQLite.Memory_Handle) return String
   is
      PR      : constant Parse_Result := Parse (Msg_JSON);
      Chan    : constant Config.Schema.Channel_Config :=
        Find_Channel (Cfg, Config.Schema.Signal);
   begin
      if not PR.Valid then
         return "";
      end if;

      declare
         Envelope    : constant JSON_Value_Type :=
           Get_Object (PR.Root, "envelope");
         Source      : constant String :=
           Get_String (Envelope, "source");
         Data_Msg    : constant JSON_Value_Type :=
           Get_Object (Envelope, "dataMessage");
         Text        : constant String :=
           Get_String (Data_Msg, "message");
         Is_Operator : Boolean := False;
      begin
         if Text'Length = 0 then return ""; end if;

         --  Allowlist check.
         declare
            Allowlist   : constant String := To_String (Chan.Allowlist);
            Comma       : constant Natural := Index (Allowlist, ",");
            First_Entry : constant String :=
              (if Comma > 0 then Allowlist (Allowlist'First .. Comma - 1)
               else Allowlist);
         begin
            if Allowlist'Length = 0 then return ""; end if;
            if Allowlist /= "*" and then Index (Allowlist, Source) = 0 then
               return "";
            end if;
            --  Operator = first allowlist entry; guest = open-access users.
            Is_Operator := Allowlist /= "*" and then Source = First_Entry;
         end;

         --  Rate limit: enforce Max_RPS per user session.
         if not Channels.Rate_Limit.Check
           ("signal:" & Source, Chan.Max_RPS)
         then
            return "";
         end if;

         declare
            Sess  : constant String :=
              (if Is_Operator then "signal:" & Source
               else "guest-signal-" & Source);
            Conv  : Agent.Context.Conversation;
            Reply : Agent.Loop_Pkg.Agent_Reply;
         begin
            Set_Unbounded_String (Conv.Session_ID, Sess);
            Set_Unbounded_String (Conv.Channel, "signal:" & Source);

            if Memory.SQLite.Is_Open (Mem) then
               Memory.SQLite.Load_History
                 (Mem, Sess, Cfg.Memory.Max_History, Conv);
            end if;

            Metrics.Increment ("requests_total", "signal");

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
               Metrics.Increment ("errors_total", "signal");
            end if;
         end;
      end;
      return "";
   end Process_Message_JSON;

   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle)
   is
      Current_Cfg : Config.Schema.Agent_Config := Cfg;
      Chan_Cfg    : Config.Schema.Channel_Config :=
        Find_Channel (Current_Cfg, Config.Schema.Signal);
      Bridge_URL  : Unbounded_String := Chan_Cfg.Bridge_URL;
      Our_Number  : Unbounded_String := Chan_Cfg.Token;
   begin
      if not Chan_Cfg.Enabled or else Length (Bridge_URL) = 0 then
         Logging.Info ("Signal: not configured, skipping.");
         return;
      end if;

      Logging.Info
        ("Signal: polling " & To_String (Bridge_URL) & " ...");

      loop
         --  Check for SIGHUP-triggered config reload.
         if Config.Reload.Is_Requested then
            declare
               New_CR : constant Config.Loader.Load_Result :=
                 Config.Loader.Load;
            begin
               if New_CR.Success then
                  Current_Cfg := New_CR.Config;
                  Chan_Cfg    := Find_Channel (Current_Cfg, Config.Schema.Signal);
                  Bridge_URL  := Chan_Cfg.Bridge_URL;
                  Our_Number  := Chan_Cfg.Token;
                  Logging.Info ("Config reloaded.");
               end if;
            end;
            Config.Reload.Acknowledge;
         end if;

         declare
            BU   : constant String := To_String (Bridge_URL);
            Num  : constant String := To_String (Our_Number);
            Resp : constant HTTP.Client.Response :=
              HTTP.Client.Get
                (URL        => BU & "/v1/receive/" & Num,
                 Headers    => [1 .. 0 => <>],
                 Timeout_Ms => 10_000);
         begin
            if HTTP.Client.Is_Success (Resp) then
               declare
                  Body_Text : constant String :=
                    To_String (Resp.Body_Text);
                  PR        : constant Parse_Result := Parse (Body_Text);
               begin
                  if PR.Valid then
                     declare
                        Root_Arr : constant JSON_Array_Type :=
                          Value_To_Array (PR.Root);
                     begin
                        for I in 1 .. Array_Length (Root_Arr) loop
                           declare
                              Item       : constant JSON_Value_Type :=
                                Array_Item (Root_Arr, I);
                              Reply_Text : constant String :=
                                Process_Message_JSON
                                  (To_JSON_String (Item), Current_Cfg, Mem);
                              Source     : constant String :=
                                Get_String
                                  (Get_Object (Item, "envelope"), "source");
                           begin
                              if Reply_Text'Length > 0
                                and then Source'Length > 0
                              then
                                 if not Send_Message
                                   (BU, Num, Source, Reply_Text)
                                 then
                                    Logging.Error
                                      ("Signal: send failed to " & Source);
                                 end if;
                              end if;
                           end;
                        end loop;
                     end;
                  end if;
               end;
            end if;
         end;

         --  Brief pause between polls.
         delay 1.0;
      end loop;
   end Run_Polling;

end Channels.Signal;
