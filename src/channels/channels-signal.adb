with Ada.Text_IO;
with HTTP.Client;
with Config.JSON_Parser; use Config.JSON_Parser;
with Agent.Context;
with Agent.Loop_Pkg;
with Ada.Strings.Fixed;  use Ada.Strings.Fixed;

package body Channels.Signal is

   function Get_Chan_Config
     (Cfg : Config.Schema.Agent_Config)
      return Config.Schema.Channel_Config
   is
   begin
      for I in 1 .. Cfg.Num_Channels loop
         if Cfg.Channels (I).Kind = Config.Schema.Signal then
            return Cfg.Channels (I);
         end if;
      end loop;
      return (Kind => Config.Schema.Signal, others => <>);
   end Get_Chan_Config;

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
         Headers   => (1 .. 0 => <>),
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
        Get_Chan_Config (Cfg);
   begin
      if not PR.Valid then
         return "";
      end if;

      declare
         Envelope : constant JSON_Value_Type :=
           Get_Object (PR.Root, "envelope");
         Source   : constant String :=
           Get_String (Envelope, "source");
         Data_Msg : constant JSON_Value_Type :=
           Get_Object (Envelope, "dataMessage");
         Text     : constant String :=
           Get_String (Data_Msg, "message");
      begin
         if Text'Length = 0 then return ""; end if;

         --  Allowlist check.
         declare
            Allowlist : constant String := To_String (Chan.Allowlist);
         begin
            if Allowlist'Length = 0 then return ""; end if;
            if Allowlist /= "*" and then Index (Allowlist, Source) = 0 then
               return "";
            end if;
         end;

         declare
            Conv  : Agent.Context.Conversation;
            Reply : Agent.Loop_Pkg.Agent_Reply;
         begin
            Set_Unbounded_String (Conv.Session_ID, "signal:" & Source);
            Set_Unbounded_String (Conv.Channel, "signal:" & Source);

            if Mem.Open then
               Memory.SQLite.Load_History
                 (Mem, "signal:" & Source,
                  Cfg.Memory.Max_History, Conv);
            end if;

            Reply := Agent.Loop_Pkg.Process_Message
              (User_Input => Text,
               Conv       => Conv,
               Cfg        => Cfg,
               Mem        => Mem);

            if Reply.Success then
               return To_String (Reply.Content);
            end if;
         end;
      end;
      return "";
   end Process_Message_JSON;

   procedure Run_Polling
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle)
   is
      Chan_Cfg   : constant Config.Schema.Channel_Config :=
        Get_Chan_Config (Cfg);
      Bridge_URL : constant String := To_String (Chan_Cfg.Bridge_URL);
      Our_Number : constant String := To_String (Chan_Cfg.Token);
   begin
      if not Chan_Cfg.Enabled or else Bridge_URL'Length = 0 then
         Ada.Text_IO.Put_Line ("Signal: not configured, skipping.");
         return;
      end if;

      Ada.Text_IO.Put_Line ("Signal: polling " & Bridge_URL & " ...");

      loop
         declare
            Resp : constant HTTP.Client.Response :=
              HTTP.Client.Get
                (URL       => Bridge_URL & "/v1/receive/" & Our_Number,
                 Headers   => (1 .. 0 => <>),
                 Timeout_Ms => 10_000);
         begin
            if HTTP.Client.Is_Success (Resp) then
               declare
                  Body_Text : constant String :=
                    To_String (Resp.Body_Text);
                  PR        : constant Parse_Result := Parse (Body_Text);
               begin
                  if PR.Valid then
                     for I in 1 .. Integer (PR.Root.Length) loop
                        declare
                           Item       : constant JSON_Value_Type :=
                             PR.Root.Get (I);
                           Reply_Text : constant String :=
                             Process_Message_JSON
                               (To_JSON_String (Item), Cfg, Mem);
                           Source     : constant String :=
                             Get_String
                               (Get_Object (Item, "envelope"), "source");
                        begin
                           if Reply_Text'Length > 0
                             and then Source'Length > 0
                           then
                              if not Send_Message
                                (Bridge_URL, Our_Number,
                                 Source, Reply_Text)
                              then
                                 Ada.Text_IO.Put_Line
                                   ("Signal: send failed to " & Source);
                              end if;
                           end if;
                        end;
                     end loop;
                  end if;
               end;
            end if;
         end;

         --  Brief pause between polls.
         delay 1.0;
      end loop;
   end Run_Polling;

end Channels.Signal;
