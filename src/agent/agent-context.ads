--  Conversation context types for Quasar's agent loop.
--  These types are in standard Ada mode (not SPARK) because they manage
--  dynamic memory (Unbounded_String arrays) — but the security decisions
--  that act on messages are still SPARK-verified in Security.Policy.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Agent.Context is

   type Role is (System_Role, User, Assistant, Tool_Result);

   type Message is record
      Role    : Agent.Context.Role := User;
      Content : Unbounded_String;
      Name    : Unbounded_String;  -- for Tool_Result: the tool name
   end record;

   Max_History : constant := 200;  -- hard cap on in-memory messages

   type Message_Array is array (Positive range <>) of Message;

   --  A conversation holds an ordered list of messages plus metadata.
   type Conversation is record
      Session_ID : Unbounded_String;  -- unique per CLI session / channel message thread
      Channel    : Unbounded_String;  -- "cli", "telegram:<chat_id>", etc.
      Messages   : Message_Array (1 .. Max_History);
      Msg_Count  : Natural := 0;
   end record;

   function Make_Session_ID return String;
   --  Generates a random 16-char hex session ID.

   procedure Append_Message
     (Conv    : in out Conversation;
      Role    : Agent.Context.Role;
      Content : String;
      Name    : String := "");
   --  Appends a message, evicting oldest non-system messages if at capacity.

   function Last_User_Message (Conv : Conversation) return String;
   function Format_For_Provider (Conv : Conversation) return Message_Array;
   --  Returns messages trimmed to the current context window.

   function Token_Estimate (Conv : Conversation) return Natural;
   --  Rough token estimate: total chars / 4.

end Agent.Context;
