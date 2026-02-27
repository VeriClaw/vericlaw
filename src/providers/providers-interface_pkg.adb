--  Default implementation of Chat_Streaming: falls back to non-streaming Chat.
--  Providers that support SSE streaming override this.

pragma SPARK_Mode (Off);
package body Providers.Interface_Pkg is

   function Chat_Streaming
     (Provider  : in out Provider_Type;
      Conv      : Agent.Context.Conversation;
      Tools     : Tool_Schema_Array;
      Num_Tools : Natural) return Provider_Response
   is
   begin
      return Provider_Type'Class (Provider).Chat (Conv, Tools, Num_Tools);
   end Chat_Streaming;

end Providers.Interface_Pkg;
