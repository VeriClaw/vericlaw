with Gateway.Auth;
with Runtime.Executor;
with Runtime.Memory;
with Security.Secrets;

package Core.Agent with SPARK_Mode is
   type Agent_Config is record
      Auth : Gateway.Auth.Auth_Config :=
        (Require_Pairing => True,
         Allow_Public_Bind => False,
         Max_Pairing_Attempts => 3,
         Lockout_Interval => 3);
      Secrets : Security.Secrets.Secret_Config :=
         (Source => Security.Secrets.OS_Key_Store,
          Env_Key_Set => False,
          Encrypted_At_Rest => True,
          Active_Key_Version => 1,
          Require_Sealed_Key => True);
      Limits : Runtime.Executor.Limits :=
        (Max_Seconds => 30, Max_Memory_MB => 256, Max_Processes => 4);
      Memory_Backend : Runtime.Memory.Backend_Config := (others => <>);
      Memory_Retention : Runtime.Memory.Retention_Config := (others => <>);
   end record;

   function Config_Is_Safe_Default (Config : Agent_Config) return Boolean
   with
     Post =>
       Config_Is_Safe_Default'Result =
         (Gateway.Auth.Config_Is_Secure (Config.Auth)
           and then Security.Secrets.Config_Valid (Config.Secrets)
           and then Runtime.Executor.Limits_Are_Strict (Config.Limits)
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
               Oldest_Age_Days   => 0)
            and then Config.Auth.Require_Pairing
            and then not Config.Auth.Allow_Public_Bind);
end Core.Agent;
