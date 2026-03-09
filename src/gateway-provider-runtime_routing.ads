with Config.Schema;
with Gateway.Provider.Routing;

package Gateway.Provider.Runtime_Routing
  with SPARK_Mode => Off
is
   subtype Provider_Position is Natural range 0 .. Config.Schema.Max_Providers;

   type Attempt_State is record
      Primary_Failed     : Boolean := False;
      Failover_Failed    : Boolean := False;
      Long_Tail_Failures : Natural := 0;
   end record;

   type Provider_Attempt is record
      Allowed      : Boolean := False;
      Config_Index : Provider_Position := 0;
      Route        : Gateway.Provider.Routing.Route_Result;
   end record;

   function Next_Attempt
     (Cfg   : Config.Schema.Agent_Config;
      State : Attempt_State) return Provider_Attempt;

   procedure Mark_Failed
     (State   : in out Attempt_State;
      Attempt : Provider_Attempt)
   with
      Pre => Attempt.Allowed;
end Gateway.Provider.Runtime_Routing;
