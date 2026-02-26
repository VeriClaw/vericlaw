--  Generic OpenAI-compatible endpoint provider.
--  Used for: Ollama, OpenRouter, Azure AI Foundry, LiteLLM, vLLM, etc.
--  Azure Foundry: set base_url, deployment, api_version in config.

with Providers.Interface_Pkg; use Providers.Interface_Pkg;
with Config.Schema;            use Config.Schema;
with Ada.Strings.Unbounded;    use Ada.Strings.Unbounded;

package Providers.OpenAI_Compatible is

   type OpenAI_Compat_Provider is new Provider_Type with private;

   function Create (Cfg : Provider_Config) return OpenAI_Compat_Provider;

   overriding function Chat
     (Provider  : in out OpenAI_Compat_Provider;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response;

   overriding function Name (Provider : OpenAI_Compat_Provider) return String;

private

   type OpenAI_Compat_Provider is new Provider_Type with record
      API_Key     : Unbounded_String;
      Base_URL    : Unbounded_String;
      Model       : Unbounded_String;
      Deployment  : Unbounded_String;  -- Azure: deployment name
      API_Version : Unbounded_String;  -- Azure: e.g. "2024-02-15-preview"
      Max_Tokens  : Positive := 4096;
      Timeout_Ms  : Positive := 60_000;
      Is_Azure    : Boolean  := False;
   end record;

end Providers.OpenAI_Compatible;
