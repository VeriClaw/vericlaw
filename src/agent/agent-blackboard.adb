pragma SPARK_Mode (Off);
package body Agent.Blackboard is

   type KV_Entry is record
      Key   : Unbounded_String;
      Value : Unbounded_String;
      Used  : Boolean := False;
   end record;

   type KV_Array is array (1 .. Max_Entries) of KV_Entry;

   protected Store is
      procedure Write (Key : String; Value : String);
      function  Read  (Key : String) return String;
      function  Exists (Key : String) return Boolean;
      procedure Reset;
   private
      Entries : KV_Array;
      Count   : Natural := 0;
      Next_Slot : Positive := 1;  -- round-robin eviction pointer
   end Store;

   protected body Store is

      procedure Write (Key : String; Value : String) is
         K : constant Unbounded_String := To_Unbounded_String (Key);
      begin
         --  Update existing entry if key matches.
         for I in Entries'Range loop
            if Entries (I).Used and then Entries (I).Key = K then
               Set_Unbounded_String (Entries (I).Value, Value);
               return;
            end if;
         end loop;
         --  Insert into next slot (evicting if full).
         Entries (Next_Slot) :=
           (Key   => K,
            Value  => To_Unbounded_String (Value),
            Used   => True);
         if Count < Max_Entries then
            Count := Count + 1;
         end if;
         if Next_Slot = Max_Entries then
            Next_Slot := 1;
         else
            Next_Slot := Next_Slot + 1;
         end if;
      end Write;

      function Read (Key : String) return String is
         K : constant Unbounded_String := To_Unbounded_String (Key);
      begin
         for I in Entries'Range loop
            if Entries (I).Used and then Entries (I).Key = K then
               return To_String (Entries (I).Value);
            end if;
         end loop;
         return "";
      end Read;

      function Exists (Key : String) return Boolean is
         K : constant Unbounded_String := To_Unbounded_String (Key);
      begin
         for I in Entries'Range loop
            if Entries (I).Used and then Entries (I).Key = K then
               return True;
            end if;
         end loop;
         return False;
      end Exists;

      procedure Reset is
      begin
         Entries   := (others => <>);
         Count     := 0;
         Next_Slot := 1;
      end Reset;

   end Store;

   procedure Put (Key : String; Value : String) is
   begin
      Store.Write (Key, Value);
   end Put;

   function Get (Key : String) return String is
   begin
      return Store.Read (Key);
   end Get;

   function Has (Key : String) return Boolean is
   begin
      return Store.Exists (Key);
   end Has;

   procedure Clear is
   begin
      Store.Reset;
   end Clear;

end Agent.Blackboard;
