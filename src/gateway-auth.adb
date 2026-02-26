package body Gateway.Auth with SPARK_Mode is
   function Config_Is_Secure (Config : Auth_Config) return Boolean is
   begin
      return (not Config.Allow_Public_Bind) or else Config.Require_Pairing;
   end Config_Is_Secure;

   function Pairing_Status_Is_Locked
     (Config : Auth_Config; Status : Pairing_Status) return Boolean is
   begin
      return Status.State = Locked_Out
        or else
          (Status.Failed_Attempts >= Config.Max_Pairing_Attempts
           and then Status.Lockout_Intervals_Remaining > 0);
   end Pairing_Status_Is_Locked;

   function Reset_Pairing_Status
     (Status : Pairing_Status) return Pairing_Status is
      pragma Unreferenced (Status);
   begin
      return
        (State => Unpaired,
         Failed_Attempts => 0,
         Lockout_Intervals_Remaining => 0);
   end Reset_Pairing_Status;

   function Increment_Attempts (Count : Natural) return Natural is
   begin
      if Count = Natural'Last then
         return Natural'Last;
      else
         return Count + 1;
      end if;
   end Increment_Attempts;

   function Advance_Pairing_Status
     (Config                   : Auth_Config;
      Status                   : Pairing_Status;
      Pairing_Attempt_Failed   : Boolean := False;
      Pairing_Succeeded        : Boolean := False;
      Lockout_Interval_Elapsed : Boolean := False;
      Reset                    : Boolean := False) return Pairing_Status is
      Next_Status : Pairing_Status := Status;
      Next_Attempts : Natural;
      Next_Lockout : Natural := Status.Lockout_Intervals_Remaining;
   begin
      if Reset then
         return Reset_Pairing_Status (Status);
      elsif Pairing_Succeeded then
         return
           (State => Paired,
            Failed_Attempts => 0,
            Lockout_Intervals_Remaining => 0);
      elsif Pairing_Attempt_Failed then
         Next_Attempts := Increment_Attempts (Status.Failed_Attempts);
         if Next_Attempts >= Config.Max_Pairing_Attempts then
            return
              (State => Locked_Out,
               Failed_Attempts => Next_Attempts,
               Lockout_Intervals_Remaining => Config.Lockout_Interval);
         else
            return
              (State => Pairing,
               Failed_Attempts => Next_Attempts,
               Lockout_Intervals_Remaining => 0);
         end if;
      elsif Pairing_Status_Is_Locked (Config, Status) then
         if Lockout_Interval_Elapsed and then Next_Lockout > 0 then
            Next_Lockout := Next_Lockout - 1;
         end if;

         if Next_Lockout = 0 then
            return Reset_Pairing_Status (Status);
         else
            Next_Status.State := Locked_Out;
            Next_Status.Lockout_Intervals_Remaining := Next_Lockout;
            if Next_Status.Failed_Attempts < Config.Max_Pairing_Attempts then
               Next_Status.Failed_Attempts := Config.Max_Pairing_Attempts;
            end if;
            return Next_Status;
         end if;
      else
         return Next_Status;
      end if;
   end Advance_Pairing_Status;

   function Request_Decision
     (Config        : Auth_Config;
      Status        : Pairing_Status;
      Token_Present : Boolean;
      Token_Valid   : Boolean) return Auth_Decision is
   begin
      if not Config_Is_Secure (Config) then
         return Deny_Insecure_Config;
      elsif Pairing_Status_Is_Locked (Config, Status) then
         return Deny_Pairing_Lockout;
      elsif Config.Require_Pairing and then Status.State /= Paired then
         return Deny_Not_Paired;
      elsif not Token_Present then
         return Deny_Missing_Token;
      elsif not Token_Valid then
         return Deny_Invalid_Token;
      else
         return Allow;
      end if;
   end Request_Decision;

   function Request_Decision
     (Config        : Auth_Config;
      State         : Pairing_State;
      Token_Present : Boolean;
      Token_Valid   : Boolean) return Auth_Decision is
   begin
      return Request_Decision
        (Config => Config,
         Status =>
           (State => State,
            Failed_Attempts => 0,
            Lockout_Intervals_Remaining => 0),
         Token_Present => Token_Present,
         Token_Valid => Token_Valid);
   end Request_Decision;

   function Request_Authorized
     (Config        : Auth_Config;
      Status        : Pairing_Status;
      Token_Present : Boolean;
      Token_Valid   : Boolean) return Boolean is
   begin
      return Request_Decision
        (Config => Config,
         Status => Status,
         Token_Present => Token_Present,
         Token_Valid => Token_Valid) = Allow;
   end Request_Authorized;

   function Request_Authorized
     (Config        : Auth_Config;
      State         : Pairing_State;
      Token_Present : Boolean;
      Token_Valid   : Boolean) return Boolean is
   begin
      return Request_Decision
        (Config => Config,
         State => State,
         Token_Present => Token_Present,
         Token_Valid => Token_Valid) = Allow;
   end Request_Authorized;
end Gateway.Auth;
