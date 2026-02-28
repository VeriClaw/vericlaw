with Ada.Strings.Unbounded;
with Agent.Context;
with Config.Schema;            use Config.Schema;
with Providers.Interface_Pkg;  use Providers.Interface_Pkg;
with Providers.OpenAI;
with Providers.Anthropic;
with Providers.OpenAI_Compatible;
with Providers.Gemini;

package body Tools.Spawn
  with SPARK_Mode => Off
is

   Spawn_Depth : Natural := 0;

   pragma Warnings (Off, "anonymous access type allocator");
   function Make_Provider_Local
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
         when Gemini =>
            return new Providers.Gemini.Gemini_Provider'
              (Providers.Gemini.Create (Cfg));
      end case;
   end Make_Provider_Local;
   pragma Warnings (On, "anonymous access type allocator");

   function Run_Subagent
     (Prompt : String;
      Cfg    : Config.Schema.Agent_Config;
      Model  : String := "") return String
   is
      Conv        : Agent.Context.Conversation;
      Prov_Cfg    : Provider_Config;
      Provider    : access Provider_Type'Class;
      Empty_Tools : Tool_Schema_Array (1 .. 0);
      Resp        : Provider_Response;
   begin
      if Spawn_Depth >= Max_Spawn_Depth then
         return "Error: maximum spawn depth reached";
      end if;
      pragma Warnings (Off, "condition can only be");
      if Cfg.Num_Providers < 1 then
         pragma Warnings (On, "condition can only be");
         return "Error: no providers configured";
      end if;

      Prov_Cfg := Cfg.Providers (1);
      if Model'Length > 0 then
         Ada.Strings.Unbounded.Set_Unbounded_String (Prov_Cfg.Model, Model);
      end if;

      Agent.Context.Append_Message
        (Conv, Agent.Context.System_Role,
         Ada.Strings.Unbounded.To_String (Cfg.System_Prompt));
      Agent.Context.Append_Message (Conv, Agent.Context.User, Prompt);

      Spawn_Depth := Spawn_Depth + 1;
      Provider    := Make_Provider_Local (Prov_Cfg);
      Resp        := Provider.Chat (Conv, Empty_Tools, 0);
      Spawn_Depth := Spawn_Depth - 1;

      if Resp.Success then
         return Ada.Strings.Unbounded.To_String (Resp.Content);
      else
         return "Subagent error: "
           & Ada.Strings.Unbounded.To_String (Resp.Error);
      end if;
   end Run_Subagent;

end Tools.Spawn;
