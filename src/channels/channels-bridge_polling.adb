package body Channels.Bridge_Polling
  with SPARK_Mode => Off
is

   procedure Initialize
     (State      : out Backoff_State;
      Base_Delay : Duration;
      Max_Delay  : Duration)
   is
   begin
      State.Base_Delay := Base_Delay;
      if Max_Delay < Base_Delay then
         State.Max_Delay := Base_Delay;
      else
         State.Max_Delay := Max_Delay;
      end if;
      State.Delay_Now := State.Base_Delay;
   end Initialize;

   procedure Record_Success (State : in out Backoff_State) is
   begin
      State.Delay_Now := State.Base_Delay;
   end Record_Success;

   procedure Record_Failure (State : in out Backoff_State) is
      Next_Delay : constant Duration := State.Delay_Now + State.Delay_Now;
   begin
      if Next_Delay > State.Max_Delay then
         State.Delay_Now := State.Max_Delay;
      else
         State.Delay_Now := Next_Delay;
      end if;
   end Record_Failure;

   function Current_Delay (State : Backoff_State) return Duration is
   begin
      return State.Delay_Now;
   end Current_Delay;

end Channels.Bridge_Polling;
