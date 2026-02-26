with Ada.Calendar;
with Ada.Numerics.Discrete_Random;

package body Agent.Context is

   package Rand_Char is new Ada.Numerics.Discrete_Random (Character);
   Rng : Rand_Char.Generator;

   Hex_Chars : constant String := "0123456789abcdef";

   function Make_Session_ID return String is
      Result : String (1 .. 16);
   begin
      Rand_Char.Reset (Rng);
      for I in Result'Range loop
         Result (I) :=
           Hex_Chars (1 + Character'Pos (Rand_Char.Random (Rng)) mod 16);
      end loop;
      return Result;
   end Make_Session_ID;

   procedure Append_Message
     (Conv    : in out Conversation;
      Role    : Agent.Context.Role;
      Content : String;
      Name    : String := "")
   is
      New_Msg : constant Message :=
        (Role    => Role,
         Content => To_Unbounded_String (Content),
         Name    => To_Unbounded_String (Name));
   begin
      if Conv.Msg_Count < Max_History then
         Conv.Msg_Count := Conv.Msg_Count + 1;
         Conv.Messages (Conv.Msg_Count) := New_Msg;
      else
         --  Evict oldest non-system message (shift left from index 2).
         --  Index 1 is always the system prompt if present; preserve it.
         declare
            Start : constant Positive :=
              (if Conv.Messages (1).Role = System_Role then 2 else 1);
         begin
            Conv.Messages (Start .. Max_History - 1) :=
              Conv.Messages (Start + 1 .. Max_History);
            Conv.Messages (Max_History) := New_Msg;
         end;
      end if;
   end Append_Message;

   function Last_User_Message (Conv : Conversation) return String is
   begin
      for I in reverse 1 .. Conv.Msg_Count loop
         if Conv.Messages (I).Role = User then
            return To_String (Conv.Messages (I).Content);
         end if;
      end loop;
      return "";
   end Last_User_Message;

   function Format_For_Provider
     (Conv : Conversation) return Message_Array
   is
   begin
      return Conv.Messages (1 .. Conv.Msg_Count);
   end Format_For_Provider;

   function Token_Estimate (Conv : Conversation) return Natural is
      Total : Natural := 0;
   begin
      for I in 1 .. Conv.Msg_Count loop
         Total := Total + Length (Conv.Messages (I).Content) / 4 + 4;
      end loop;
      return Total;
   end Token_Estimate;

end Agent.Context;
