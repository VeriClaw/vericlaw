package Gateway.Provider.Registry with SPARK_Mode is
   type Provider_Id is
     (Primary_Provider,
      Failover_Provider,
      Long_Tail_Provider);

   type Provider_Status is
     (Provider_Allow,
      Provider_Deny_Disabled,
      Provider_Error_Not_Configured);

   type Registry_Config is record
      Primary_Configured  : Boolean := True;
      Primary_Enabled     : Boolean := True;
      Failover_Configured : Boolean := True;
      Failover_Enabled    : Boolean := False;
      Long_Tail_Configured : Boolean := True;
      Long_Tail_Enabled    : Boolean := False;
   end record;

   function Status_Decision
     (Configured : Boolean;
      Enabled    : Boolean) return Provider_Status
   with
     Post =>
       (if not Configured then
           Status_Decision'Result = Provider_Error_Not_Configured
        elsif not Enabled then
           Status_Decision'Result = Provider_Deny_Disabled
        else
           Status_Decision'Result = Provider_Allow);

   function Provider_Decision
     (Config   : Registry_Config;
       Provider : Provider_Id) return Provider_Status
   with
      Post =>
        (case Provider is
            when Primary_Provider =>
              Provider_Decision'Result =
                Status_Decision
                  (Configured => Config.Primary_Configured,
                   Enabled    => Config.Primary_Enabled),
            when Failover_Provider =>
              Provider_Decision'Result =
                Status_Decision
                  (Configured => Config.Failover_Configured,
                   Enabled    => Config.Failover_Enabled),
            when Long_Tail_Provider =>
              Provider_Decision'Result =
                Status_Decision
                  (Configured => Config.Long_Tail_Configured,
                   Enabled    => Config.Long_Tail_Enabled));

   function Provider_Enabled
     (Config   : Registry_Config;
      Provider : Provider_Id) return Boolean
   with
     Post =>
       Provider_Enabled'Result =
         (Provider_Decision (Config => Config, Provider => Provider) =
            Provider_Allow);
end Gateway.Provider.Registry;
