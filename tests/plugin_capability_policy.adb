with Plugins.Capabilities;

procedure Plugin_Capability_Policy is
   use Plugins.Capabilities;

   Unsigned_Manifest : constant Capability_Manifest :=
     (Granted_Tools => (File_Read_Tool => True, others => False),
      Signature     => Manifest_Unsigned);

   Untrusted_Manifest : constant Capability_Manifest :=
     (Granted_Tools => (File_Read_Tool => True, others => False),
      Signature     => Manifest_Signed_Untrusted_Key);

   Trusted_Manifest : constant Capability_Manifest :=
     (Granted_Tools =>
        (File_Read_Tool     => True,
         File_Write_Tool    => False,
         Command_Exec_Tool  => True,
         Network_Fetch_Tool => False),
      Signature => Manifest_Signed_Trusted_Key);

   Result         : Tool_Access_Result;
   Consent_Result : Operator_Consent_Decision;
begin
   pragma Assert
     (Signature_Policy_Decision (Manifest_Unsigned) = Signature_Deny_Unsigned);
   pragma Assert
     (Signature_Policy_Decision (Manifest_Signed_Untrusted_Key) =
        Signature_Deny_Untrusted_Key);
   pragma Assert
     (Signature_Policy_Decision (Manifest_Signed_Trusted_Key) = Signature_Allow);

   Result :=
     Authorize_Tool_Access
       (Manifest       => Unsigned_Manifest,
        Requested_Tool => File_Read_Tool);
   pragma Assert
     ((not Result.Allowed)
      and then Result.Decision = Tool_Access_Deny_Unsigned_Manifest);

   Result :=
     Authorize_Tool_Access
       (Manifest       => Untrusted_Manifest,
        Requested_Tool => File_Read_Tool);
   pragma Assert
     ((not Result.Allowed)
      and then Result.Decision = Tool_Access_Deny_Untrusted_Key);

   Result :=
     Authorize_Tool_Access
       (Manifest       => Trusted_Manifest,
        Requested_Tool => File_Write_Tool);
   pragma Assert
     ((not Result.Allowed)
      and then Result.Decision = Tool_Access_Deny_Tool_Not_Granted);

   Result :=
     Authorize_Tool_Access
       (Manifest       => Trusted_Manifest,
        Requested_Tool => Command_Exec_Tool);
   pragma Assert (Result.Allowed and then Result.Decision = Tool_Access_Allow);

   pragma Assert
     (Tool_Access_Allowed
        (Manifest       => Trusted_Manifest,
         Requested_Tool => Command_Exec_Tool));
   pragma Assert
     (not Tool_Access_Allowed
        (Manifest       => Unsigned_Manifest,
         Requested_Tool => File_Read_Tool));

   pragma Assert (Tool_Requires_Operator_Consent (Command_Exec_Tool));
   pragma Assert (not Tool_Requires_Operator_Consent (File_Read_Tool));

   Consent_Result :=
     Operator_Consent_Policy_Decision
       (Requested_Tool   => Command_Exec_Tool,
        Operator_Consent => Operator_Consent_Approved);
   pragma Assert (Consent_Result = Operator_Consent_Allow_Approved);

   Consent_Result :=
     Operator_Consent_Policy_Decision
       (Requested_Tool   => Command_Exec_Tool,
        Operator_Consent => Operator_Consent_Denied);
   pragma Assert (Consent_Result = Operator_Consent_Deny_Explicit);

   Consent_Result :=
     Operator_Consent_Policy_Decision
       (Requested_Tool   => Command_Exec_Tool,
        Operator_Consent => Operator_Consent_Missing);
   pragma Assert (Consent_Result = Operator_Consent_Deny_Missing);
   pragma Assert
     (not Operator_Consent_Allowed
        (Requested_Tool   => Command_Exec_Tool,
         Operator_Consent => Operator_Consent_Missing));
end Plugin_Capability_Policy;
