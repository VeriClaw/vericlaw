--  Config.Reload: SIGHUP handler flag for hot config reload.
--  Polling loops call Is_Requested / Acknowledge to check and clear the flag.

package Config.Reload is

   --  Set the reload-requested flag (also invoked directly by the signal handler).
   procedure Request;

   --  True when SIGHUP has been received and a config reload is pending.
   function Is_Requested return Boolean;

   --  Clear the flag after the new config has been loaded.
   procedure Acknowledge;

end Config.Reload;
