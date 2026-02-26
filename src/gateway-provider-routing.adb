with Gateway.Provider.Credentials;
with Gateway.Provider.Registry;

package body Gateway.Provider.Routing with SPARK_Mode is
   use type Gateway.Provider.Credentials.Credential_Decision;

   function Route_Deny_Request_Decision
     (Decision : Route_Decision) return Provider_Request_Decision is
   begin
      case Decision is
         when Route_Deny_Primary_Unavailable =>
            return Provider_Request_Deny_Primary_Unavailable;
         when Route_Deny_Failover_Unavailable =>
            return Provider_Request_Deny_Failover_Unavailable;
         when Route_Error_Invalid_Weight =>
            return Provider_Request_Deny_Invalid_Weight;
          when Route_Deny_No_Provider
             | Route_Allow_Primary
             | Route_Allow_Failover
             | Route_Allow_Long_Tail
             | Route_Allow_Weighted_Primary
             | Route_Allow_Weighted_Failover =>
             return Provider_Request_Deny_No_Provider;
      end case;
   end Route_Deny_Request_Decision;

   function Credential_Deny_Request_Decision
     (Decision : Gateway.Provider.Credentials.Credential_Decision)
      return Provider_Request_Decision is
   begin
      case Decision is
         when Gateway.Provider.Credentials.Credential_Deny_Missing_Token =>
            return Provider_Request_Deny_Missing_Token;
         when Gateway.Provider.Credentials.Credential_Deny_Provider_Mismatch =>
            return Provider_Request_Deny_Provider_Mismatch;
         when Gateway.Provider.Credentials.Credential_Deny_Cross_Provider_Fallback =>
            return Provider_Request_Deny_Cross_Provider_Fallback;
         when Gateway.Provider.Credentials.Credential_Allow =>
            return Provider_Request_Deny_No_Provider;
      end case;
   end Credential_Deny_Request_Decision;

   function Primary_Decision
     (Config : Gateway.Provider.Registry.Registry_Config) return Route_Result is
   begin
      if Gateway.Provider.Registry.Provider_Enabled
          (Config   => Config,
           Provider => Gateway.Provider.Registry.Primary_Provider) then
         return (Allowed  => True,
                 Provider => Gateway.Provider.Registry.Primary_Provider,
                 Decision => Route_Allow_Primary);
      end if;

      return (Allowed  => False,
              Provider => Gateway.Provider.Registry.Primary_Provider,
              Decision => Route_Deny_Primary_Unavailable);
   end Primary_Decision;

   function Failover_Decision
     (Config : Gateway.Provider.Registry.Registry_Config) return Route_Result is
   begin
      if Gateway.Provider.Registry.Provider_Enabled
          (Config   => Config,
           Provider => Gateway.Provider.Registry.Failover_Provider) then
         return (Allowed  => True,
                 Provider => Gateway.Provider.Registry.Failover_Provider,
                 Decision => Route_Allow_Failover);
      end if;

      return (Allowed  => False,
              Provider => Gateway.Provider.Registry.Failover_Provider,
              Decision => Route_Deny_Failover_Unavailable);
   end Failover_Decision;

   function Primary_With_Failover_Decision
      (Config : Gateway.Provider.Registry.Registry_Config) return Route_Result is
       Primary_Result : constant Route_Result := Primary_Decision (Config);
       Failover_Result : constant Route_Result := Failover_Decision (Config);
    begin
       if Primary_Result.Allowed then
          return Primary_Result;
       elsif Failover_Result.Allowed then
          return Failover_Result;
       elsif Gateway.Provider.Registry.Provider_Enabled
           (Config   => Config,
            Provider => Gateway.Provider.Registry.Long_Tail_Provider) then
          return (Allowed  => True,
                  Provider => Gateway.Provider.Registry.Long_Tail_Provider,
                  Decision => Route_Allow_Long_Tail);
       end if;

       return (Allowed  => False,
               Provider => Gateway.Provider.Registry.Primary_Provider,
               Decision => Route_Deny_No_Provider);
   end Primary_With_Failover_Decision;

   function Weighted_Decision
     (Config             : Gateway.Provider.Registry.Registry_Config;
      Primary_Weight     : Natural;
      Deterministic_Slot : Natural) return Route_Result is
       Primary_Enabled : constant Boolean :=
         Gateway.Provider.Registry.Provider_Enabled
           (Config   => Config,
            Provider => Gateway.Provider.Registry.Primary_Provider);
       Failover_Enabled : constant Boolean :=
         Gateway.Provider.Registry.Provider_Enabled
           (Config   => Config,
            Provider => Gateway.Provider.Registry.Failover_Provider);
       Long_Tail_Enabled : constant Boolean :=
         Gateway.Provider.Registry.Provider_Enabled
           (Config   => Config,
            Provider => Gateway.Provider.Registry.Long_Tail_Provider);
    begin
       if Primary_Weight > 100 or else Deterministic_Slot > 99 then
          return (Allowed  => False,
                  Provider => Gateway.Provider.Registry.Primary_Provider,
                  Decision => Route_Error_Invalid_Weight);
      elsif Deterministic_Slot < Primary_Weight then
          if Primary_Enabled then
             return (Allowed  => True,
                     Provider => Gateway.Provider.Registry.Primary_Provider,
                     Decision => Route_Allow_Weighted_Primary);
          elsif Failover_Enabled then
             return (Allowed  => True,
                     Provider => Gateway.Provider.Registry.Failover_Provider,
                     Decision => Route_Allow_Failover);
          elsif Long_Tail_Enabled then
             return (Allowed  => True,
                     Provider => Gateway.Provider.Registry.Long_Tail_Provider,
                     Decision => Route_Allow_Long_Tail);
          end if;
       else
          if Failover_Enabled then
             return (Allowed  => True,
                     Provider => Gateway.Provider.Registry.Failover_Provider,
                     Decision => Route_Allow_Weighted_Failover);
          elsif Primary_Enabled then
             return (Allowed  => True,
                     Provider => Gateway.Provider.Registry.Primary_Provider,
                     Decision => Route_Allow_Primary);
          elsif Long_Tail_Enabled then
             return (Allowed  => True,
                     Provider => Gateway.Provider.Registry.Long_Tail_Provider,
                     Decision => Route_Allow_Long_Tail);
          end if;
       end if;

      return (Allowed  => False,
              Provider => Gateway.Provider.Registry.Primary_Provider,
              Decision => Route_Deny_No_Provider);
   end Weighted_Decision;

   function Route_Uses_Fallback (Route : Route_Result) return Boolean is
   begin
      return Route.Decision in Route_Allow_Failover | Route_Allow_Long_Tail;
   end Route_Uses_Fallback;

   function Scoped_Request_Decision
     (Route : Route_Result;
      Token : Gateway.Provider.Credentials.Provider_Token)
      return Provider_Request_Result is
      Credential : Gateway.Provider.Credentials.Credential_Decision;
   begin
      if not Route.Allowed then
         return
           (Allowed    => False,
            Provider   => Route.Provider,
            Route      => Route.Decision,
            Credential => Gateway.Provider.Credentials.Credential_Deny_Missing_Token,
            Decision   => Route_Deny_Request_Decision (Route.Decision));
      end if;

      Credential :=
        Gateway.Provider.Credentials.Access_Decision
          (Token              => Token,
           Requested_Provider => Route.Provider,
           Is_Fallback        => Route_Uses_Fallback (Route));

      if Credential /= Gateway.Provider.Credentials.Credential_Allow then
         return
           (Allowed    => False,
            Provider   => Route.Provider,
            Route      => Route.Decision,
            Credential => Credential,
            Decision   => Credential_Deny_Request_Decision (Credential));
      end if;

      case Route.Decision is
         when Route_Allow_Primary | Route_Allow_Weighted_Primary =>
            return
              (Allowed    => True,
               Provider   => Route.Provider,
               Route      => Route.Decision,
               Credential => Credential,
               Decision   => Provider_Request_Allow_Primary);
         when Route_Allow_Failover | Route_Allow_Weighted_Failover =>
            return
              (Allowed    => True,
               Provider   => Route.Provider,
               Route      => Route.Decision,
               Credential => Credential,
               Decision   => Provider_Request_Allow_Failover);
         when Route_Allow_Long_Tail =>
            return
              (Allowed    => True,
               Provider   => Route.Provider,
               Route      => Route.Decision,
               Credential => Credential,
               Decision   => Provider_Request_Allow_Long_Tail);
         when Route_Deny_Primary_Unavailable
             | Route_Deny_Failover_Unavailable
             | Route_Deny_No_Provider
            | Route_Error_Invalid_Weight =>
            return
              (Allowed    => False,
               Provider   => Route.Provider,
               Route      => Route.Decision,
               Credential => Credential,
               Decision   => Route_Deny_Request_Decision (Route.Decision));
      end case;
   end Scoped_Request_Decision;

   function Primary_With_Failover_Request_Decision
     (Config : Gateway.Provider.Registry.Registry_Config;
      Token  : Gateway.Provider.Credentials.Provider_Token)
      return Provider_Request_Result is
   begin
      return
        Scoped_Request_Decision
          (Route => Primary_With_Failover_Decision (Config => Config),
           Token => Token);
   end Primary_With_Failover_Request_Decision;

   function Weighted_Request_Decision
     (Config             : Gateway.Provider.Registry.Registry_Config;
      Token              : Gateway.Provider.Credentials.Provider_Token;
      Primary_Weight     : Natural;
      Deterministic_Slot : Natural) return Provider_Request_Result is
   begin
      return
        Scoped_Request_Decision
          (Route =>
             Weighted_Decision
               (Config             => Config,
                Primary_Weight     => Primary_Weight,
                Deterministic_Slot => Deterministic_Slot),
           Token => Token);
   end Weighted_Request_Decision;

   function Request_Authorized (Decision : Provider_Request_Result) return Boolean is
   begin
      return Decision.Allowed;
   end Request_Authorized;
end Gateway.Provider.Routing;
