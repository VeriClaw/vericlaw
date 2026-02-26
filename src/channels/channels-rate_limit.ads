--  Simple per-session rate limiter for inbound channel messages.
--  Uses a 1-second sliding window: if more than Max_RPS messages
--  arrive from the same session within a second, Check returns False.

package Channels.Rate_Limit is

   --  Check whether a new message from Session_Key is within limits.
   --  Returns False (and does not count the request) if rate exceeded.
   function Check (Session_Key : String; Max_RPS : Positive) return Boolean;

end Channels.Rate_Limit;
