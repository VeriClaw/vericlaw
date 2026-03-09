pragma SPARK_Mode (Off);
package body Metrics.Cost is

   protected Store is
      procedure Log_Entry
        (Provider_Label   : String;
         Tokens_In        : Natural;
         Tokens_Out       : Natural;
         Price_In_Per_1K  : Float;
         Price_Out_Per_1K : Float);
      function Get_Total_Cost return Float;
      function Get_Total_Tokens_In return Natural;
      function Get_Total_Tokens_Out return Natural;
      procedure Snapshot (Usage : out Usage_Array; Count : out Natural);
   private
      Entries : Usage_Array;
      Size    : Natural := 0;
   end Store;

   protected body Store is

      procedure Log_Entry
        (Provider_Label   : String;
         Tokens_In        : Natural;
         Tokens_Out       : Natural;
         Price_In_Per_1K  : Float;
         Price_Out_Per_1K : Float)
      is
         Call_Cost : constant Float :=
           Float (Tokens_In)  * Price_In_Per_1K  / 1000.0 +
           Float (Tokens_Out) * Price_Out_Per_1K / 1000.0;
      begin
         --  Find existing entry for this provider.
         for I in 1 .. Size loop
            if Entries (I).Label (1 .. Entries (I).Label_Len) =
              Provider_Label
            then
               Entries (I).Tokens_In  := Entries (I).Tokens_In  + Tokens_In;
               Entries (I).Tokens_Out := Entries (I).Tokens_Out + Tokens_Out;
               Entries (I).Cost       := Entries (I).Cost + Call_Cost;
               return;
            end if;
         end loop;
         --  New provider entry.
         if Size < Max_Providers then
            Size := Size + 1;
            Entries (Size).Label     := (others => ' ');
            declare
               Len : constant Natural :=
                 Natural'Min (Provider_Label'Length, 32);
            begin
               Entries (Size).Label (1 .. Len) :=
                 Provider_Label (Provider_Label'First ..
                                 Provider_Label'First + Len - 1);
               Entries (Size).Label_Len := Len;
            end;
            Entries (Size).Tokens_In  := Tokens_In;
            Entries (Size).Tokens_Out := Tokens_Out;
            Entries (Size).Cost       := Call_Cost;
         end if;
      end Log_Entry;

      function Get_Total_Cost return Float is
         Sum : Float := 0.0;
      begin
         for I in 1 .. Size loop
            Sum := Sum + Entries (I).Cost;
         end loop;
         return Sum;
      end Get_Total_Cost;

      function Get_Total_Tokens_In return Natural is
         Sum : Natural := 0;
      begin
         for I in 1 .. Size loop
            Sum := Sum + Entries (I).Tokens_In;
         end loop;
         return Sum;
      end Get_Total_Tokens_In;

      function Get_Total_Tokens_Out return Natural is
         Sum : Natural := 0;
      begin
         for I in 1 .. Size loop
            Sum := Sum + Entries (I).Tokens_Out;
         end loop;
         return Sum;
      end Get_Total_Tokens_Out;

      procedure Snapshot (Usage : out Usage_Array; Count : out Natural) is
      begin
         Usage := Entries;
         Count := Size;
      end Snapshot;

   end Store;

   procedure Record_Usage
     (Provider_Label   : String;
      Tokens_In        : Natural;
      Tokens_Out       : Natural;
      Price_In_Per_1K  : Float;
      Price_Out_Per_1K : Float)
   is
   begin
      Store.Log_Entry
        (Provider_Label, Tokens_In, Tokens_Out,
         Price_In_Per_1K, Price_Out_Per_1K);
   end Record_Usage;

   function Total_Cost return Float is
   begin
      return Store.Get_Total_Cost;
   end Total_Cost;

   function Total_Tokens_In return Natural is
   begin
      return Store.Get_Total_Tokens_In;
   end Total_Tokens_In;

   function Total_Tokens_Out return Natural is
   begin
      return Store.Get_Total_Tokens_Out;
   end Total_Tokens_Out;

   procedure Get_All_Usage (Usage : out Usage_Array; Count : out Natural) is
   begin
      Store.Snapshot (Usage, Count);
   end Get_All_Usage;

end Metrics.Cost;
