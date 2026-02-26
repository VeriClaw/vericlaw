with Runtime.Executor;
with Security.Policy;

procedure Autonomy_Guardrails_Policy is
   use Runtime.Executor;
   use Security.Policy;

   Strict_Limits : constant Limits := (others => <>);
   Insecure_Limits : constant Limits :=
     (Max_Seconds => 301, Max_Memory_MB => 256, Max_Processes => 4);
   Action_Result : Supervised_Action_Result;
begin
   pragma Assert
     (Autonomy_Guardrail_Policy_Decision
        (Budget_Available    => False,
         Budget_Remaining    => 5,
         Actions_Requested   => 1,
         Cooldown_Active     => False,
         Supervisor_Approved => True) = Autonomy_Deny_Budget_Unavailable);
   pragma Assert
     (Autonomy_Guardrail_Policy_Decision
        (Budget_Available    => True,
         Budget_Remaining    => 0,
         Actions_Requested   => 1,
         Cooldown_Active     => False,
         Supervisor_Approved => True) = Autonomy_Deny_Budget_Exhausted);
   pragma Assert
     (Autonomy_Guardrail_Policy_Decision
        (Budget_Available    => True,
         Budget_Remaining    => 3,
         Actions_Requested   => 1,
         Cooldown_Active     => True,
         Supervisor_Approved => True) = Autonomy_Deny_Cooldown_Active);
   pragma Assert
     (Autonomy_Guardrail_Policy_Decision
        (Budget_Available    => True,
         Budget_Remaining    => 3,
         Actions_Requested   => 1,
         Cooldown_Active     => False,
         Supervisor_Approved => False) =
           Autonomy_Deny_Supervisor_Approval_Required);
   pragma Assert
     (Autonomy_Guardrail_Policy_Decision
        (Budget_Available    => True,
         Budget_Remaining    => 0,
         Actions_Requested   => 1,
         Cooldown_Active     => True,
         Supervisor_Approved => False) = Autonomy_Deny_Budget_Exhausted);
   pragma Assert
     (Autonomy_Guardrail_Allows
        (Budget_Available    => True,
         Budget_Remaining    => 3,
         Actions_Requested   => 1,
         Cooldown_Active     => False,
         Supervisor_Approved => True));
   pragma Assert
     (not Autonomy_Guardrail_Allows
        (Budget_Available    => True,
         Budget_Remaining    => 3,
         Actions_Requested   => 1,
         Cooldown_Active     => False,
         Supervisor_Approved => False));

   pragma Assert
     (Supervised_Run_Policy_Decision
        (Config              => Strict_Limits,
         Requested_Seconds   => 30,
         Requested_Memory_MB => 256,
         Requested_Processes => 4,
         Budget_Available    => True,
         Budget_Remaining    => 3,
         Actions_Requested   => 1,
         Cooldown_Active     => False,
         Supervisor_Approved => True) = Supervised_Run_Allow);
   pragma Assert
     (Supervised_Run_Policy_Decision
        (Config              => Insecure_Limits,
         Requested_Seconds   => 1,
         Requested_Memory_MB => 1,
         Requested_Processes => 1,
         Budget_Available    => True,
         Budget_Remaining    => 3,
         Actions_Requested   => 1,
         Cooldown_Active     => False,
         Supervisor_Approved => True) = Supervised_Run_Deny_Runtime_Limits);
   pragma Assert
     (Supervised_Run_Policy_Decision
        (Config              => Strict_Limits,
         Requested_Seconds   => 30,
         Requested_Memory_MB => 256,
         Requested_Processes => 4,
         Budget_Available    => False,
         Budget_Remaining    => 3,
         Actions_Requested   => 1,
         Cooldown_Active     => False,
         Supervisor_Approved => True) =
           Supervised_Run_Deny_Budget_Unavailable);
   pragma Assert
     (Supervised_Run_Policy_Decision
        (Config              => Strict_Limits,
         Requested_Seconds   => 30,
         Requested_Memory_MB => 256,
         Requested_Processes => 4,
         Budget_Available    => True,
         Budget_Remaining    => 0,
         Actions_Requested   => 1,
         Cooldown_Active     => False,
         Supervisor_Approved => True) = Supervised_Run_Deny_Budget_Exhausted);
   pragma Assert
     (Supervised_Run_Policy_Decision
        (Config              => Strict_Limits,
         Requested_Seconds   => 30,
         Requested_Memory_MB => 256,
         Requested_Processes => 4,
         Budget_Available    => True,
         Budget_Remaining    => 3,
         Actions_Requested   => 1,
         Cooldown_Active     => True,
         Supervisor_Approved => True) = Supervised_Run_Deny_Cooldown_Active);
   pragma Assert
     (Supervised_Run_Policy_Decision
        (Config              => Strict_Limits,
         Requested_Seconds   => 30,
         Requested_Memory_MB => 256,
         Requested_Processes => 4,
         Budget_Available    => True,
         Budget_Remaining    => 3,
         Actions_Requested   => 1,
         Cooldown_Active     => False,
         Supervisor_Approved => False) =
           Supervised_Run_Deny_Supervisor_Approval_Required);
    pragma Assert
      (not Can_Run_Supervised
         (Config              => Strict_Limits,
          Requested_Seconds   => 30,
          Requested_Memory_MB => 256,
          Requested_Processes => 4,
          Budget_Available    => True,
          Budget_Remaining    => 3,
          Actions_Requested   => 1,
          Cooldown_Active     => True,
          Supervisor_Approved => True));

   Action_Result :=
     Evaluate_Supervised_Action
       (Config              => Strict_Limits,
        Requested_Seconds   => 30,
        Requested_Memory_MB => 256,
        Requested_Processes => 4,
        Budget_Available    => False,
        Budget_Remaining    => 3,
        Actions_Requested   => 1,
        Cooldown_Active     => False,
        Supervisor_Approved => True);
   pragma Assert
     ((not Action_Result.Allowed)
      and then Action_Result.Decision = Supervised_Run_Deny_Budget_Unavailable);

   Action_Result :=
     Evaluate_Supervised_Action
       (Config              => Strict_Limits,
        Requested_Seconds   => 30,
        Requested_Memory_MB => 256,
        Requested_Processes => 4,
        Budget_Available    => True,
        Budget_Remaining    => 0,
        Actions_Requested   => 1,
        Cooldown_Active     => False,
        Supervisor_Approved => True);
   pragma Assert
     ((not Action_Result.Allowed)
      and then Action_Result.Decision = Supervised_Run_Deny_Budget_Exhausted);

   Action_Result :=
     Evaluate_Supervised_Action
       (Config              => Strict_Limits,
        Requested_Seconds   => 30,
        Requested_Memory_MB => 256,
        Requested_Processes => 4,
        Budget_Available    => True,
        Budget_Remaining    => 3,
        Actions_Requested   => 1,
        Cooldown_Active     => True,
        Supervisor_Approved => True);
   pragma Assert
     ((not Action_Result.Allowed)
      and then Action_Result.Decision = Supervised_Run_Deny_Cooldown_Active);

   Action_Result :=
     Evaluate_Supervised_Action
       (Config              => Strict_Limits,
        Requested_Seconds   => 30,
        Requested_Memory_MB => 256,
        Requested_Processes => 4,
        Budget_Available    => True,
        Budget_Remaining    => 3,
        Actions_Requested   => 1,
        Cooldown_Active     => False,
        Supervisor_Approved => False);
   pragma Assert
     ((not Action_Result.Allowed)
      and then
        Action_Result.Decision =
          Supervised_Run_Deny_Supervisor_Approval_Required);

   Action_Result :=
     Evaluate_Supervised_Action
       (Config              => Strict_Limits,
        Requested_Seconds   => 30,
        Requested_Memory_MB => 256,
        Requested_Processes => 4,
        Budget_Available    => True,
        Budget_Remaining    => 3,
        Actions_Requested   => 1,
        Cooldown_Active     => False,
        Supervisor_Approved => True);
   pragma Assert
     (Action_Result.Allowed
      and then Action_Result.Decision = Supervised_Run_Allow);

   Action_Result :=
     Evaluate_Supervised_Action
       (Config              => Insecure_Limits,
        Requested_Seconds   => 1,
        Requested_Memory_MB => 1,
        Requested_Processes => 1,
        Budget_Available    => True,
        Budget_Remaining    => 3,
        Actions_Requested   => 1,
        Cooldown_Active     => False,
        Supervisor_Approved => True);
   pragma Assert
     ((not Action_Result.Allowed)
      and then Action_Result.Decision = Supervised_Run_Deny_Runtime_Limits);
end Autonomy_Guardrails_Policy;
