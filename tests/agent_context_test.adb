--  Unit tests for Agent.Context: Append_Message, eviction, formatting.
--  No external dependencies — pure Ada.

with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Agent.Context;          use Agent.Context;

procedure Agent_Context_Test is

   Passed : Natural := 0;
   Failed : Natural := 0;

   procedure Assert (Condition : Boolean; Label : String) is
   begin
      if Condition then
         Put_Line ("  PASS: " & Label);
         Passed := Passed + 1;
      else
         Put_Line ("  FAIL: " & Label);
         Failed := Failed + 1;
      end if;
   end Assert;

   ---------------------------------------------------------
   --  Section 1: Basic append
   ---------------------------------------------------------
   procedure Test_Append is
      Conv : Conversation;
   begin
      Put_Line ("--- Append_Message ---");
      Conv.Session_ID := To_Unbounded_String ("sess-001");
      Conv.Channel    := To_Unbounded_String ("cli");

      Append_Message (Conv, User, "Hello, Quasar!");
      Assert (Conv.Msg_Count = 1, "Msg_Count = 1 after first append");

      Append_Message (Conv, Assistant, "Hello! How can I help?");
      Assert (Conv.Msg_Count = 2, "Msg_Count = 2 after second append");

      Assert (Conv.Messages (1).Role = User,
              "First message role = User");
      Assert (To_String (Conv.Messages (1).Content) = "Hello, Quasar!",
              "First message content preserved");
      Assert (Conv.Messages (2).Role = Assistant,
              "Second message role = Assistant");
   end Test_Append;

   ---------------------------------------------------------
   --  Section 2: Last_User_Message
   ---------------------------------------------------------
   procedure Test_Last_User_Message is
      Conv : Conversation;
   begin
      Put_Line ("--- Last_User_Message ---");
      Append_Message (Conv, System_Role, "System prompt here.");
      Append_Message (Conv, User, "First user message.");
      Append_Message (Conv, Assistant, "First assistant reply.");
      Append_Message (Conv, User, "Second user message.");

      Assert (Last_User_Message (Conv) = "Second user message.",
              "Last_User_Message returns most recent user message");
   end Test_Last_User_Message;

   ---------------------------------------------------------
   --  Section 3: Token estimate is proportional
   ---------------------------------------------------------
   procedure Test_Token_Estimate is
      Conv  : Conversation;
      Est1  : Natural;
      Est2  : Natural;
   begin
      Put_Line ("--- Token_Estimate ---");
      Append_Message (Conv, User, "Short.");
      Est1 := Token_Estimate (Conv);

      --  Add a much longer message
      Append_Message (Conv, User,
        "This is a considerably longer message that should yield a higher " &
        "token estimate because it contains many more characters than the " &
        "previous one. The rough estimator divides total chars by 4.");
      Est2 := Token_Estimate (Conv);

      Assert (Est1 >= 1, "Token estimate >= 1 for non-empty conversation");
      Assert (Est2 > Est1, "Token estimate grows with more content");
   end Test_Token_Estimate;

   ---------------------------------------------------------
   --  Section 4: History eviction at capacity
   ---------------------------------------------------------
   procedure Test_Eviction is
      Conv : Conversation;
   begin
      Put_Line ("--- Eviction at Max_History ---");
      --  Prepend a system message that must survive eviction
      Append_Message (Conv, System_Role, "System: do not evict me.");

      --  Fill up to Max_History with user/assistant pairs
      for I in 1 .. Max_History loop
         Append_Message (Conv, User,
           "User message number " & Integer'Image (I));
      end loop;

      --  Msg_Count must not exceed Max_History
      Assert (Conv.Msg_Count <= Max_History,
              "Msg_Count stays within Max_History after overflow");

      --  System message must still be present at position 1
      Assert (Conv.Messages (1).Role = System_Role,
              "System message preserved after eviction");
   end Test_Eviction;

   ---------------------------------------------------------
   --  Section 5: Make_Session_ID produces non-empty string
   ---------------------------------------------------------
   procedure Test_Session_ID is
      ID1 : constant String := Make_Session_ID;
      ID2 : constant String := Make_Session_ID;
   begin
      Put_Line ("--- Make_Session_ID ---");
      Assert (ID1'Length = 16, "Session ID length = 16");
      Assert (ID1 /= ID2,     "Consecutive session IDs are distinct");
   end Test_Session_ID;

   ---------------------------------------------------------
   --  Section 6: Format_For_Provider
   ---------------------------------------------------------
   procedure Test_Format_For_Provider is
      Conv : Conversation;
      Msgs : Message_Array (1 .. Max_History);
   begin
      Put_Line ("--- Format_For_Provider ---");
      Append_Message (Conv, System_Role, "System prompt.");
      Append_Message (Conv, User, "Hello.");
      Append_Message (Conv, Assistant, "Hi there.");

      Msgs := Format_For_Provider (Conv);
      --  Format_For_Provider should return a contiguous array; check first few
      Assert (Msgs (1).Role = System_Role, "Format_For_Provider: msg 1 = System");
      Assert (Msgs (2).Role = User,        "Format_For_Provider: msg 2 = User");
      Assert (Msgs (3).Role = Assistant,   "Format_For_Provider: msg 3 = Assistant");
   end Test_Format_For_Provider;

begin
   Put_Line ("=== agent_context_test ===");
   Test_Append;
   Test_Last_User_Message;
   Test_Token_Estimate;
   Test_Eviction;
   Test_Session_ID;
   Test_Format_For_Provider;

   Put_Line ("");
   Put_Line ("Results: " & Natural'Image (Passed) & " passed, "
             & Natural'Image (Failed) & " failed");
   if Failed > 0 then
      raise Program_Error with Natural'Image (Failed) & " test(s) failed";
   end if;
end Agent_Context_Test;
