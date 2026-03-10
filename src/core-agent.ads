with Runtime.Memory;
with Security.Secrets;

package Core.Agent with SPARK_Mode is
   type Agent_Config is record
      Secrets : Security.Secrets.Secret_Config :=
         (Source => Security.Secrets.OS_Key_Store,
          Env_Key_Set => False,
          Encrypted_At_Rest => True,
          Active_Key_Version => 1,
          Require_Sealed_Key => True);
      Memory_Backend : Runtime.Memory.Backend_Config := (others => <>);
      Memory_Retention : Runtime.Memory.Retention_Config := (others => <>);
   end record;

   function Config_Is_Safe_Default (Config : Agent_Config) return Boolean
   with
     Post =>
       Config_Is_Safe_Default'Result =
         (Security.Secrets.Config_Valid (Config.Secrets)
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
               Oldest_Age_Days   => 0));
end Core.Agent;
