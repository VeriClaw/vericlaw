with Channels.Adapters;
with Channels.Adapters.Discord;
with Channels.Adapters.Email;
with Channels.Adapters.Slack;
with Channels.Adapters.Telegram;
with Channels.Adapters.WhatsApp_Bridge;
with Channels.Security;

procedure Channel_Adapter_Policy is
   use type Channels.Adapters.Inbound_Decision;
   use type Channels.Adapters.Outbound_Decision;

   Base_Context : constant Channels.Adapters.Security_Context :=
     (Allowlist_Size          => 1,
      Candidate_Matches       => True,
      Limiter_Configured      => True,
      Requests_In_Window      => 1,
      Max_Requests            => 10,
      Idempotency_Key_Present => True,
      Seen_Before             => False);
   Allowlist_Deny_Context : constant Channels.Adapters.Security_Context :=
     (Allowlist_Size          => 0,
      Candidate_Matches       => True,
      Limiter_Configured      => True,
      Requests_In_Window      => 1,
      Max_Requests            => 10,
      Idempotency_Key_Present => True,
      Seen_Before             => False);
   Not_Allowlisted_Deny_Context : constant Channels.Adapters.Security_Context :=
     (Allowlist_Size          => 1,
      Candidate_Matches       => False,
      Limiter_Configured      => True,
      Requests_In_Window      => 1,
      Max_Requests            => 10,
      Idempotency_Key_Present => True,
      Seen_Before             => False);
   Rate_Limit_Deny_Context : constant Channels.Adapters.Security_Context :=
     (Allowlist_Size          => 1,
      Candidate_Matches       => True,
      Limiter_Configured      => True,
      Requests_In_Window      => 11,
      Max_Requests            => 10,
      Idempotency_Key_Present => True,
      Seen_Before             => False);
   Replay_Deny_Context : constant Channels.Adapters.Security_Context :=
     (Allowlist_Size          => 1,
      Candidate_Matches       => True,
      Limiter_Configured      => True,
      Requests_In_Window      => 1,
      Max_Requests            => 10,
      Idempotency_Key_Present => True,
      Seen_Before             => True);
   Missing_Idempotency_Key_Context : constant Channels.Adapters.Security_Context :=
     (Allowlist_Size          => 1,
      Candidate_Matches       => True,
      Limiter_Configured      => True,
      Requests_In_Window      => 1,
      Max_Requests            => 10,
      Idempotency_Key_Present => False,
      Seen_Before             => False);

   type Contract_Vector is record
      Channel_Enabled : Boolean;
      Context         : Channels.Adapters.Security_Context;
   end record;

   Contract_Vectors : constant array (Positive range <>) of Contract_Vector :=
     ((Channel_Enabled => True, Context => Base_Context),
      (Channel_Enabled => True, Context => Allowlist_Deny_Context),
      (Channel_Enabled => True, Context => Not_Allowlisted_Deny_Context),
      (Channel_Enabled => True, Context => Rate_Limit_Deny_Context),
      (Channel_Enabled => True, Context => Replay_Deny_Context),
      (Channel_Enabled => True, Context => Missing_Idempotency_Key_Context),
      (Channel_Enabled => False, Context => Base_Context),
      (Channel_Enabled => False, Context => Allowlist_Deny_Context),
      (Channel_Enabled => False, Context => Not_Allowlisted_Deny_Context),
      (Channel_Enabled => False, Context => Rate_Limit_Deny_Context),
      (Channel_Enabled => False, Context => Replay_Deny_Context),
      (Channel_Enabled => False, Context => Missing_Idempotency_Key_Context));

   function To_Inbound_From_Security
     (Decision : Channels.Security.Channel_Request_Decision)
      return Channels.Adapters.Inbound_Decision is
   begin
      case Decision is
         when Channels.Security.Channel_Request_Allow =>
            return Channels.Adapters.Inbound_Accept;
         when Channels.Security.Channel_Request_Deny_Allowlist =>
            return Channels.Adapters.Inbound_Deny_Allowlist;
         when Channels.Security.Channel_Request_Deny_Rate_Limit =>
            return Channels.Adapters.Inbound_Deny_Rate_Limit;
         when Channels.Security.Channel_Request_Deny_Replay =>
            return Channels.Adapters.Inbound_Deny_Replay;
      end case;
   end To_Inbound_From_Security;

   function To_Outbound_From_Security
     (Decision : Channels.Security.Channel_Request_Decision)
      return Channels.Adapters.Outbound_Decision is
   begin
      case Decision is
         when Channels.Security.Channel_Request_Allow =>
            return Channels.Adapters.Outbound_Eligible;
         when Channels.Security.Channel_Request_Deny_Allowlist =>
            return Channels.Adapters.Outbound_Deny_Allowlist;
         when Channels.Security.Channel_Request_Deny_Rate_Limit =>
            return Channels.Adapters.Outbound_Deny_Rate_Limit;
         when Channels.Security.Channel_Request_Deny_Replay =>
            return Channels.Adapters.Outbound_Deny_Replay;
      end case;
   end To_Outbound_From_Security;

   function To_Outbound_From_Inbound
     (Decision : Channels.Adapters.Inbound_Decision)
      return Channels.Adapters.Outbound_Decision is
   begin
      case Decision is
         when Channels.Adapters.Inbound_Accept =>
            return Channels.Adapters.Outbound_Eligible;
         when Channels.Adapters.Inbound_Deny_Channel_Disabled =>
            return Channels.Adapters.Outbound_Deny_Channel_Disabled;
         when Channels.Adapters.Inbound_Deny_Allowlist =>
            return Channels.Adapters.Outbound_Deny_Allowlist;
         when Channels.Adapters.Inbound_Deny_Rate_Limit =>
            return Channels.Adapters.Outbound_Deny_Rate_Limit;
         when Channels.Adapters.Inbound_Deny_Replay =>
            return Channels.Adapters.Outbound_Deny_Replay;
      end case;
   end To_Outbound_From_Inbound;

   generic
      Channel : Channels.Security.Channel_Kind;
      with function Inbound_Acceptance
        (Channel_Enabled : Boolean;
         Context         : Channels.Adapters.Security_Context)
         return Channels.Adapters.Inbound_Result;
      with function Outbound_Eligibility
        (Channel_Enabled : Boolean;
         Context         : Channels.Adapters.Security_Context)
         return Channels.Adapters.Outbound_Result;
   procedure Assert_Core_Channel_Parity;

   procedure Assert_Core_Channel_Parity is
      Inbound_Result  : Channels.Adapters.Inbound_Result;
      Outbound_Result : Channels.Adapters.Outbound_Result;
      Security_Result : Channels.Security.Channel_Request_Result;
   begin
      for Vector of Contract_Vectors loop
         Inbound_Result :=
           Inbound_Acceptance
             (Channel_Enabled => Vector.Channel_Enabled,
              Context         => Vector.Context);
         Outbound_Result :=
           Outbound_Eligibility
             (Channel_Enabled => Vector.Channel_Enabled,
              Context         => Vector.Context);

         pragma Assert
           (Outbound_Result.Decision =
              To_Outbound_From_Inbound (Inbound_Result.Decision));

         if Vector.Channel_Enabled then
            Security_Result :=
              Channels.Security.Evaluate_Channel_Request
                (Channel                 => Channel,
                 Allowlist_Size          => Vector.Context.Allowlist_Size,
                 Candidate_Matches       => Vector.Context.Candidate_Matches,
                 Limiter_Configured      => Vector.Context.Limiter_Configured,
                 Requests_In_Window      => Vector.Context.Requests_In_Window,
                 Max_Requests            => Vector.Context.Max_Requests,
                 Idempotency_Key_Present =>
                   Vector.Context.Idempotency_Key_Present,
                 Seen_Before             => Vector.Context.Seen_Before);
            pragma Assert (Inbound_Result.Accepted = Security_Result.Allowed);
            pragma Assert (Outbound_Result.Eligible = Security_Result.Allowed);
            pragma Assert
              (Inbound_Result.Decision =
                 To_Inbound_From_Security (Security_Result.Decision));
            pragma Assert
              (Outbound_Result.Decision =
                 To_Outbound_From_Security (Security_Result.Decision));
         else
            pragma Assert
              ((not Inbound_Result.Accepted)
               and then
                 Inbound_Result.Decision =
                   Channels.Adapters.Inbound_Deny_Channel_Disabled);
            pragma Assert
              ((not Outbound_Result.Eligible)
               and then
                 Outbound_Result.Decision =
                   Channels.Adapters.Outbound_Deny_Channel_Disabled);
         end if;
      end loop;
   end Assert_Core_Channel_Parity;

   procedure Assert_Telegram_Parity is new Assert_Core_Channel_Parity
     (Channel              => Channels.Security.Telegram_Channel,
      Inbound_Acceptance   => Channels.Adapters.Telegram.Inbound_Acceptance,
      Outbound_Eligibility => Channels.Adapters.Telegram.Outbound_Eligibility);
   procedure Assert_Discord_Parity is new Assert_Core_Channel_Parity
     (Channel              => Channels.Security.Discord_Channel,
      Inbound_Acceptance   => Channels.Adapters.Discord.Inbound_Acceptance,
      Outbound_Eligibility => Channels.Adapters.Discord.Outbound_Eligibility);
   procedure Assert_Slack_Parity is new Assert_Core_Channel_Parity
     (Channel              => Channels.Security.Slack_Channel,
      Inbound_Acceptance   => Channels.Adapters.Slack.Inbound_Acceptance,
      Outbound_Eligibility => Channels.Adapters.Slack.Outbound_Eligibility);
   procedure Assert_WhatsApp_Parity is new Assert_Core_Channel_Parity
     (Channel              => Channels.Security.WhatsApp_Bridge_Channel,
      Inbound_Acceptance   => Channels.Adapters.WhatsApp_Bridge.Inbound_Acceptance,
      Outbound_Eligibility =>
        Channels.Adapters.WhatsApp_Bridge.Outbound_Eligibility);
   procedure Assert_Email_Parity is new Assert_Core_Channel_Parity
     (Channel              => Channels.Security.Email_Channel,
      Inbound_Acceptance   => Channels.Adapters.Email.Inbound_Acceptance,
      Outbound_Eligibility => Channels.Adapters.Email.Outbound_Eligibility);

   procedure Assert_Long_Tail_Default_Gates is
      Inbound_Result  : Channels.Adapters.Inbound_Result;
      Outbound_Result : Channels.Adapters.Outbound_Result;
   begin
      Inbound_Result :=
        Channels.Adapters.WhatsApp_Bridge.Inbound_Acceptance (Base_Context);
      pragma Assert
        ((not Inbound_Result.Accepted)
         and then
           Inbound_Result.Decision =
             Channels.Adapters.Inbound_Deny_Channel_Disabled);

      Inbound_Result :=
        Channels.Adapters.WhatsApp_Bridge.Inbound_Acceptance
          (Allowlist_Deny_Context);
      pragma Assert
        ((not Inbound_Result.Accepted)
         and then
           Inbound_Result.Decision =
             Channels.Adapters.Inbound_Deny_Channel_Disabled);

      Outbound_Result :=
        Channels.Adapters.WhatsApp_Bridge.Outbound_Eligibility
          (Channel_Enabled => False,
           Context         => Base_Context);
      pragma Assert
        ((not Outbound_Result.Eligible)
         and then
           Outbound_Result.Decision =
             Channels.Adapters.Outbound_Deny_Channel_Disabled);

      Outbound_Result :=
        Channels.Adapters.WhatsApp_Bridge.Outbound_Eligibility
          (Channel_Enabled => False,
           Context         => Allowlist_Deny_Context);
      pragma Assert
        ((not Outbound_Result.Eligible)
         and then
           Outbound_Result.Decision =
             Channels.Adapters.Outbound_Deny_Channel_Disabled);

      Inbound_Result := Channels.Adapters.Email.Inbound_Acceptance (Base_Context);
      pragma Assert
        ((not Inbound_Result.Accepted)
         and then
           Inbound_Result.Decision =
             Channels.Adapters.Inbound_Deny_Channel_Disabled);

      Inbound_Result :=
        Channels.Adapters.Email.Inbound_Acceptance (Rate_Limit_Deny_Context);
      pragma Assert
        ((not Inbound_Result.Accepted)
         and then
           Inbound_Result.Decision =
             Channels.Adapters.Inbound_Deny_Channel_Disabled);

      Outbound_Result :=
        Channels.Adapters.Email.Outbound_Eligibility
          (Channel_Enabled => False,
           Context         => Base_Context);
      pragma Assert
        ((not Outbound_Result.Eligible)
         and then
           Outbound_Result.Decision =
             Channels.Adapters.Outbound_Deny_Channel_Disabled);

      Outbound_Result :=
        Channels.Adapters.Email.Outbound_Eligibility
          (Channel_Enabled => False,
           Context         => Rate_Limit_Deny_Context);
      pragma Assert
        ((not Outbound_Result.Eligible)
         and then
           Outbound_Result.Decision =
             Channels.Adapters.Outbound_Deny_Channel_Disabled);
   end Assert_Long_Tail_Default_Gates;
begin
   Assert_Telegram_Parity;
   Assert_Discord_Parity;
   Assert_Slack_Parity;
   Assert_WhatsApp_Parity;
   Assert_Email_Parity;
   Assert_Long_Tail_Default_Gates;
end Channel_Adapter_Policy;
