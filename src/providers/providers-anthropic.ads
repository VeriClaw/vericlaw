--  Anthropic provider: /v1/messages API (claude-3-5-sonnet, claude-3-opus, etc.)

with Providers.Interface_Pkg; use Providers.Interface_Pkg;
with Agent.Context;
with Config.Schema;            use Config.Schema;
with Ada.Strings.Unbounded;    use Ada.Strings.Unbounded;

package Providers.Anthropic
  with SPARK_Mode => Off
is

   type Anthropic_Provider is new Provider_Type with private;

   function Create (Cfg : Provider_Config) return Anthropic_Provider;

   overriding function Chat
     (Provider  : in out Anthropic_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response;

   overriding function Chat_Streaming
     (Provider  : in out Anthropic_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response;

   overriding function Name (Provider : Anthropic_Provider) return String;

private

   type Anthropic_Provider is new Provider_Type with record
      API_Key    : Unbounded_String;
      Model      : Unbounded_String;
      Max_Tokens : Positive := 4096;
      Timeout_Ms : Positive := 60_000;
   end record;

end Providers.Anthropic;
