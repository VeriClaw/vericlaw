package body Channels.Message_Dedup is

   function Was_Seen (D : Dedup_Buffer; Msg_ID : String) return Boolean is
   begin
      for S of D.IDs loop
         if To_String (S) = Msg_ID then
            return True;
         end if;
      end loop;
      return False;
   end Was_Seen;

   procedure Mark_Seen (D : in out Dedup_Buffer; Msg_ID : String) is
   begin
      Set_Unbounded_String (D.IDs (D.Next), Msg_ID);
      D.Next := D.Next + 1;
   end Mark_Seen;

end Channels.Message_Dedup;
