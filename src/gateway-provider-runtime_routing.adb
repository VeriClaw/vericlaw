with Config.Schema;
with Gateway.Provider.Registry;
with Gateway.Provider.Routing;

package body Gateway.Provider.Runtime_Routing
  with SPARK_Mode => Off
is
   function Next_Long_Tail_Index
     (Cfg   : Config.Schema.Agent_Config;
      State : Attempt_State) return Provider_Position
   is
      Next_Index : constant Natural := 3 + State.Long_Tail_Failures;
   begin
      if Next_Index <= Natural (Cfg.Num_Providers) then
         return Provider_Position (Next_Index);
      end if;

      return 0;
   end Next_Long_Tail_Index;

   function Registry_View
     (Cfg   : Config.Schema.Agent_Config;
      State : Attempt_State) return Gateway.Provider.Registry.Registry_Config
   is
      Long_Tail_Index : constant Provider_Position :=
        Next_Long_Tail_Index (Cfg, State);
   begin
      return
        (Primary_Configured   => Natural (Cfg.Num_Providers) >= 1,
         Primary_Enabled      =>
           Natural (Cfg.Num_Providers) >= 1 and then not State.Primary_Failed,
         Failover_Configured  => Natural (Cfg.Num_Providers) >= 2,
         Failover_Enabled     =>
           Natural (Cfg.Num_Providers) >= 2 and then not State.Failover_Failed,
         Long_Tail_Configured => Long_Tail_Index /= 0,
         Long_Tail_Enabled    => Long_Tail_Index /= 0);
   end Registry_View;

   function Next_Attempt
     (Cfg   : Config.Schema.Agent_Config;
      State : Attempt_State) return Provider_Attempt
   is
      Route : constant Gateway.Provider.Routing.Route_Result :=
        Gateway.Provider.Routing.Primary_With_Failover_Decision
          (Registry_View (Cfg, State));
      Config_Index : Provider_Position := 0;
   begin
      if Route.Allowed then
         case Route.Provider is
            when Gateway.Provider.Registry.Primary_Provider =>
               Config_Index := 1;
            when Gateway.Provider.Registry.Failover_Provider =>
               Config_Index := 2;
            when Gateway.Provider.Registry.Long_Tail_Provider =>
               Config_Index := Next_Long_Tail_Index (Cfg, State);
         end case;
      end if;

      if Route.Allowed and then Config_Index /= 0 then
         return
           (Allowed      => True,
            Config_Index => Config_Index,
            Route        => Route);
      end if;

      return
        (Allowed      => False,
         Config_Index => 0,
         Route        => (Allowed  => False,
                          Provider => Gateway.Provider.Registry.Primary_Provider,
                          Decision => Gateway.Provider.Routing.Route_Deny_No_Provider));
   end Next_Attempt;

   procedure Mark_Failed
     (State   : in out Attempt_State;
      Attempt : Provider_Attempt) is
   begin
      case Attempt.Route.Provider is
         when Gateway.Provider.Registry.Primary_Provider =>
            State.Primary_Failed := True;
         when Gateway.Provider.Registry.Failover_Provider =>
            State.Failover_Failed := True;
         when Gateway.Provider.Registry.Long_Tail_Provider =>
            State.Long_Tail_Failures := State.Long_Tail_Failures + 1;
      end case;
   end Mark_Failed;
end Gateway.Provider.Runtime_Routing;
