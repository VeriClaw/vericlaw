package Gateway.Auth with SPARK_Mode is
   type Pairing_State is (Unpaired, Pairing, Paired, Locked_Out);

   type Pairing_Status is record
      State : Pairing_State := Unpaired;
      Failed_Attempts : Natural := 0;
      Lockout_Intervals_Remaining : Natural := 0;
   end record;

   type Auth_Decision is
     (Allow,
      Deny_Insecure_Config,
      Deny_Pairing_Lockout,
      Deny_Not_Paired,
      Deny_Missing_Token,
      Deny_Invalid_Token);

   type Auth_Config is record
      Require_Pairing : Boolean := True;
      Allow_Public_Bind : Boolean := False;
      Max_Pairing_Attempts : Positive := 3;
      Lockout_Interval : Positive := 3;
   end record;

   function Config_Is_Secure (Config : Auth_Config) return Boolean
   with
     Post =>
       Config_Is_Secure'Result =
         ((not Config.Allow_Public_Bind) or else Config.Require_Pairing);

   function Pairing_Status_Is_Locked
     (Config : Auth_Config; Status : Pairing_Status) return Boolean
   with
     Post =>
       Pairing_Status_Is_Locked'Result =
         (Status.State = Locked_Out
          or else
            (Status.Failed_Attempts >= Config.Max_Pairing_Attempts
             and then Status.Lockout_Intervals_Remaining > 0));

   function Reset_Pairing_Status
     (Status : Pairing_Status) return Pairing_Status
   with
     Post =>
       Reset_Pairing_Status'Result =
         (State => Unpaired,
          Failed_Attempts => 0,
          Lockout_Intervals_Remaining => 0);

   function Advance_Pairing_Status
     (Config                   : Auth_Config;
      Status                   : Pairing_Status;
      Pairing_Attempt_Failed   : Boolean := False;
      Pairing_Succeeded        : Boolean := False;
      Lockout_Interval_Elapsed : Boolean := False;
      Reset                    : Boolean := False) return Pairing_Status
   with
     Pre => not (Pairing_Attempt_Failed and Pairing_Succeeded);

   function Request_Decision
     (Config        : Auth_Config;
      Status        : Pairing_Status;
      Token_Present : Boolean;
      Token_Valid   : Boolean) return Auth_Decision
   with
     Pre  => (if Token_Valid then Token_Present),
     Post =>
       (if not Config_Is_Secure (Config) then
           Request_Decision'Result = Deny_Insecure_Config
        elsif Pairing_Status_Is_Locked (Config, Status) then
           Request_Decision'Result = Deny_Pairing_Lockout
        elsif Config.Require_Pairing and then Status.State /= Paired then
           Request_Decision'Result = Deny_Not_Paired
        elsif not Token_Present then
           Request_Decision'Result = Deny_Missing_Token
        elsif not Token_Valid then
           Request_Decision'Result = Deny_Invalid_Token
        else
           Request_Decision'Result = Allow);

   function Request_Decision
     (Config        : Auth_Config;
      State         : Pairing_State;
      Token_Present : Boolean;
      Token_Valid   : Boolean) return Auth_Decision
   with
     Pre  => (if Token_Valid then Token_Present),
     Post =>
       (if not Config_Is_Secure (Config) then
           Request_Decision'Result = Deny_Insecure_Config
        elsif State = Locked_Out then
           Request_Decision'Result = Deny_Pairing_Lockout
        elsif Config.Require_Pairing and then State /= Paired then
           Request_Decision'Result = Deny_Not_Paired
        elsif not Token_Present then
           Request_Decision'Result = Deny_Missing_Token
        elsif not Token_Valid then
           Request_Decision'Result = Deny_Invalid_Token
        else
           Request_Decision'Result = Allow);

   function Request_Authorized
     (Config        : Auth_Config;
      Status        : Pairing_Status;
      Token_Present : Boolean;
      Token_Valid   : Boolean) return Boolean
   with
     Pre  => (if Token_Valid then Token_Present),
     Post =>
       Request_Authorized'Result =
         (Request_Decision
            (Config => Config,
             Status => Status,
             Token_Present => Token_Present,
             Token_Valid => Token_Valid) = Allow);

   function Request_Authorized
     (Config        : Auth_Config;
      State         : Pairing_State;
      Token_Present : Boolean;
      Token_Valid   : Boolean) return Boolean
   with
     Pre  => (if Token_Valid then Token_Present),
     Post =>
       Request_Authorized'Result =
         (Request_Decision
            (Config => Config,
             State => State,
             Token_Present => Token_Present,
             Token_Valid => Token_Valid) = Allow);
end Gateway.Auth;
