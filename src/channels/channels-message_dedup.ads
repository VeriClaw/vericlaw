with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

--  Client-side message deduplication ring buffer.
--  Tracks the last Max_Seen_IDs message IDs to prevent reprocessing a
--  message when the bridge buffer is polled before it is fully drained.
--  Each channel that polls a bridge should declare its own Dedup_Buffer
--  as a package-body variable.
package Channels.Message_Dedup is

   Max_Seen_IDs : constant := 100;

   type Dedup_Buffer is private;

   --  Return True if Msg_ID was previously recorded in D.
   function Was_Seen (D : Dedup_Buffer; Msg_ID : String) return Boolean;

   --  Record Msg_ID in D (circular overwrite when the buffer is full).
   procedure Mark_Seen (D : in out Dedup_Buffer; Msg_ID : String);

private

   type Seen_Index is mod Max_Seen_IDs;
   type Seen_Array is array (Seen_Index) of Unbounded_String;

   type Dedup_Buffer is record
      IDs  : Seen_Array := (others => Null_Unbounded_String);
      Next : Seen_Index := 0;
   end record;

end Channels.Message_Dedup;
