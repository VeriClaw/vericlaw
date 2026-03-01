--  Windows stub: SIGHUP does not exist on Windows so hot-reload is request-only.
--  The flag can still be set programmatically via Request; no signal handler.
package body Config.Reload
  with SPARK_Mode => Off
is

   Flag : Boolean := False;

   procedure Request is
   begin
      Flag := True;
   end Request;

   function Is_Requested return Boolean is
   begin
      return Flag;
   end Is_Requested;

   procedure Acknowledge is
   begin
      Flag := False;
   end Acknowledge;

end Config.Reload;
