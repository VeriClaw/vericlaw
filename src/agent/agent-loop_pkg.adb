with Ada.Environment_Variables;
with Providers.Interface_Pkg;       use Providers.Interface_Pkg;
with Providers.Anthropic;
with Providers.OpenAI_Compatible;
with Agent.Tools;

package body Agent.Loop_Pkg
  with SPARK_Mode => Off
is
   use Config.Schema;
   use Agent.Context;

   Max_Schema_Count : constant := Max_Tool_Schemas;

   --  Derive workspace path (home dir + .vericlaw/workspace).
   function Home_Workspace return String is
      Home : constant String :=
        Ada.Environment_Variables.Value ("HOME", ".");
   begin
      return Home & "/.vericlaw/workspace";
   end Home_Workspace;

   --  Create a provider from config. Returns a heap-allocated Provider_Type.
   function Make_Provider
     (Cfg : Provider_Config) return access Provider_Type'Class
   is
      pragma Warnings (Off, "anonymous access");
   begin
      case Cfg.Kind is
         when Anthropic =>
            return new Providers.Anthropic.Anthropic_Provider'
              (Providers.Anthropic.Create (Cfg));
         when OpenAI | Azure_Foundry | OpenAI_Compatible | Gemini =>
            return new Providers.OpenAI_Compatible.OpenAI_Compat_Provider'
              (Providers.OpenAI_Compatible.Create (Cfg));
      end case;
   end Make_Provider;

   function Call_Provider_With_Routing
     (Conv         : Agent.Context.Conversation;
      Cfg          : Agent_Config;
      Tool_Schemas : Tool_Schema_Array;
      Num_Tools    : Natural;
      Streaming    : Boolean) return Provider_Response
   is
      Response    : Provider_Response;
      First_Error : Unbounded_String;
      Error_Set   : Boolean := False;
   begin
      for Attempt_Index in
        Config.Schema.Provider_Index'First .. Cfg.Num_Providers
      loop
         declare
            Attempt_Cfg : constant Provider_Config :=
              Cfg.Providers (Attempt_Index);
            Provider    : constant access Provider_Type'Class :=
              Make_Provider (Attempt_Cfg);
            Prov_Resp   : Provider_Response;
         begin
            if Streaming
              and then Attempt_Index = Config.Schema.Provider_Index'First
            then
               Prov_Resp :=
                 Provider.Chat_Streaming (Conv, Tool_Schemas, Num_Tools);
            else
               Prov_Resp := Provider.Chat (Conv, Tool_Schemas, Num_Tools);
            end if;

            if Prov_Resp.Success then
               return Prov_Resp;
            end if;

            if not Error_Set then
               First_Error := Prov_Resp.Error;
               Error_Set   := True;
            end if;
         end;
      end loop;

      Response.Success := False;
      if Error_Set then
         Response.Error := First_Error;
      else
         Response.Error :=
           To_Unbounded_String
             ("No provider available. Add a provider to config.");
      end if;
      return Response;
   end Call_Provider_With_Routing;

   --  Inject system prompt at the start of the conversation if not present.
   procedure Ensure_System_Prompt
     (Conv : in out Agent.Context.Conversation;
      Cfg  : Agent_Config)
   is
   begin
      if Conv.Msg_Count = 0
        or else Conv.Messages (1).Role /= Agent.Context.System_Role
      then
         Agent.Context.Append_Message
           (Conv,
            Agent.Context.System_Role,
            To_String (Cfg.System_Prompt),
            Limit => Cfg.Memory.Max_History);
      end if;
   end Ensure_System_Prompt;

   --  Compact the oldest turn when the configured fill-ratio threshold is met.
   --  Called once per user turn, before appending the new user message.
   procedure Compact_If_Needed
     (Conv : in out Agent.Context.Conversation;
      Cfg  : Agent_Config)
   is
   begin
      if Agent.Context.Compaction_Needed
           (Conv          => Conv,
            Threshold_Pct => Cfg.Memory.Compact_At_Pct,
            Limit         => Cfg.Memory.Max_History)
      then
         Agent.Context.Compact_Oldest_Turn (Conv);
      end if;
   end Compact_If_Needed;

   function Process_Message
     (User_Input : String;
      Conv       : in out Agent.Context.Conversation;
      Cfg        : Agent_Config;
      Mem        : Memory.SQLite.Memory_Handle) return Agent_Reply
   is
      Reply        : Agent_Reply;
      Tool_Schemas : Tool_Schema_Array (1 .. Max_Schema_Count);
      Num_Tools    : Natural := 0;
      Round        : Natural := 0;
   begin
      --  Guard: need at least one provider (defensive; Provider_Index >= 1).
      pragma Warnings (Off, "condition can only be");
      if Cfg.Num_Providers < 1 then
         Set_Unbounded_String
           (Reply.Error, "No providers configured. Add a provider to config.");
         return Reply;
      end if;
      pragma Warnings (On, "condition can only be");

      Ensure_System_Prompt (Conv, Cfg);
      Compact_If_Needed (Conv, Cfg);

      --  Parse [IMAGE:path] markers from user input.
      declare
         Text_Part : Unbounded_String;
         Imgs      : Agent.Context.Image_Array;
         Num_Imgs  : Natural;
      begin
         Agent.Context.Parse_Image_Markers
           (User_Input, Text_Part, Imgs, Num_Imgs);
         Agent.Context.Append_Message
           (Conv, Agent.Context.User, To_String (Text_Part),
            Limit => Cfg.Memory.Max_History);
         --  Attach parsed images to the just-appended message.
         if Num_Imgs > 0 and Conv.Msg_Count > 0 then
            Conv.Messages (Conv.Msg_Count).Images := Imgs;
            Conv.Messages (Conv.Msg_Count).Num_Images := Num_Imgs;
         end if;
      end;

      --  Persist to memory.
      if Memory.SQLite.Is_Open (Mem) then
         Memory.SQLite.Save_Message
           (Mem,
            To_String (Conv.Session_ID),
            To_String (Conv.Channel),
            Agent.Context.User,
            User_Input);
      end if;

      --  Build tool schemas from config.
      Agent.Tools.Build_Schemas (Cfg.Tools, Tool_Schemas, Num_Tools);

      --  Agentic loop: keep calling provider until no more tool calls.
      loop
         Round := Round + 1;
         exit when Round > Max_Tool_Rounds;

         declare
            Prov_Resp : constant Provider_Response :=
              Call_Provider_With_Routing
                (Conv         => Conv,
                 Cfg          => Cfg,
                 Tool_Schemas => Tool_Schemas,
                 Num_Tools    => Num_Tools,
                 Streaming    => False);
         begin
            if not Prov_Resp.Success then
               Set_Unbounded_String
                 (Reply.Error, To_String (Prov_Resp.Error));
               return Reply;
            end if;

            --  No tool calls → done.
            if Prov_Resp.Num_Tool_Calls = 0 then
               Reply.Content  := Prov_Resp.Content;
               Reply.Success  := True;

               --  Append assistant reply to conversation.
               Agent.Context.Append_Message
                 (Conv, Agent.Context.Assistant,
                  To_String (Prov_Resp.Content),
                  Limit => Cfg.Memory.Max_History);

               --  Persist assistant reply.
               if Memory.SQLite.Is_Open (Mem) then
                  Memory.SQLite.Save_Message
                    (Mem,
                     To_String (Conv.Session_ID),
                     To_String (Conv.Channel),
                     Agent.Context.Assistant,
                     To_String (Prov_Resp.Content));
               end if;

               exit;
            end if;

            --  Append assistant tool-call placeholder.
            Agent.Context.Append_Message
              (Conv, Agent.Context.Assistant,
               "[tool calls: "
               & Natural'Image (Prov_Resp.Num_Tool_Calls) & "]",
               Limit => Cfg.Memory.Max_History);

            --  Execute tool calls; parallelise safe ones when N > 1.
            declare
               N : constant Positive := Prov_Resp.Num_Tool_Calls;

               --  Tools that have ordering-sensitive side effects run
               --  sequentially; everything else is safe to parallelise.
               function Is_Parallel_Safe (Name : String) return Boolean is
               begin
                  return Name /= "cron_add"
                    and then Name /= "cron_list"
                    and then Name /= "cron_remove"
                    and then Name /= "spawn"
                    and then Name /= "delegate";
               end Is_Parallel_Safe;

               type Output_Array is
                 array (Positive range 1 .. N) of Unbounded_String;
               Outputs  : Output_Array;
               All_Safe : Boolean := N > 1;
            begin
               --  Check every call in this batch before committing to the
               --  parallel path.
               if All_Safe then
                  for I in 1 .. N loop
                     if not Is_Parallel_Safe
                          (To_String (Prov_Resp.Tool_Calls (I).Name))
                     then
                        All_Safe := False;
                        exit;
                     end if;
                  end loop;
               end if;

               if All_Safe then
                  --  Parallel path: one Ada task per tool call.
                  declare
                     task type Worker is
                        entry Start (TC : Tool_Call);
                        entry Get_Result (R : out Unbounded_String);
                     end Worker;

                     task body Worker is
                        My_TC : Tool_Call;
                        Res   : Unbounded_String;
                     begin
                        accept Start (TC : Tool_Call) do
                           My_TC := TC;
                        end Start;

                        declare
                           TName : constant String := To_String (My_TC.Name);
                           TRes  : constant Agent.Tools.Tool_Result :=
                             Agent.Tools.Safe_Dispatch
                               (Name      => TName,
                                Args_JSON => To_String (My_TC.Arguments),
                                Cfg       => Cfg,
                                Mem       => Mem,
                                Workspace => Home_Workspace);
                        begin
                           Res := To_Unbounded_String
                             (if TRes.Success
                              then To_String (TRes.Output)
                              else "ERROR: " & To_String (TRes.Error));
                        end;

                        accept Get_Result (R : out Unbounded_String) do
                           R := Res;
                        end Get_Result;
                     end Worker;

                     type Worker_Access is access Worker;
                     Workers : array (1 .. N) of Worker_Access;
                  begin
                     --  Spawn and start all workers concurrently.
                     for I in 1 .. N loop
                        Workers (I) := new Worker;
                        Workers (I).Start (Prov_Resp.Tool_Calls (I));
                     end loop;
                     --  Collect results in original call order.
                     begin
                        for I in 1 .. N loop
                           Workers (I).Get_Result (Outputs (I));
                        end loop;
                     exception
                        when others =>
                           for I in 1 .. N loop
                              if not Workers (I)'Terminated then
                                 abort Workers (I).all;
                              end if;
                           end loop;
                           raise;
                     end;
                  end;
               else
                  --  Sequential path: single call or ordering-sensitive tools.
                  for I in 1 .. N loop
                     declare
                        TC    : constant Tool_Call :=
                          Prov_Resp.Tool_Calls (I);
                        TName : constant String := To_String (TC.Name);
                        TRes  : constant Agent.Tools.Tool_Result :=
                          Agent.Tools.Safe_Dispatch
                            (Name      => TName,
                             Args_JSON => To_String (TC.Arguments),
                             Cfg       => Cfg,
                             Mem       => Mem,
                             Workspace => Home_Workspace);
                     begin
                        Outputs (I) :=
                          To_Unbounded_String
                            (if TRes.Success
                             then To_String (TRes.Output)
                             else "ERROR: " & To_String (TRes.Error));
                     end;
                  end loop;
               end if;

               --  Feed all results back into the conversation in order.
               for I in 1 .. N loop
                  Agent.Context.Append_Message
                    (Conv, Agent.Context.Tool_Result,
                     To_String (Outputs (I)),
                     Name  => To_String (Prov_Resp.Tool_Calls (I).ID),
                     Limit => Cfg.Memory.Max_History);
               end loop;
            end;
         end;
      end loop;

      if Round > Max_Tool_Rounds then
         Set_Unbounded_String
           (Reply.Content,
            "I reached the maximum number of tool-use steps. "
            & "Here is what I found so far.");
         Reply.Success := True;
      end if;

      return Reply;
   end Process_Message;

   function Process_Message_Streaming
     (User_Input : String;
      Conv       : in out Agent.Context.Conversation;
      Cfg        : Config.Schema.Agent_Config;
      Mem        : Memory.SQLite.Memory_Handle) return Agent_Reply
   is
      Reply        : Agent_Reply;
      Tool_Schemas : Tool_Schema_Array (1 .. Max_Schema_Count);
      Num_Tools    : Natural := 0;
      Round        : Natural := 0;
   begin
      pragma Warnings (Off, "condition can only be");
      if Cfg.Num_Providers < 1 then
         Set_Unbounded_String
           (Reply.Error, "No providers configured. Add a provider to config.");
         return Reply;
      end if;
      pragma Warnings (On, "condition can only be");

      Ensure_System_Prompt (Conv, Cfg);
      Compact_If_Needed (Conv, Cfg);

      --  Parse [IMAGE:path] markers from user input.
      declare
         Text_Part : Unbounded_String;
         Imgs      : Agent.Context.Image_Array;
         Num_Imgs  : Natural;
      begin
         Agent.Context.Parse_Image_Markers
           (User_Input, Text_Part, Imgs, Num_Imgs);
         Agent.Context.Append_Message
           (Conv, Agent.Context.User, To_String (Text_Part),
            Limit => Cfg.Memory.Max_History);
         if Num_Imgs > 0 and Conv.Msg_Count > 0 then
            Conv.Messages (Conv.Msg_Count).Images := Imgs;
            Conv.Messages (Conv.Msg_Count).Num_Images := Num_Imgs;
         end if;
      end;

      if Memory.SQLite.Is_Open (Mem) then
         Memory.SQLite.Save_Message
           (Mem,
            To_String (Conv.Session_ID),
            To_String (Conv.Channel),
            Agent.Context.User,
            User_Input);
      end if;

      Agent.Tools.Build_Schemas (Cfg.Tools, Tool_Schemas, Num_Tools);

      loop
         Round := Round + 1;
         exit when Round > Max_Tool_Rounds;

         declare
            Prov_Resp : constant Provider_Response :=
              Call_Provider_With_Routing
                (Conv         => Conv,
                 Cfg          => Cfg,
                 Tool_Schemas => Tool_Schemas,
                 Num_Tools    => Num_Tools,
                 Streaming    => True);
         begin
            if not Prov_Resp.Success then
               Set_Unbounded_String
                 (Reply.Error, To_String (Prov_Resp.Error));
               return Reply;
            end if;

            if Prov_Resp.Num_Tool_Calls = 0 then
               Reply.Content := Prov_Resp.Content;
               Reply.Success := True;

               Agent.Context.Append_Message
                 (Conv, Agent.Context.Assistant,
                  To_String (Prov_Resp.Content),
                  Limit => Cfg.Memory.Max_History);

               if Memory.SQLite.Is_Open (Mem) then
                  Memory.SQLite.Save_Message
                    (Mem,
                     To_String (Conv.Session_ID),
                     To_String (Conv.Channel),
                     Agent.Context.Assistant,
                     To_String (Prov_Resp.Content));
               end if;

               exit;
            end if;

            Agent.Context.Append_Message
              (Conv, Agent.Context.Assistant,
               "[tool calls: "
               & Natural'Image (Prov_Resp.Num_Tool_Calls) & "]",
               Limit => Cfg.Memory.Max_History);

            for I in 1 .. Prov_Resp.Num_Tool_Calls loop
               declare
                  TC    : constant Tool_Call := Prov_Resp.Tool_Calls (I);
                  TName : constant String    := To_String (TC.Name);
                  TRes  : constant Agent.Tools.Tool_Result :=
                    Agent.Tools.Safe_Dispatch
                      (Name      => TName,
                       Args_JSON => To_String (TC.Arguments),
                       Cfg       => Cfg,
                       Mem       => Mem,
                       Workspace => Home_Workspace);
                  Output : constant String :=
                    (if TRes.Success
                     then To_String (TRes.Output)
                     else "ERROR: " & To_String (TRes.Error));
               begin
                  Agent.Context.Append_Message
                    (Conv, Agent.Context.Tool_Result,
                     Output,
                     Name  => To_String (TC.ID),
                     Limit => Cfg.Memory.Max_History);
               end;
            end loop;
         end;
      end loop;

      if Round > Max_Tool_Rounds then
         Set_Unbounded_String
           (Reply.Content,
            "I reached the maximum number of tool-use steps. "
            & "Here is what I found so far.");
         Reply.Success := True;
      end if;

      return Reply;
   end Process_Message_Streaming;

end Agent.Loop_Pkg;
