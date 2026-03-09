--  Unit tests for Agent.Context: Append_Message, eviction, formatting.
--  No external dependencies — pure Ada.

with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Agent.Context;          use Agent.Context;
with Config.Schema;

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

      Append_Message (Conv, User, "Hello, VeriClaw!");
      Assert (Conv.Msg_Count = 1, "Msg_Count = 1 after first append");

      Append_Message (Conv, Assistant, "Hello! How can I help?");
      Assert (Conv.Msg_Count = 2, "Msg_Count = 2 after second append");

      Assert (Conv.Messages (1).Role = User,
              "First message role = User");
      Assert (To_String (Conv.Messages (1).Content) = "Hello, VeriClaw!",
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
      Put_Line ("--- Eviction at Max_Stored_Messages ---");
      --  Prepend a system message that must survive eviction
      Append_Message (Conv, System_Role, "System: do not evict me.");

      --  Fill up to Max_Stored_Messages with user/assistant pairs
      for I in 1 .. Max_Stored_Messages loop
         Append_Message (Conv, User,
           "User message number " & Integer'Image (I));
      end loop;

      --  Msg_Count must not exceed Max_Stored_Messages
      Assert (Conv.Msg_Count <= Max_Stored_Messages,
              "Msg_Count stays within Max_Stored_Messages after overflow");

      --  System message must still be present at position 1
      Assert (Conv.Messages (1).Role = System_Role,
              "System message preserved after eviction");
   end Test_Eviction;

   ---------------------------------------------------------
   --  Section 5: Configured history limit is enforced
   ---------------------------------------------------------
   procedure Test_Configured_Limit is
      Conv : Conversation;
   begin
      Put_Line ("--- Configured history limit ---");
      Append_Message (Conv, System_Role, "System prompt.", Limit => 3);
      Append_Message (Conv, User, "User 1", Limit => 3);
      Append_Message (Conv, User, "User 2", Limit => 3);
      Append_Message (Conv, User, "User 3", Limit => 3);

      Assert (Conv.Msg_Count = 3,
              "Msg_Count respects configured history limit");
      Assert (Conv.Messages (1).Role = System_Role,
              "System prompt remains at position 1");
      Assert (To_String (Conv.Messages (2).Content) = "User 2",
              "Oldest conversational message is evicted first");
      Assert (To_String (Conv.Messages (3).Content) = "User 3",
              "Newest message is retained");
   end Test_Configured_Limit;

   ---------------------------------------------------------
   --  Section 6: Make_Session_ID produces non-empty string
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
   --  Section 7: Format_For_Provider
   ---------------------------------------------------------
   procedure Test_Format_For_Provider is
      Conv : Conversation;
   begin
      Put_Line ("--- Format_For_Provider ---");
      Append_Message (Conv, System_Role, "System prompt.");
      Append_Message (Conv, User, "Hello.");
      Append_Message (Conv, Assistant, "Hi there.");

      declare
         Msgs : constant Message_Array := Format_For_Provider (Conv);
      begin
         Assert (Msgs'Length = 3,           "Format_For_Provider: length = 3");
         Assert (Msgs (1).Role = System_Role, "Format_For_Provider: msg 1 = System");
         Assert (Msgs (2).Role = User,        "Format_For_Provider: msg 2 = User");
         Assert (Msgs (3).Role = Assistant,   "Format_For_Provider: msg 3 = Assistant");
      end;
   end Test_Format_For_Provider;

   ---------------------------------------------------------
   --  Section 8: Compact_Oldest_Turn - user+assistant pair
   ---------------------------------------------------------
   procedure Test_Compact_Pair is
      Conv : Conversation;
   begin
      Put_Line ("--- Compact_Oldest_Turn (pair) ---");
      Append_Message (Conv, System_Role, "System prompt.");
      Append_Message (Conv, User,      "What is Ada?");
      Append_Message (Conv, Assistant, "Ada is a strongly typed language.");
      Append_Message (Conv, User,      "Current question.");

      --  Before compaction: 4 messages
      Assert (Conv.Msg_Count = 4, "Before compact: Msg_Count = 4");

      Compact_Oldest_Turn (Conv);

      --  After compaction: user+assistant pair at pos 2+3 collapsed to 1 stub
      Assert (Conv.Msg_Count = 3, "After compact pair: Msg_Count = 3");
      Assert (Conv.Messages (1).Role = System_Role,
              "System prompt still at position 1");
      declare
         Stub : constant String := To_String (Conv.Messages (2).Content);
      begin
         Assert (Conv.Messages (2).Role = User,
                 "Compaction stub has User role");
         Assert (Stub'Length > 0 and then Stub (Stub'First) = '[',
                 "Compaction stub starts with '['");
         Assert (Ada.Strings.Unbounded.Index
                   (Conv.Messages (2).Content, "Ada") > 0
                 or else Ada.Strings.Unbounded.Index
                   (Conv.Messages (2).Content, "Ada is") > 0
                 or else Ada.Strings.Unbounded.Index
                   (Conv.Messages (2).Content, "What is") > 0,
                 "Compaction stub references original content");
      end;
      Assert (To_String (Conv.Messages (3).Content) = "Current question.",
              "Newest message retained after compact");
   end Test_Compact_Pair;

   ---------------------------------------------------------
   --  Section 9: Compact_Oldest_Turn - no-op on short conversation
   ---------------------------------------------------------
   procedure Test_Compact_Short is
      Conv : Conversation;
   begin
      Put_Line ("--- Compact_Oldest_Turn (short, no-op) ---");
      Append_Message (Conv, System_Role, "System prompt.");

      --  Single message: compaction must not crash or corrupt
      Compact_Oldest_Turn (Conv);
      Assert (Conv.Msg_Count = 1, "Compact on 1 msg leaves count = 1");
      Assert (Conv.Messages (1).Role = System_Role,
              "System message intact after no-op compact");
   end Test_Compact_Short;

   ---------------------------------------------------------
   --  Section 10: Compact_Oldest_Turn - non-pair eviction
   ---------------------------------------------------------
   procedure Test_Compact_Non_Pair is
      Conv : Conversation;
   begin
      Put_Line ("--- Compact_Oldest_Turn (non-pair drop) ---");
      --  Two User messages in a row (no assistant between them)
      Append_Message (Conv, System_Role, "System.");
      Append_Message (Conv, User,        "First user.");
      Append_Message (Conv, User,        "Second user.");

      Assert (Conv.Msg_Count = 3, "Before compact: Msg_Count = 3");
      Compact_Oldest_Turn (Conv);
      Assert (Conv.Msg_Count = 2, "Non-pair compact drops one message");
      Assert (Conv.Messages (1).Role = System_Role,
              "System prompt preserved in non-pair compact");
      Assert (To_String (Conv.Messages (2).Content) = "Second user.",
              "Second user message retained after non-pair drop");
   end Test_Compact_Non_Pair;

   ---------------------------------------------------------
   --  Section 11: Compaction_Needed threshold
   ---------------------------------------------------------
   procedure Test_Compaction_Needed is
      use Config.Schema;
      Conv : Conversation;
      Lim  : constant History_Limit := 10;
   begin
      Put_Line ("--- Compaction_Needed ---");

      --  Disabled (0)
      Assert (not Compaction_Needed (Conv, 0, Lim),
              "Compaction_Needed: threshold 0 always false");

      --  Empty conversation at threshold 80 -> 0 * 100 / 10 = 0 < 80
      Assert (not Compaction_Needed (Conv, 80, Lim),
              "Compaction_Needed: empty conv below threshold");

      --  Fill to 8 messages: 8*100/10 = 80 >= 80 -> True
      for I in 1 .. 8 loop
         Append_Message (Conv, User, "msg" & Integer'Image (I), Limit => Lim);
      end loop;
      Assert (Compaction_Needed (Conv, 80, Lim),
              "Compaction_Needed: 80 % fill at threshold 80 -> True");

      --  At threshold 90 -> 8*100/10 = 80 < 90 -> False
      Assert (not Compaction_Needed (Conv, 90, Lim),
              "Compaction_Needed: 80 % fill below threshold 90 -> False");
   end Test_Compaction_Needed;

   ---------------------------------------------------------
   --  Section 12: Compact_Summary_Len truncation boundary
   ---------------------------------------------------------
   procedure Test_Compact_Truncation is
      Conv : Conversation;
      Long : constant String (1 .. Compact_Summary_Len + 20) :=
        (others => 'x');
   begin
      Put_Line ("--- Compact_Oldest_Turn (truncation) ---");
      Append_Message (Conv, System_Role, "System.");
      Append_Message (Conv, User,        Long);
      Append_Message (Conv, Assistant,   Long);
      Append_Message (Conv, User,        "Follow-up.");

      Compact_Oldest_Turn (Conv);

      Assert (Conv.Msg_Count = 3, "Truncation test: Msg_Count = 3 after compact");
      declare
         Stub : constant String := To_String (Conv.Messages (2).Content);
         Max_Stub_Len : constant := 10  -- "[Earlier: "
                                   + Compact_Summary_Len  -- user head
                                   + 4                    -- " → "
                                   + Compact_Summary_Len  -- assistant head
                                   + 1;                   -- "]"
      begin
         Assert (Stub'Length <= Max_Stub_Len,
                 "Compaction stub respects Compact_Summary_Len bound");
      end;
   end Test_Compact_Truncation;

begin
   Put_Line ("=== agent_context_test ===");
   Test_Append;
   Test_Last_User_Message;
   Test_Token_Estimate;
   Test_Eviction;
   Test_Configured_Limit;
   Test_Session_ID;
   Test_Format_For_Provider;
   Test_Compact_Pair;
   Test_Compact_Short;
   Test_Compact_Non_Pair;
   Test_Compaction_Needed;
   Test_Compact_Truncation;

   Put_Line ("");
   Put_Line ("Results: " & Natural'Image (Passed) & " passed, "
             & Natural'Image (Failed) & " failed");
   if Failed > 0 then
      raise Program_Error with Natural'Image (Failed) & " test(s) failed";
   end if;
end Agent_Context_Test;
