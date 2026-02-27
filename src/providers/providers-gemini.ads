--  Google Gemini provider: generateContent API (gemini-2.0-flash, etc.)
--  Uses query-param auth: ?key={api_key}

with Providers.Interface_Pkg; use Providers.Interface_Pkg;
with Agent.Context;
with Config.Schema;            use Config.Schema;
with Ada.Strings.Unbounded;    use Ada.Strings.Unbounded;

pragma SPARK_Mode (Off);
package Providers.Gemini is

   type Gemini_Provider is new Provider_Type with private;

   function Create (Cfg : Provider_Config) return Gemini_Provider;

   overriding function Chat
     (Provider  : in out Gemini_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response;

   overriding function Chat_Streaming
     (Provider  : in out Gemini_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response;

   overriding function Name (Provider : Gemini_Provider) return String;

private

   type Gemini_Provider is new Provider_Type with record
      API_Key    : Unbounded_String;
      Model      : Unbounded_String;
      Max_Tokens : Positive := 4096;
      Timeout_Ms : Positive := 60_000;
   end record;

end Providers.Gemini;
