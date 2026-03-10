package body Core.Agent with SPARK_Mode is
   function Config_Is_Safe_Default (Config : Agent_Config) return Boolean is
   begin
      return Security.Secrets.Config_Valid (Config.Secrets)
        and then Runtime.Memory.Backend_Config_Valid (Config.Memory_Backend)
        and then Runtime.Memory.Backend_Request_Allowed
          (Config.Memory_Backend, Config.Memory_Backend.Default_Backend)
        and then Runtime.Memory.Retention_Config_Valid
          (Config.Memory_Retention)
        and then Runtime.Memory.Memory_Runtime_Allowed
          (Backend           => Config.Memory_Backend,
           Requested_Backend => Config.Memory_Backend.Default_Backend,
           Availability      => (others => <>),
           Retention         => Config.Memory_Retention,
           Current_Entries   => 0,
           Oldest_Age_Days   => 0);
   end Config_Is_Safe_Default;
end Core.Agent;
