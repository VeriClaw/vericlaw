package Channels.Security with SPARK_Mode is
   type Channel_Kind is
     (CLI_Channel,
      Webhook_Channel,
      Chat_Channel,
      Telegram_Channel,
      Discord_Channel,
      Slack_Channel,
      WhatsApp_Bridge_Channel,
      Email_Channel);

   type Allowlist_Decision is
     (Allowlist_Allow,
      Allowlist_Deny_Empty_Allowlist,
      Allowlist_Deny_Not_Allowlisted);

   function Allowlist_Policy_Decision
     (Channel           : Channel_Kind;
      Allowlist_Size    : Natural;
      Candidate_Matches : Boolean) return Allowlist_Decision
   with
     Post =>
       (if Allowlist_Size = 0 then
           Allowlist_Policy_Decision'Result = Allowlist_Deny_Empty_Allowlist
        elsif Candidate_Matches then
           Allowlist_Policy_Decision'Result = Allowlist_Allow
        else
           Allowlist_Policy_Decision'Result = Allowlist_Deny_Not_Allowlisted);

   function Allowlist_Allows
     (Channel           : Channel_Kind;
      Allowlist_Size    : Natural;
      Candidate_Matches : Boolean) return Boolean
   with
     Post =>
       Allowlist_Allows'Result =
         (Allowlist_Policy_Decision
            (Channel           => Channel,
             Allowlist_Size    => Allowlist_Size,
             Candidate_Matches => Candidate_Matches) = Allowlist_Allow);

   type Rate_Limit_Decision is
     (Rate_Limit_Allow,
      Rate_Limit_Deny_Not_Configured,
      Rate_Limit_Deny_Window_Exceeded);

   function Rate_Limit_Policy_Decision
     (Limiter_Configured : Boolean;
      Requests_In_Window : Natural;
      Max_Requests       : Natural) return Rate_Limit_Decision
   with
     Post =>
       (if not Limiter_Configured then
           Rate_Limit_Policy_Decision'Result = Rate_Limit_Deny_Not_Configured
        elsif Requests_In_Window > Max_Requests then
           Rate_Limit_Policy_Decision'Result = Rate_Limit_Deny_Window_Exceeded
        else
           Rate_Limit_Policy_Decision'Result = Rate_Limit_Allow);

   function Rate_Limit_Allows
     (Limiter_Configured : Boolean;
      Requests_In_Window : Natural;
      Max_Requests       : Natural) return Boolean
   with
     Post =>
       Rate_Limit_Allows'Result =
         (Rate_Limit_Policy_Decision
            (Limiter_Configured => Limiter_Configured,
             Requests_In_Window => Requests_In_Window,
             Max_Requests       => Max_Requests) = Rate_Limit_Allow);

   type Replay_Decision is
     (Replay_Allow,
      Replay_Deny_Missing_Idempotency_Key,
      Replay_Deny_Seen_Before);

   function Replay_Policy_Decision
     (Idempotency_Key_Present : Boolean;
      Seen_Before             : Boolean) return Replay_Decision
   with
     Post =>
       (if not Idempotency_Key_Present then
           Replay_Policy_Decision'Result = Replay_Deny_Missing_Idempotency_Key
        elsif Seen_Before then
           Replay_Policy_Decision'Result = Replay_Deny_Seen_Before
        else
           Replay_Policy_Decision'Result = Replay_Allow);

   function Replay_Protected
     (Idempotency_Key_Present : Boolean;
      Seen_Before             : Boolean) return Boolean
   with
     Post =>
       Replay_Protected'Result =
         (Replay_Policy_Decision
            (Idempotency_Key_Present => Idempotency_Key_Present,
             Seen_Before             => Seen_Before) = Replay_Allow);

   type Channel_Request_Decision is
     (Channel_Request_Allow,
      Channel_Request_Deny_Allowlist,
      Channel_Request_Deny_Rate_Limit,
      Channel_Request_Deny_Replay);

   type Channel_Request_Result is record
      Allowed  : Boolean := False;
      Decision : Channel_Request_Decision := Channel_Request_Deny_Allowlist;
   end record;

   function Evaluate_Channel_Request
     (Channel                 : Channel_Kind;
      Allowlist_Size          : Natural;
      Candidate_Matches       : Boolean;
      Limiter_Configured      : Boolean;
      Requests_In_Window      : Natural;
      Max_Requests            : Natural;
      Idempotency_Key_Present : Boolean;
      Seen_Before             : Boolean) return Channel_Request_Result
   with
     Post =>
       (if Evaluate_Channel_Request'Result.Allowed then
           Evaluate_Channel_Request'Result.Decision = Channel_Request_Allow
        else
           Evaluate_Channel_Request'Result.Decision /= Channel_Request_Allow);
end Channels.Security;
