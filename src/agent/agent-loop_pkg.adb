with Ada.Environment_Variables;
with Providers.Interface_Pkg;       use Providers.Interface_Pkg;
with Providers.OpenAI;
with Providers.Anthropic;
with Providers.OpenAI_Compatible;
with Providers.Gemini;
with Agent.Tools;
with Gateway.Provider.Routing;
with Gateway.Provider.Runtime_Routing;
with Metrics;
with Metrics.Cost;
with Observability.Tracing;

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
         when OpenAI =>
            return new Providers.OpenAI.OpenAI_Provider'
              (Providers.OpenAI.Create (Cfg));
         when Anthropic =>
            return new Providers.Anthropic.Anthropic_Provider'
              (Providers.Anthropic.Create (Cfg));
         when Azure_Foundry | OpenAI_Compatible =>
            return new Providers.OpenAI_Compatible.OpenAI_Compat_Provider'
              (Providers.OpenAI_Compatible.Create (Cfg));
         when Gemini =>
            return new Providers.Gemini.Gemini_Provider'
              (Providers.Gemini.Create (Cfg));
      end case;
   end Make_Provider;

   --  Map Provider_Kind to a Prometheus label string.
   function Provider_Label (Kind : Provider_Kind) return String is
   begin
      case Kind is
         when OpenAI             => return "openai";
         when Anthropic          => return "anthropic";
         when Azure_Foundry      => return "azure_foundry";
         when OpenAI_Compatible  => return "openai_compatible";
         when Gemini             => return "gemini";
      end case;
   end Provider_Label;

   function Call_Provider_With_Routing
     (Conv         : Agent.Context.Conversation;
      Cfg          : Agent_Config;
      Tool_Schemas : Tool_Schema_Array;
      Num_Tools    : Natural;
      Streaming    : Boolean) return Provider_Response
   is
      Routing_State : Gateway.Provider.Runtime_Routing.Attempt_State;
      Attempt       : Gateway.Provider.Runtime_Routing.Provider_Attempt;
      Response      : Provider_Response;
      First_Error   : Unbounded_String;
      Error_Set     : Boolean := False;
   begin
      --  Runtime config is still ordered. Route providers[1], [2], and [3..]
      --  through the existing primary/failover/long-tail tiers.
      loop
         Attempt :=
           Gateway.Provider.Runtime_Routing.Next_Attempt
             (Cfg   => Cfg,
              State => Routing_State);
         exit when not Attempt.Allowed;

         declare
            Attempt_Index : constant Config.Schema.Provider_Index :=
              Config.Schema.Provider_Index (Attempt.Config_Index);
            Attempt_Cfg   : constant Provider_Config := Cfg.Providers (Attempt_Index);
            Provider      : constant access Provider_Type'Class :=
              Make_Provider (Attempt_Cfg);
            Prov_Label    : constant String := Provider_Label (Attempt_Cfg.Kind);
            LLM_Span      : constant Observability.Tracing.Span_ID :=
              Observability.Tracing.Start_Span ("llm.chat");
            Prov_Resp     : Provider_Response;
            Use_Streaming : constant Boolean :=
              Streaming
              and then Attempt_Index = Config.Schema.Provider_Index'First
              and then not Gateway.Provider.Routing.Route_Uses_Fallback
                (Attempt.Route);
         begin
            if Use_Streaming then
               Prov_Resp := Provider.Chat_Streaming (Conv, Tool_Schemas, Num_Tools);
            else
               Prov_Resp := Provider.Chat (Conv, Tool_Schemas, Num_Tools);
            end if;

            Observability.Tracing.Set_Attribute
              (LLM_Span, "provider", Prov_Label);
            Observability.Tracing.Set_Attribute
              (LLM_Span, "model", To_String (Attempt_Cfg.Model));
            if not Prov_Resp.Success then
               Observability.Tracing.Set_Error
                 (LLM_Span, To_String (Prov_Resp.Error));
            end if;
            Observability.Tracing.End_Span (LLM_Span);

            Metrics.Increment ("provider_calls_total", Prov_Label);

            if Prov_Resp.Success then
               Metrics.Cost.Record_Usage
                 (Prov_Label,
                  Prov_Resp.Input_Tokens,
                  Prov_Resp.Output_Tokens,
                  Attempt_Cfg.Price_Per_1K_Input,
                  Attempt_Cfg.Price_Per_1K_Output);
               return Prov_Resp;
            end if;

            Metrics.Increment ("provider_errors_total", Prov_Label);
            if not Error_Set then
               First_Error := Prov_Resp.Error;
               Error_Set := True;
            end if;

            Gateway.Provider.Runtime_Routing.Mark_Failed
              (State   => Routing_State,
               Attempt => Attempt);
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
                        Tool_Span : constant Observability.Tracing.Span_ID :=
                          Observability.Tracing.Start_Span ("tool.execute");
                        TRes  : constant Agent.Tools.Tool_Result :=
                          Agent.Tools.Safe_Dispatch
                            (Name      => TName,
                             Args_JSON => To_String (TC.Arguments),
                             Cfg       => Cfg,
                             Mem       => Mem,
                             Workspace => Home_Workspace);
                     begin
                        Observability.Tracing.Set_Attribute
                          (Tool_Span, "tool_name", TName);
                        if not TRes.Success then
                           Observability.Tracing.Set_Error
                             (Tool_Span, To_String (TRes.Error));
                        end if;
                        Observability.Tracing.End_Span (Tool_Span);
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
                  Tool_Span_S : constant Observability.Tracing.Span_ID :=
                    Observability.Tracing.Start_Span ("tool.execute");
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
                  Observability.Tracing.Set_Attribute
                    (Tool_Span_S, "tool_name", TName);
                  if not TRes.Success then
                     Observability.Tracing.Set_Error
                       (Tool_Span_S, To_String (TRes.Error));
                  end if;
                  Observability.Tracing.End_Span (Tool_Span_S);
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
