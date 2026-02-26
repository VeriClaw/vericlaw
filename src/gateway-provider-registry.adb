package body Gateway.Provider.Registry with SPARK_Mode is
   function Status_Decision
     (Configured : Boolean;
      Enabled    : Boolean) return Provider_Status is
   begin
      if not Configured then
         return Provider_Error_Not_Configured;
      elsif not Enabled then
         return Provider_Deny_Disabled;
      else
         return Provider_Allow;
      end if;
   end Status_Decision;

   function Provider_Decision
     (Config   : Registry_Config;
      Provider : Provider_Id) return Provider_Status is
   begin
      case Provider is
         when Primary_Provider =>
            return Status_Decision
              (Configured => Config.Primary_Configured,
               Enabled    => Config.Primary_Enabled);
         when Failover_Provider =>
            return Status_Decision
              (Configured => Config.Failover_Configured,
               Enabled    => Config.Failover_Enabled);
         when Long_Tail_Provider =>
            return Status_Decision
              (Configured => Config.Long_Tail_Configured,
               Enabled    => Config.Long_Tail_Enabled);
      end case;
   end Provider_Decision;

   function Provider_Enabled
     (Config   : Registry_Config;
      Provider : Provider_Id) return Boolean is
   begin
      return Provider_Decision (Config => Config, Provider => Provider) =
        Provider_Allow;
   end Provider_Enabled;
end Gateway.Provider.Registry;
