with Ada.Environment_Variables;
with Providers.Interface_Pkg;       use Providers.Interface_Pkg;
with Providers.OpenAI;
with Providers.Anthropic;
with Providers.OpenAI_Compatible;
with Config.Schema;                  use Config.Schema;
with Agent.Context;                  use Agent.Context;

package body Agent.Loop_Pkg is

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
      end case;
   end Make_Provider;

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
            To_String (Cfg.System_Prompt));
      end if;
   end Ensure_System_Prompt;

   function Process_Message
     (User_Input : String;
      Conv       : in out Agent.Context.Conversation;
      Cfg        : Agent_Config;
      Mem        : Memory.SQLite.Memory_Handle) return Agent_Reply
   is
      Reply         : Agent_Reply;
      Provider      : access Provider_Type'Class;
      Tool_Schemas  : Tool_Schema_Array (1 .. Max_Schema_Count);
      Num_Tools     : Natural := 0;
      Round         : Natural := 0;
   begin
      --  Guard: need at least one provider.
      if Cfg.Num_Providers < 1 then
         Set_Unbounded_String
           (Reply.Error, "No providers configured. Add a provider to config.");
         return Reply;
      end if;

      Ensure_System_Prompt (Conv, Cfg);

      --  Append user message.
      Agent.Context.Append_Message
        (Conv, Agent.Context.User, User_Input);

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

      --  Create primary provider.
      Provider := Make_Provider (Cfg.Providers (1));

      --  Agentic loop: keep calling provider until no more tool calls.
      loop
         Round := Round + 1;
         exit when Round > Max_Tool_Rounds;

         declare
            Prov_Resp : Provider_Response :=
              Provider.Chat (Conv, Tool_Schemas, Num_Tools);
         begin
            if not Prov_Resp.Success and then Cfg.Num_Providers >= 2 then
               --  Try failover provider.
               declare
                  Failover : access Provider_Type'Class :=
                    Make_Provider (Cfg.Providers (2));
                  FR2      : constant Provider_Response :=
                    Failover.Chat (Conv, Tool_Schemas, Num_Tools);
               begin
                  if FR2.Success then
                     Prov_Resp := FR2;
                  end if;
               end;
            end if;

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
                  To_String (Prov_Resp.Content));

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
               & Natural'Image (Prov_Resp.Num_Tool_Calls) & "]");

            --  Execute each tool call and feed results back.
            for I in 1 .. Prov_Resp.Num_Tool_Calls loop
               declare
                  TC     : constant Tool_Call :=
                    Prov_Resp.Tool_Calls (I);
                  TRes   : constant Agent.Tools.Tool_Result :=
                    Agent.Tools.Dispatch
                      (Name      => To_String (TC.Name),
                       Args_JSON => To_String (TC.Arguments),
                       Cfg       => Cfg.Tools,
                       Workspace => Home_Workspace);
                  Output : constant String :=
                    (if TRes.Success
                     then To_String (TRes.Output)
                     else "ERROR: " & To_String (TRes.Error));
               begin
                  --  Append tool result as a message.
                  Agent.Context.Append_Message
                    (Conv, Agent.Context.Tool_Result,
                     Output,
                     To_String (TC.ID));
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
   end Process_Message;

end Agent.Loop_Pkg;
