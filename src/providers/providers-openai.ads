--  OpenAI provider: /v1/chat/completions API (gpt-4o, gpt-4-turbo, etc.)
--  Handles tool_calls in the response.

with Providers.Interface_Pkg; use Providers.Interface_Pkg;
with Config.Schema;            use Config.Schema;
with Ada.Strings.Unbounded;    use Ada.Strings.Unbounded;

package Providers.OpenAI is

   type OpenAI_Provider is new Provider_Type with private;

   function Create (Cfg : Provider_Config) return OpenAI_Provider;

   overriding function Chat
     (Provider  : in out OpenAI_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response;

   overriding function Name (Provider : OpenAI_Provider) return String;

private

   type OpenAI_Provider is new Provider_Type with record
      API_Key    : Unbounded_String;
      Base_URL   : Unbounded_String;
      Model      : Unbounded_String;
      Max_Tokens : Positive := 4096;
      Timeout_Ms : Positive := 60_000;
   end record;

end Providers.OpenAI;
