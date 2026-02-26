with Channels.Security;

procedure Channel_Security_Policy is
   use Channels.Security;

   Result : Channel_Request_Result;
begin
   pragma Assert
     (Allowlist_Policy_Decision
        (Channel           => CLI_Channel,
         Allowlist_Size    => 0,
         Candidate_Matches => True) = Allowlist_Deny_Empty_Allowlist);
   pragma Assert
     (Allowlist_Policy_Decision
        (Channel           => Webhook_Channel,
         Allowlist_Size    => 2,
         Candidate_Matches => True) = Allowlist_Allow);
   pragma Assert
     (Allowlist_Policy_Decision
        (Channel           => Chat_Channel,
         Allowlist_Size    => 2,
         Candidate_Matches => False) = Allowlist_Deny_Not_Allowlisted);
   pragma Assert
     (not Allowlist_Allows
        (Channel           => CLI_Channel,
         Allowlist_Size    => 0,
         Candidate_Matches => True));

   pragma Assert
     (Rate_Limit_Policy_Decision
        (Limiter_Configured => False,
         Requests_In_Window => 1,
         Max_Requests       => 10) = Rate_Limit_Deny_Not_Configured);
   pragma Assert
     (Rate_Limit_Policy_Decision
        (Limiter_Configured => True,
         Requests_In_Window => 11,
         Max_Requests       => 10) = Rate_Limit_Deny_Window_Exceeded);
   pragma Assert
     (Rate_Limit_Allows
        (Limiter_Configured => True,
         Requests_In_Window => 10,
         Max_Requests       => 10));

   pragma Assert
     (Replay_Policy_Decision
        (Idempotency_Key_Present => False,
         Seen_Before             => False) =
           Replay_Deny_Missing_Idempotency_Key);
   pragma Assert
     (Replay_Policy_Decision
        (Idempotency_Key_Present => True,
         Seen_Before             => True) = Replay_Deny_Seen_Before);
   pragma Assert
     (Replay_Protected
        (Idempotency_Key_Present => True,
         Seen_Before             => False));

   Result :=
     Evaluate_Channel_Request
       (Channel                 => CLI_Channel,
        Allowlist_Size          => 1,
        Candidate_Matches       => True,
        Limiter_Configured      => True,
        Requests_In_Window      => 4,
        Max_Requests            => 10,
        Idempotency_Key_Present => True,
        Seen_Before             => False);
   pragma Assert (Result.Allowed and then Result.Decision = Channel_Request_Allow);

   Result :=
     Evaluate_Channel_Request
       (Channel                 => Webhook_Channel,
        Allowlist_Size          => 0,
        Candidate_Matches       => True,
        Limiter_Configured      => True,
        Requests_In_Window      => 1,
        Max_Requests            => 10,
        Idempotency_Key_Present => True,
        Seen_Before             => False);
   pragma Assert
     ((not Result.Allowed)
      and then Result.Decision = Channel_Request_Deny_Allowlist);

   Result :=
      Evaluate_Channel_Request
        (Channel                 => Chat_Channel,
         Allowlist_Size          => 1,
        Candidate_Matches       => True,
        Limiter_Configured      => False,
        Requests_In_Window      => 1,
        Max_Requests            => 10,
        Idempotency_Key_Present => True,
        Seen_Before             => False);
   pragma Assert
     ((not Result.Allowed)
      and then Result.Decision = Channel_Request_Deny_Rate_Limit);

   Result :=
     Evaluate_Channel_Request
       (Channel                 => Chat_Channel,
        Allowlist_Size          => 1,
        Candidate_Matches       => True,
        Limiter_Configured      => True,
        Requests_In_Window      => 1,
        Max_Requests            => 10,
        Idempotency_Key_Present => True,
         Seen_Before             => True);
   pragma Assert
      ((not Result.Allowed) and then Result.Decision = Channel_Request_Deny_Replay);

   for Core_Channel in Telegram_Channel .. Email_Channel loop
      Result :=
        Evaluate_Channel_Request
          (Channel                 => Core_Channel,
           Allowlist_Size          => 0,
           Candidate_Matches       => True,
           Limiter_Configured      => True,
           Requests_In_Window      => 1,
           Max_Requests            => 10,
           Idempotency_Key_Present => True,
           Seen_Before             => False);
      pragma Assert
        ((not Result.Allowed)
         and then Result.Decision = Channel_Request_Deny_Allowlist);

      Result :=
        Evaluate_Channel_Request
          (Channel                 => Core_Channel,
           Allowlist_Size          => 1,
           Candidate_Matches       => True,
           Limiter_Configured      => False,
           Requests_In_Window      => 1,
           Max_Requests            => 10,
           Idempotency_Key_Present => True,
           Seen_Before             => False);
      pragma Assert
        ((not Result.Allowed)
         and then Result.Decision = Channel_Request_Deny_Rate_Limit);

      Result :=
        Evaluate_Channel_Request
          (Channel                 => Core_Channel,
           Allowlist_Size          => 1,
           Candidate_Matches       => True,
           Limiter_Configured      => True,
           Requests_In_Window      => 1,
           Max_Requests            => 10,
           Idempotency_Key_Present => False,
           Seen_Before             => False);
      pragma Assert
        ((not Result.Allowed) and then Result.Decision = Channel_Request_Deny_Replay);

      Result :=
        Evaluate_Channel_Request
          (Channel                 => Core_Channel,
           Allowlist_Size          => 1,
           Candidate_Matches       => True,
           Limiter_Configured      => True,
           Requests_In_Window      => 1,
           Max_Requests            => 10,
           Idempotency_Key_Present => True,
           Seen_Before             => False);
      pragma Assert
        (Result.Allowed and then Result.Decision = Channel_Request_Allow);
   end loop;
end Channel_Security_Policy;
