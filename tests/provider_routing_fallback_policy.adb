with Gateway.Provider.Credentials;
with Gateway.Provider.Registry;
with Gateway.Provider.Routing;
with Gateway.Provider.Runtime_Routing;
with Config.Schema;

procedure Provider_Routing_Fallback_Policy is
   use Config.Schema;
   use Gateway.Provider.Credentials;
   use Gateway.Provider.Registry;
   use Gateway.Provider.Routing;
   use Gateway.Provider.Runtime_Routing;

   Fully_Enabled : constant Registry_Config :=
     (Primary_Configured  => True,
      Primary_Enabled     => True,
      Failover_Configured => True,
      Failover_Enabled    => True,
      Long_Tail_Configured => True,
      Long_Tail_Enabled    => False);

   Primary_Down : constant Registry_Config :=
     (Primary_Configured  => True,
      Primary_Enabled     => False,
      Failover_Configured => True,
      Failover_Enabled    => True,
      Long_Tail_Configured => True,
      Long_Tail_Enabled    => False);

   None_Available : constant Registry_Config :=
     (Primary_Configured  => False,
      Primary_Enabled     => False,
      Failover_Configured => True,
      Failover_Enabled    => False,
      Long_Tail_Configured => False,
      Long_Tail_Enabled    => False);

   Core_Down_Long_Tail_Only : constant Registry_Config :=
     (Primary_Configured  => True,
      Primary_Enabled     => False,
      Failover_Configured => True,
      Failover_Enabled    => False,
      Long_Tail_Configured => True,
      Long_Tail_Enabled    => True);

   Route : Route_Result;
   Token : Provider_Token;
   Request : Provider_Request_Result;
begin
   pragma Assert
     (Status_Decision (Configured => False, Enabled => True) =
        Provider_Error_Not_Configured);
   pragma Assert
     (Status_Decision (Configured => True, Enabled => False) =
        Provider_Deny_Disabled);

   Route := Primary_Decision (Fully_Enabled);
   pragma Assert (Route.Allowed and then Route.Provider = Primary_Provider);
   pragma Assert (Route.Decision = Route_Allow_Primary);

   Route := Primary_Decision (Primary_Down);
   pragma Assert
     ((not Route.Allowed) and then Route.Decision = Route_Deny_Primary_Unavailable);

   Route := Failover_Decision (Fully_Enabled);
   pragma Assert (Route.Allowed and then Route.Provider = Failover_Provider);
   pragma Assert (Route.Decision = Route_Allow_Failover);

   Route := Failover_Decision (Core_Down_Long_Tail_Only);
   pragma Assert
     ((not Route.Allowed) and then Route.Decision = Route_Deny_Failover_Unavailable);

   Route := Primary_With_Failover_Decision (Primary_Down);
   pragma Assert (Route.Allowed and then Route.Provider = Failover_Provider);
   pragma Assert (Route.Decision = Route_Allow_Failover);

   Route := Primary_With_Failover_Decision (Core_Down_Long_Tail_Only);
   pragma Assert (Route.Allowed and then Route.Provider = Long_Tail_Provider);
   pragma Assert (Route.Decision = Route_Allow_Long_Tail);
   pragma Assert (Route_Uses_Fallback (Route));

   Route := Primary_With_Failover_Decision (None_Available);
   pragma Assert
     ((not Route.Allowed) and then Route.Decision = Route_Deny_No_Provider);

   Route :=
     Weighted_Decision
       (Config             => Fully_Enabled,
        Primary_Weight     => 70,
        Deterministic_Slot => 10);
   pragma Assert (Route.Allowed and then Route.Provider = Primary_Provider);
   pragma Assert (Route.Decision = Route_Allow_Weighted_Primary);

   Route :=
      Weighted_Decision
        (Config             => Fully_Enabled,
         Primary_Weight     => 30,
         Deterministic_Slot => 90);
   pragma Assert (Route.Allowed and then Route.Provider = Failover_Provider);
   pragma Assert (Route.Decision = Route_Allow_Weighted_Failover);
   pragma Assert (not Route_Uses_Fallback (Route));

   Route :=
      Weighted_Decision
        (Config             => Primary_Down,
         Primary_Weight     => 80,
         Deterministic_Slot => 5);
   pragma Assert (Route.Allowed and then Route.Provider = Failover_Provider);
   pragma Assert (Route.Decision = Route_Allow_Failover);
   pragma Assert (Route_Uses_Fallback (Route));
   pragma Assert
     (Weighted_Decision
        (Config             => Primary_Down,
         Primary_Weight     => 80,
         Deterministic_Slot => 5).Decision = Route.Decision);

   Route :=
      Weighted_Decision
        (Config             => Core_Down_Long_Tail_Only,
         Primary_Weight     => 80,
         Deterministic_Slot => 5);
   pragma Assert (Route.Allowed and then Route.Provider = Long_Tail_Provider);
   pragma Assert (Route.Decision = Route_Allow_Long_Tail);
   pragma Assert (Route_Uses_Fallback (Route));

   Route :=
      Weighted_Decision
        (Config             => Core_Down_Long_Tail_Only,
         Primary_Weight     => 30,
         Deterministic_Slot => 90);
   pragma Assert (Route.Allowed and then Route.Provider = Long_Tail_Provider);
   pragma Assert (Route.Decision = Route_Allow_Long_Tail);
   pragma Assert (Route_Uses_Fallback (Route));
   pragma Assert
     (Weighted_Decision
        (Config             => Core_Down_Long_Tail_Only,
         Primary_Weight     => 30,
         Deterministic_Slot => 90).Provider = Route.Provider);
   pragma Assert
     (Weighted_Decision
        (Config             => Core_Down_Long_Tail_Only,
         Primary_Weight     => 30,
         Deterministic_Slot => 90).Decision = Route.Decision);

   Route :=
      Weighted_Decision
        (Config             => Fully_Enabled,
         Primary_Weight     => 101,
         Deterministic_Slot => 0);
   pragma Assert
     ((not Route.Allowed) and then Route.Decision = Route_Error_Invalid_Weight);

   Route :=
      Weighted_Decision
        (Config             => Fully_Enabled,
         Primary_Weight     => 50,
         Deterministic_Slot => 100);
   pragma Assert
     ((not Route.Allowed) and then Route.Decision = Route_Error_Invalid_Weight);

   Token := Bind_Token (Provider => Primary_Provider, Token_Present => True);
   pragma Assert
     (Access_Decision
        (Token              => Token,
         Requested_Provider => Primary_Provider,
         Is_Fallback        => False) = Credential_Allow);
   pragma Assert
     (Access_Decision
        (Token              => Token,
         Requested_Provider => Failover_Provider,
         Is_Fallback        => False) = Credential_Deny_Provider_Mismatch);
   pragma Assert
     (Access_Decision
        (Token              => Token,
         Requested_Provider => Failover_Provider,
         Is_Fallback        => True) =
          Credential_Deny_Cross_Provider_Fallback);
   pragma Assert
     (Access_Decision
        (Token              => Token,
         Requested_Provider => Long_Tail_Provider,
         Is_Fallback        => False) = Credential_Deny_Provider_Mismatch);

   Token := Bind_Token (Provider => Failover_Provider, Token_Present => False);
   pragma Assert
     (Access_Decision
        (Token              => Token,
         Requested_Provider => Failover_Provider,
         Is_Fallback        => False) = Credential_Deny_Missing_Token);
   pragma Assert
     (Access_Decision
        (Token              => Token,
         Requested_Provider => Primary_Provider,
         Is_Fallback        => True) = Credential_Deny_Missing_Token);

   pragma Assert
     (Access_Decision
        (Token              => Bind_Token
           (Provider => Primary_Provider, Token_Present => True),
         Requested_Provider => Long_Tail_Provider,
         Is_Fallback        => True) = Credential_Deny_Cross_Provider_Fallback);

   Route := Primary_With_Failover_Decision (Primary_Down);
   Token := Bind_Token (Provider => Primary_Provider, Token_Present => True);
   pragma Assert
     (Access_Decision
        (Token              => Token,
         Requested_Provider => Route.Provider,
         Is_Fallback        => True) =
          Credential_Deny_Cross_Provider_Fallback);
   pragma Assert
      (not Token_Authorizes
         (Token              => Token,
          Requested_Provider => Route.Provider,
          Is_Fallback        => True));

   Request :=
      Primary_With_Failover_Request_Decision
        (Config => Fully_Enabled,
         Token  => Bind_Token (Provider => Primary_Provider, Token_Present => True));
   pragma Assert (Request_Authorized (Request));
   pragma Assert (Request.Decision = Provider_Request_Allow_Primary);
   pragma Assert (Request.Credential = Credential_Allow);

   Request :=
      Scoped_Request_Decision
        (Route => Primary_Decision (Primary_Down),
         Token => Bind_Token (Provider => Primary_Provider, Token_Present => True));
   pragma Assert (not Request_Authorized (Request));
   pragma Assert (Request.Route = Route_Deny_Primary_Unavailable);
   pragma Assert (Request.Decision = Provider_Request_Deny_Primary_Unavailable);

   Request :=
      Scoped_Request_Decision
        (Route => Failover_Decision (Core_Down_Long_Tail_Only),
         Token => Bind_Token (Provider => Failover_Provider, Token_Present => True));
   pragma Assert (not Request_Authorized (Request));
   pragma Assert (Request.Route = Route_Deny_Failover_Unavailable);
   pragma Assert (Request.Decision = Provider_Request_Deny_Failover_Unavailable);

   Request :=
     Primary_With_Failover_Request_Decision
       (Config => Primary_Down,
        Token  => Bind_Token (Provider => Primary_Provider, Token_Present => True));
   pragma Assert (not Request_Authorized (Request));
   pragma Assert (Request.Decision = Provider_Request_Deny_Cross_Provider_Fallback);
   pragma Assert (Request.Route = Route_Allow_Failover);

   Request :=
      Primary_With_Failover_Request_Decision
        (Config => Primary_Down,
         Token  => Bind_Token (Provider => Failover_Provider, Token_Present => True));
   pragma Assert (Request_Authorized (Request));
   pragma Assert (Request.Decision = Provider_Request_Allow_Failover);
   pragma Assert (Request.Credential = Credential_Allow);

   Request :=
     Primary_With_Failover_Request_Decision
       (Config => Core_Down_Long_Tail_Only,
        Token  => Bind_Token (Provider => Long_Tail_Provider, Token_Present => True));
   pragma Assert (Request_Authorized (Request));
   pragma Assert (Request.Decision = Provider_Request_Allow_Long_Tail);
   pragma Assert (Request.Credential = Credential_Allow);

   Request :=
      Primary_With_Failover_Request_Decision
        (Config => Core_Down_Long_Tail_Only,
         Token  => Bind_Token (Provider => Failover_Provider, Token_Present => True));
   pragma Assert (not Request_Authorized (Request));
   pragma Assert (Request.Decision = Provider_Request_Deny_Cross_Provider_Fallback);

   Request :=
      Weighted_Request_Decision
        (Config             => Core_Down_Long_Tail_Only,
         Token              => Bind_Token
           (Provider => Failover_Provider, Token_Present => True),
         Primary_Weight     => 30,
         Deterministic_Slot => 90);
   pragma Assert (not Request_Authorized (Request));
   pragma Assert (Request.Route = Route_Allow_Long_Tail);
   pragma Assert (Request.Decision = Provider_Request_Deny_Cross_Provider_Fallback);

   Request :=
     Weighted_Request_Decision
       (Config             => Fully_Enabled,
        Token              => Bind_Token
          (Provider => Primary_Provider, Token_Present => True),
        Primary_Weight     => 30,
        Deterministic_Slot => 90);
   pragma Assert (not Request_Authorized (Request));
   pragma Assert (Request.Decision = Provider_Request_Deny_Provider_Mismatch);

   Request :=
     Primary_With_Failover_Request_Decision
       (Config => Primary_Down,
        Token  => Bind_Token (Provider => Failover_Provider, Token_Present => False));
   pragma Assert (not Request_Authorized (Request));
   pragma Assert (Request.Decision = Provider_Request_Deny_Missing_Token);

   Request :=
     Primary_With_Failover_Request_Decision
       (Config => None_Available,
        Token  => Bind_Token (Provider => Primary_Provider, Token_Present => True));
   pragma Assert (not Request_Authorized (Request));
   pragma Assert (Request.Decision = Provider_Request_Deny_No_Provider);

    Request :=
      Weighted_Request_Decision
        (Config             => Fully_Enabled,
         Token              => Bind_Token
           (Provider => Primary_Provider, Token_Present => True),
         Primary_Weight     => 101,
         Deterministic_Slot => 0);
    pragma Assert (not Request_Authorized (Request));
    pragma Assert (Request.Decision = Provider_Request_Deny_Invalid_Weight);

    declare
       One_Provider  : Agent_Config := Default_Config;
       Two_Providers : Agent_Config := Default_Config;
       Four_Providers : Agent_Config := Default_Config;
       State         : Attempt_State;
       Attempt       : Provider_Attempt;
    begin
       One_Provider.Num_Providers := 1;

       Attempt := Next_Attempt (One_Provider, State);
       pragma Assert (Attempt.Allowed);
       pragma Assert (Attempt.Config_Index = 1);
       pragma Assert (Attempt.Route.Decision = Route_Allow_Primary);

       Mark_Failed (State, Attempt);
       Attempt := Next_Attempt (One_Provider, State);
       pragma Assert (not Attempt.Allowed);
       pragma Assert (Attempt.Route.Decision = Route_Deny_No_Provider);

       Two_Providers.Num_Providers := 2;
       State := (others => <>);

       Attempt := Next_Attempt (Two_Providers, State);
       pragma Assert (Attempt.Allowed);
       pragma Assert (Attempt.Config_Index = 1);
       Mark_Failed (State, Attempt);

       Attempt := Next_Attempt (Two_Providers, State);
       pragma Assert (Attempt.Allowed);
       pragma Assert (Attempt.Config_Index = 2);
       pragma Assert (Attempt.Route.Decision = Route_Allow_Failover);
       pragma Assert (Route_Uses_Fallback (Attempt.Route));

       Mark_Failed (State, Attempt);
       Attempt := Next_Attempt (Two_Providers, State);
       pragma Assert (not Attempt.Allowed);
       pragma Assert (Attempt.Route.Decision = Route_Deny_No_Provider);

       Four_Providers.Num_Providers := 4;
       State := (others => <>);

       Attempt := Next_Attempt (Four_Providers, State);
       pragma Assert (Attempt.Allowed);
       pragma Assert (Attempt.Config_Index = 1);
       Mark_Failed (State, Attempt);

       Attempt := Next_Attempt (Four_Providers, State);
       pragma Assert (Attempt.Allowed);
       pragma Assert (Attempt.Config_Index = 2);
       Mark_Failed (State, Attempt);

       Attempt := Next_Attempt (Four_Providers, State);
       pragma Assert (Attempt.Allowed);
       pragma Assert (Attempt.Config_Index = 3);
       pragma Assert (Attempt.Route.Decision = Route_Allow_Long_Tail);
       pragma Assert (Route_Uses_Fallback (Attempt.Route));
       Mark_Failed (State, Attempt);

       Attempt := Next_Attempt (Four_Providers, State);
       pragma Assert (Attempt.Allowed);
       pragma Assert (Attempt.Config_Index = 4);
       pragma Assert (Attempt.Route.Decision = Route_Allow_Long_Tail);
       pragma Assert (Route_Uses_Fallback (Attempt.Route));
       Mark_Failed (State, Attempt);

       Attempt := Next_Attempt (Four_Providers, State);
       pragma Assert (not Attempt.Allowed);
       pragma Assert (Attempt.Route.Decision = Route_Deny_No_Provider);
    end;
end Provider_Routing_Fallback_Policy;
