--  Cost tracking for LLM provider calls.
--  Thread-safe via a protected object; tracks per-provider token usage and cost.

pragma SPARK_Mode (Off);
package Metrics.Cost is

   procedure Record_Usage
     (Provider_Label   : String;
      Tokens_In        : Natural;
      Tokens_Out       : Natural;
      Price_In_Per_1K  : Float;
      Price_Out_Per_1K : Float);

   function Total_Cost return Float;
   function Total_Tokens_In return Natural;
   function Total_Tokens_Out return Natural;

   type Provider_Usage is record
      Label      : String (1 .. 32);
      Label_Len  : Natural := 0;
      Tokens_In  : Natural := 0;
      Tokens_Out : Natural := 0;
      Cost       : Float   := 0.0;
   end record;

   Max_Providers : constant := 8;
   type Usage_Array is array (1 .. Max_Providers) of Provider_Usage;

   procedure Get_All_Usage (Usage : out Usage_Array; Count : out Natural);

end Metrics.Cost;
