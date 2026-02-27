--  Conversation context types for VeriClaw's agent loop.
--  These types are in standard Ada mode (not SPARK) because they manage
--  dynamic memory (Unbounded_String arrays) — but the security decisions
--  that act on messages are still SPARK-verified in Security.Policy.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Agent.Context
  with SPARK_Mode => Off
is

   type Role is (System_Role, User, Assistant, Tool_Result);

   --  Image attachment for multimodal messages.
   Max_Images : constant := 4;  -- cap images per message
   type Image_Attachment is record
      Data       : Unbounded_String;  -- base64-encoded image data
      Media_Type : Unbounded_String;  -- e.g. "image/jpeg", "image/png"
      Source_URL  : Unbounded_String;  -- original URL or file path (empty for inline)
   end record;
   type Image_Array is array (1 .. Max_Images) of Image_Attachment;

   type Message is record
      Role       : Agent.Context.Role := User;
      Content    : Unbounded_String;
      Name       : Unbounded_String;  -- for Tool_Result: the tool name
      Images     : Image_Array;
      Num_Images : Natural := 0;
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

   --  Parse [IMAGE:path] and [IMAGE:url] markers from user input.
   --  Returns the text with markers removed and images populated.
   procedure Parse_Image_Markers
     (Input    : String;
      Text_Out : out Unbounded_String;
      Images   : out Image_Array;
      Num_Imgs : out Natural);

   --  Branch metadata for conversation forking.
   type Branch_Info is record
      Session_ID : Unbounded_String;
      Fork_At    : Natural := 0;
      Created_At : Unbounded_String;
   end record;
   Max_Branches : constant := 32;
   type Branch_Array is array (1 .. Max_Branches) of Branch_Info;

end Agent.Context;
