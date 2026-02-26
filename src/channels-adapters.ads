with Channels.Security;

package Channels.Adapters with SPARK_Mode is
   type Security_Context is record
      Allowlist_Size          : Natural := 0;
      Candidate_Matches       : Boolean := False;
      Limiter_Configured      : Boolean := False;
      Requests_In_Window      : Natural := 0;
      Max_Requests            : Natural := 0;
      Idempotency_Key_Present : Boolean := False;
      Seen_Before             : Boolean := False;
   end record;

   type Inbound_Decision is
     (Inbound_Accept,
      Inbound_Deny_Channel_Disabled,
      Inbound_Deny_Allowlist,
      Inbound_Deny_Rate_Limit,
      Inbound_Deny_Replay);

   type Inbound_Result is record
      Accepted : Boolean := False;
      Decision : Inbound_Decision := Inbound_Deny_Channel_Disabled;
   end record;

   function Inbound_Acceptance
      (Channel         : Channels.Security.Channel_Kind;
       Channel_Enabled : Boolean;
       Context         : Security_Context) return Inbound_Result
   with
      Post =>
        (if Inbound_Acceptance'Result.Accepted then
            Inbound_Acceptance'Result.Decision = Inbound_Accept
         else
            Inbound_Acceptance'Result.Decision /= Inbound_Accept);

   function Inbound_Acceptance
      (Channel : Channels.Security.Channel_Kind;
       Context : Security_Context) return Inbound_Result
   with
      Post =>
        (if Inbound_Acceptance'Result.Accepted then
            Inbound_Acceptance'Result.Decision = Inbound_Accept
         else
            Inbound_Acceptance'Result.Decision /= Inbound_Accept);

   type Outbound_Decision is
     (Outbound_Eligible,
      Outbound_Deny_Channel_Disabled,
      Outbound_Deny_Allowlist,
      Outbound_Deny_Rate_Limit,
      Outbound_Deny_Replay);

   type Outbound_Result is record
      Eligible : Boolean := False;
      Decision : Outbound_Decision := Outbound_Deny_Channel_Disabled;
   end record;

   function Outbound_Eligibility
     (Channel         : Channels.Security.Channel_Kind;
      Channel_Enabled : Boolean;
      Context         : Security_Context) return Outbound_Result
   with
     Post =>
       (if Outbound_Eligibility'Result.Eligible then
           Outbound_Eligibility'Result.Decision = Outbound_Eligible
        else
           Outbound_Eligibility'Result.Decision /= Outbound_Eligible);
end Channels.Adapters;
