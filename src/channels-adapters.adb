
package body Channels.Adapters with SPARK_Mode is
   function To_Inbound_Decision
     (Decision : Channels.Security.Channel_Request_Decision)
      return Inbound_Decision is
   begin
      case Decision is
         when Channels.Security.Channel_Request_Allow =>
            return Inbound_Accept;
         when Channels.Security.Channel_Request_Deny_Allowlist =>
            return Inbound_Deny_Allowlist;
         when Channels.Security.Channel_Request_Deny_Rate_Limit =>
            return Inbound_Deny_Rate_Limit;
         when Channels.Security.Channel_Request_Deny_Replay =>
            return Inbound_Deny_Replay;
      end case;
   end To_Inbound_Decision;

   function To_Outbound_Decision
     (Decision : Channels.Security.Channel_Request_Decision)
      return Outbound_Decision is
   begin
      case Decision is
         when Channels.Security.Channel_Request_Allow =>
            return Outbound_Eligible;
         when Channels.Security.Channel_Request_Deny_Allowlist =>
            return Outbound_Deny_Allowlist;
         when Channels.Security.Channel_Request_Deny_Rate_Limit =>
            return Outbound_Deny_Rate_Limit;
         when Channels.Security.Channel_Request_Deny_Replay =>
            return Outbound_Deny_Replay;
      end case;
   end To_Outbound_Decision;

   function Evaluate_Security_Context
     (Channel : Channels.Security.Channel_Kind;
      Context : Security_Context) return Channels.Security.Channel_Request_Result
   is
   begin
      return
        Channels.Security.Evaluate_Channel_Request
          (Channel                 => Channel,
           Allowlist_Size          => Context.Allowlist_Size,
           Candidate_Matches       => Context.Candidate_Matches,
           Limiter_Configured      => Context.Limiter_Configured,
           Requests_In_Window      => Context.Requests_In_Window,
           Max_Requests            => Context.Max_Requests,
           Idempotency_Key_Present => Context.Idempotency_Key_Present,
           Seen_Before             => Context.Seen_Before);
   end Evaluate_Security_Context;

   function Inbound_Acceptance
     (Channel         : Channels.Security.Channel_Kind;
      Channel_Enabled : Boolean;
      Context         : Security_Context) return Inbound_Result is
      Security_Result : Channels.Security.Channel_Request_Result;
   begin
      if not Channel_Enabled then
         return
           (Accepted => False, Decision => Inbound_Deny_Channel_Disabled);
      end if;

      Security_Result :=
        Evaluate_Security_Context (Channel => Channel, Context => Context);
      return
        (Accepted => Security_Result.Allowed,
         Decision => To_Inbound_Decision (Security_Result.Decision));
   end Inbound_Acceptance;

   function Inbound_Acceptance
     (Channel : Channels.Security.Channel_Kind;
      Context : Security_Context) return Inbound_Result is
   begin
      return
        Inbound_Acceptance
          (Channel         => Channel,
           Channel_Enabled => True,
           Context         => Context);
   end Inbound_Acceptance;

   function Outbound_Eligibility
     (Channel         : Channels.Security.Channel_Kind;
      Channel_Enabled : Boolean;
      Context         : Security_Context) return Outbound_Result is
      Security_Result : constant Channels.Security.Channel_Request_Result :=
        Evaluate_Security_Context (Channel => Channel, Context => Context);
   begin
      if not Channel_Enabled then
         return
            (Eligible => False, Decision => Outbound_Deny_Channel_Disabled);
      end if;

      return
        (Eligible => Security_Result.Allowed,
         Decision => To_Outbound_Decision (Security_Result.Decision));
   end Outbound_Eligibility;
end Channels.Adapters;
