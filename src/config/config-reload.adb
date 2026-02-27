with Ada.Interrupts;
with Ada.Interrupts.Names;

package body Config.Reload is

   --  Protected object at library level; pragma Attach_Handler installs the
   --  SIGHUP handler at elaboration time.
   protected Sig_Handler is
      pragma Interrupt_Priority;
      procedure Handle_HUP;
      pragma Attach_Handler (Handle_HUP, Ada.Interrupts.Names.SIGHUP);
      function Pending return Boolean;
      procedure Clear;
   private
      Flag : Boolean := False;
   end Sig_Handler;

   protected body Sig_Handler is
      procedure Handle_HUP is
      begin
         Flag := True;
      end Handle_HUP;

      function Pending return Boolean is
      begin
         return Flag;
      end Pending;

      procedure Clear is
      begin
         Flag := False;
      end Clear;
   end Sig_Handler;

   procedure Request is
   begin
      Sig_Handler.Handle_HUP;
   end Request;

   function Is_Requested return Boolean is
   begin
      return Sig_Handler.Pending;
   end Is_Requested;

   procedure Acknowledge is
   begin
      Sig_Handler.Clear;
   end Acknowledge;

end Config.Reload;
