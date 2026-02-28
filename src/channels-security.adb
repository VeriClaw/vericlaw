package body Channels.Security with SPARK_Mode is
   function Base_Allowlist_Decision
     (Allowlist_Size    : Natural;
      Candidate_Matches : Boolean) return Allowlist_Decision is
   begin
      if Allowlist_Size = 0 then
         return Allowlist_Deny_Empty_Allowlist;
      elsif Candidate_Matches then
         return Allowlist_Allow;
      else
         return Allowlist_Deny_Not_Allowlisted;
      end if;
   end Base_Allowlist_Decision;

   function Allowlist_Policy_Decision
     (Channel           : Channel_Kind;
      Allowlist_Size    : Natural;
      Candidate_Matches : Boolean) return Allowlist_Decision is
   begin
      pragma Unreferenced (Channel);
      return Base_Allowlist_Decision (Allowlist_Size, Candidate_Matches);
   end Allowlist_Policy_Decision;

   function Allowlist_Allows
     (Channel           : Channel_Kind;
      Allowlist_Size    : Natural;
      Candidate_Matches : Boolean) return Boolean is
   begin
      return Allowlist_Policy_Decision
        (Channel           => Channel,
         Allowlist_Size    => Allowlist_Size,
         Candidate_Matches => Candidate_Matches) = Allowlist_Allow;
   end Allowlist_Allows;

   function Rate_Limit_Policy_Decision
     (Limiter_Configured : Boolean;
      Requests_In_Window : Natural;
      Max_Requests       : Natural) return Rate_Limit_Decision is
   begin
      if not Limiter_Configured then
         return Rate_Limit_Deny_Not_Configured;
      elsif Requests_In_Window > Max_Requests then
         return Rate_Limit_Deny_Window_Exceeded;
      else
         return Rate_Limit_Allow;
      end if;
   end Rate_Limit_Policy_Decision;

   function Rate_Limit_Allows
     (Limiter_Configured : Boolean;
      Requests_In_Window : Natural;
      Max_Requests       : Natural) return Boolean is
   begin
      return Rate_Limit_Policy_Decision
        (Limiter_Configured => Limiter_Configured,
         Requests_In_Window => Requests_In_Window,
         Max_Requests       => Max_Requests) = Rate_Limit_Allow;
   end Rate_Limit_Allows;

   function Replay_Policy_Decision
     (Idempotency_Key_Present : Boolean;
      Seen_Before             : Boolean) return Replay_Decision is
   begin
      if not Idempotency_Key_Present then
         return Replay_Deny_Missing_Idempotency_Key;
      elsif Seen_Before then
         return Replay_Deny_Seen_Before;
      else
         return Replay_Allow;
      end if;
   end Replay_Policy_Decision;

   function Replay_Protected
     (Idempotency_Key_Present : Boolean;
      Seen_Before             : Boolean) return Boolean is
   begin
      return Replay_Policy_Decision
        (Idempotency_Key_Present => Idempotency_Key_Present,
         Seen_Before             => Seen_Before) = Replay_Allow;
   end Replay_Protected;

   function Evaluate_Channel_Request
     (Channel                 : Channel_Kind;
      Allowlist_Size          : Natural;
      Candidate_Matches       : Boolean;
      Limiter_Configured      : Boolean;
      Requests_In_Window      : Natural;
      Max_Requests            : Natural;
      Idempotency_Key_Present : Boolean;
      Seen_Before             : Boolean) return Channel_Request_Result is
   begin
      if Allowlist_Policy_Decision
          (Channel           => Channel,
           Allowlist_Size    => Allowlist_Size,
           Candidate_Matches => Candidate_Matches) /= Allowlist_Allow
      then
         return (Allowed => False, Decision => Channel_Request_Deny_Allowlist);
      elsif Rate_Limit_Policy_Decision
          (Limiter_Configured => Limiter_Configured,
           Requests_In_Window => Requests_In_Window,
           Max_Requests       => Max_Requests) /= Rate_Limit_Allow
      then
         return (Allowed => False, Decision => Channel_Request_Deny_Rate_Limit);
      elsif Replay_Policy_Decision
          (Idempotency_Key_Present => Idempotency_Key_Present,
           Seen_Before             => Seen_Before) /= Replay_Allow
      then
         return (Allowed => False, Decision => Channel_Request_Deny_Replay);
      end if;

      return (Allowed => True, Decision => Channel_Request_Allow);
   end Evaluate_Channel_Request;
end Channels.Security;
