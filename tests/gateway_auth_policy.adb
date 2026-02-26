with Gateway.Auth;

procedure Gateway_Auth_Policy is
   use Gateway.Auth;

   Default_Config : constant Auth_Config := (others => <>);
   Insecure_Config : constant Auth_Config :=
     (Require_Pairing => False, Allow_Public_Bind => True, others => <>);
   Local_No_Pairing : constant Auth_Config :=
     (Require_Pairing => False, Allow_Public_Bind => False, others => <>);
   Lockout_Config : constant Auth_Config :=
     (Require_Pairing => True,
      Allow_Public_Bind => False,
      Max_Pairing_Attempts => 2,
      Lockout_Interval => 2);
   Status : Pairing_Status := (others => <>);
begin
   pragma Assert (Config_Is_Secure (Default_Config));
   pragma Assert
     (Request_Decision
        (Config => Default_Config,
         State => Unpaired,
         Token_Present => True,
         Token_Valid => True) = Deny_Not_Paired);
   pragma Assert
     (Request_Decision
        (Config => Default_Config,
         State => Paired,
         Token_Present => False,
         Token_Valid => False) = Deny_Missing_Token);
   pragma Assert
     (Request_Decision
        (Config => Default_Config,
         State => Paired,
         Token_Present => True,
         Token_Valid => False) = Deny_Invalid_Token);
   pragma Assert
     (Request_Authorized
        (Config => Default_Config,
         State => Paired,
         Token_Present => True,
         Token_Valid => True));

   pragma Assert (not Config_Is_Secure (Insecure_Config));
   pragma Assert
     (Request_Decision
        (Config => Insecure_Config,
         State => Paired,
         Token_Present => True,
         Token_Valid => True) = Deny_Insecure_Config);
   pragma Assert
     (not Request_Authorized
        (Config => Insecure_Config,
         State => Paired,
         Token_Present => True,
         Token_Valid => True));

   pragma Assert (Config_Is_Secure (Local_No_Pairing));
   pragma Assert
      (Request_Decision
         (Config => Local_No_Pairing,
          State => Unpaired,
          Token_Present => True,
          Token_Valid => True) = Allow);

   Status := Advance_Pairing_Status
     (Config => Lockout_Config,
      Status => Status,
      Pairing_Attempt_Failed => True);
   pragma Assert (Status.State = Pairing);
   pragma Assert (Status.Failed_Attempts = 1);
   pragma Assert (Status.Lockout_Intervals_Remaining = 0);

   Status := Advance_Pairing_Status
     (Config => Lockout_Config,
      Status => Status,
      Pairing_Attempt_Failed => True);
   pragma Assert (Status.State = Locked_Out);
   pragma Assert (Pairing_Status_Is_Locked (Lockout_Config, Status));
   pragma Assert (Status.Failed_Attempts = 2);
   pragma Assert (Status.Lockout_Intervals_Remaining = 2);
   pragma Assert
     (Request_Decision
        (Config => Lockout_Config,
         Status => Status,
         Token_Present => True,
         Token_Valid => True) = Deny_Pairing_Lockout);
   pragma Assert
     (Request_Decision
        (Config => Lockout_Config,
         State => Locked_Out,
         Token_Present => True,
         Token_Valid => True) = Deny_Pairing_Lockout);

   Status := Advance_Pairing_Status
     (Config => Lockout_Config,
      Status => Status,
      Lockout_Interval_Elapsed => True);
   pragma Assert (Status.State = Locked_Out);
   pragma Assert (Status.Lockout_Intervals_Remaining = 1);

   Status := Advance_Pairing_Status
     (Config => Lockout_Config,
      Status => Status,
      Lockout_Interval_Elapsed => True);
   pragma Assert (Status.State = Unpaired);
   pragma Assert (Status.Failed_Attempts = 0);
   pragma Assert (Status.Lockout_Intervals_Remaining = 0);
   pragma Assert
     (Request_Decision
        (Config => Lockout_Config,
         Status => Status,
         Token_Present => True,
         Token_Valid => True) = Deny_Not_Paired);

   Status := Advance_Pairing_Status
     (Config => Lockout_Config,
      Status => Status,
      Pairing_Succeeded => True);
   pragma Assert (Status.State = Paired);
   pragma Assert (Status.Failed_Attempts = 0);
   pragma Assert (Status.Lockout_Intervals_Remaining = 0);
   pragma Assert
     (Request_Authorized
        (Config => Lockout_Config,
         Status => Status,
         Token_Present => True,
         Token_Valid => True));

   Status := Advance_Pairing_Status
     (Config => Lockout_Config,
      Status => Status,
      Pairing_Attempt_Failed => True);
   Status := Reset_Pairing_Status (Status);
   pragma Assert (Status.State = Unpaired);
   pragma Assert (Status.Failed_Attempts = 0);
   pragma Assert (Status.Lockout_Intervals_Remaining = 0);
end Gateway_Auth_Policy;
