package Channels.Bridge_Polling
  with SPARK_Mode => Off
is

   type Backoff_State is private;

   procedure Initialize
     (State      : out Backoff_State;
      Base_Delay : Duration;
      Max_Delay  : Duration);

   procedure Record_Success (State : in out Backoff_State);

   procedure Record_Failure (State : in out Backoff_State);

   function Current_Delay (State : Backoff_State) return Duration;

private

   type Backoff_State is record
      Base_Delay : Duration := 2.0;
      Max_Delay  : Duration := 30.0;
      Delay_Now  : Duration := 2.0;
   end record;

end Channels.Bridge_Polling;
