with Gateway.Provider.Credentials;
with Gateway.Provider.Registry;

package Gateway.Provider.Routing with SPARK_Mode is
   type Route_Decision is
     (Route_Allow_Primary,
      Route_Allow_Failover,
      Route_Allow_Long_Tail,
      Route_Allow_Weighted_Primary,
      Route_Allow_Weighted_Failover,
      Route_Deny_Primary_Unavailable,
      Route_Deny_Failover_Unavailable,
      Route_Deny_No_Provider,
      Route_Error_Invalid_Weight);

   type Route_Result is record
      Allowed  : Boolean := False;
      Provider : Gateway.Provider.Registry.Provider_Id :=
        Gateway.Provider.Registry.Primary_Provider;
      Decision : Route_Decision := Route_Deny_No_Provider;
   end record;

   type Provider_Request_Decision is
     (Provider_Request_Allow_Primary,
      Provider_Request_Allow_Failover,
      Provider_Request_Allow_Long_Tail,
      Provider_Request_Deny_Primary_Unavailable,
      Provider_Request_Deny_Failover_Unavailable,
      Provider_Request_Deny_No_Provider,
      Provider_Request_Deny_Invalid_Weight,
      Provider_Request_Deny_Missing_Token,
      Provider_Request_Deny_Provider_Mismatch,
      Provider_Request_Deny_Cross_Provider_Fallback);

   type Provider_Request_Result is record
      Allowed    : Boolean := False;
      Provider   : Gateway.Provider.Registry.Provider_Id :=
        Gateway.Provider.Registry.Primary_Provider;
      Route      : Route_Decision := Route_Deny_No_Provider;
      Credential : Gateway.Provider.Credentials.Credential_Decision :=
        Gateway.Provider.Credentials.Credential_Deny_Missing_Token;
      Decision   : Provider_Request_Decision := Provider_Request_Deny_No_Provider;
   end record;

   function Primary_Decision
     (Config : Gateway.Provider.Registry.Registry_Config) return Route_Result
   with
     Post =>
       (if Primary_Decision'Result.Allowed then
           Primary_Decision'Result.Decision = Route_Allow_Primary
        else
           Primary_Decision'Result.Decision =
             Route_Deny_Primary_Unavailable);

   function Failover_Decision
     (Config : Gateway.Provider.Registry.Registry_Config) return Route_Result
   with
     Post =>
       (if Failover_Decision'Result.Allowed then
           Failover_Decision'Result.Decision = Route_Allow_Failover
        else
           Failover_Decision'Result.Decision =
             Route_Deny_Failover_Unavailable);

   function Primary_With_Failover_Decision
     (Config : Gateway.Provider.Registry.Registry_Config) return Route_Result
   with
     Post =>
       (if Primary_With_Failover_Decision'Result.Allowed then
           Primary_With_Failover_Decision'Result.Decision in
             Route_Allow_Primary
             | Route_Allow_Failover
             | Route_Allow_Long_Tail
         else
            Primary_With_Failover_Decision'Result.Decision =
              Route_Deny_No_Provider);

   function Weighted_Decision
     (Config             : Gateway.Provider.Registry.Registry_Config;
      Primary_Weight     : Natural;
      Deterministic_Slot : Natural) return Route_Result
   with
     Post =>
       (if Primary_Weight > 100 or else Deterministic_Slot > 99 then
           Weighted_Decision'Result.Decision = Route_Error_Invalid_Weight
           and then not Weighted_Decision'Result.Allowed
        elsif Weighted_Decision'Result.Allowed then
           Weighted_Decision'Result.Decision in
              Route_Allow_Weighted_Primary
              | Route_Allow_Weighted_Failover
              | Route_Allow_Primary
              | Route_Allow_Failover
              | Route_Allow_Long_Tail
          else
             Weighted_Decision'Result.Decision = Route_Deny_No_Provider);

   function Route_Uses_Fallback (Route : Route_Result) return Boolean
   with
      Post =>
        Route_Uses_Fallback'Result =
          (Route.Decision in Route_Allow_Failover | Route_Allow_Long_Tail);

   function Scoped_Request_Decision
     (Route : Route_Result;
      Token : Gateway.Provider.Credentials.Provider_Token)
      return Provider_Request_Result
   with
     Post =>
       (if Scoped_Request_Decision'Result.Allowed then
           Scoped_Request_Decision'Result.Decision in
             Provider_Request_Allow_Primary
             | Provider_Request_Allow_Failover
             | Provider_Request_Allow_Long_Tail
         else
            Scoped_Request_Decision'Result.Decision not in
             Provider_Request_Allow_Primary
             | Provider_Request_Allow_Failover
             | Provider_Request_Allow_Long_Tail);

   function Primary_With_Failover_Request_Decision
     (Config : Gateway.Provider.Registry.Registry_Config;
      Token  : Gateway.Provider.Credentials.Provider_Token)
      return Provider_Request_Result;

   function Weighted_Request_Decision
     (Config             : Gateway.Provider.Registry.Registry_Config;
      Token              : Gateway.Provider.Credentials.Provider_Token;
      Primary_Weight     : Natural;
      Deterministic_Slot : Natural) return Provider_Request_Result;

   function Request_Authorized (Decision : Provider_Request_Result) return Boolean
   with
     Post => Request_Authorized'Result = Decision.Allowed;
end Gateway.Provider.Routing;
