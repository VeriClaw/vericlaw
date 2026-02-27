package Plugins.Capabilities with SPARK_Mode is
   type Tool_Kind is
     (File_Read_Tool,
      File_Write_Tool,
      Command_Exec_Tool,
      Network_Fetch_Tool);

   type Tool_Grant_Set is array (Tool_Kind) of Boolean;

   type Signature_Verification_State is
     (Manifest_Unsigned,
      Manifest_Signed_Untrusted_Key,
      Manifest_Signed_Trusted_Key);

   type Capability_Manifest is record
      Granted_Tools : Tool_Grant_Set := (others => False);
      Signature     : Signature_Verification_State := Manifest_Unsigned;
   end record;

   type Signature_Decision is
     (Signature_Allow,
      Signature_Deny_Unsigned,
      Signature_Deny_Untrusted_Key);

   function Signature_Policy_Decision
     (State : Signature_Verification_State) return Signature_Decision
   with
     Post =>
       (if State = Manifest_Unsigned then
           Signature_Policy_Decision'Result = Signature_Deny_Unsigned
        elsif State = Manifest_Signed_Untrusted_Key then
           Signature_Policy_Decision'Result = Signature_Deny_Untrusted_Key
        else
           Signature_Policy_Decision'Result = Signature_Allow);

   type Tool_Access_Decision is
     (Tool_Access_Allow,
      Tool_Access_Deny_Unsigned_Manifest,
      Tool_Access_Deny_Untrusted_Key,
      Tool_Access_Deny_Tool_Not_Granted);

   type Tool_Access_Result is record
      Allowed  : Boolean := False;
      Decision : Tool_Access_Decision := Tool_Access_Deny_Unsigned_Manifest;
   end record;

   function Authorize_Tool_Access
     (Manifest       : Capability_Manifest;
      Requested_Tool : Tool_Kind) return Tool_Access_Result
   with
     Post =>
       (if Signature_Policy_Decision (Manifest.Signature) =
             Signature_Deny_Unsigned then
           Authorize_Tool_Access'Result.Decision =
             Tool_Access_Deny_Unsigned_Manifest
        elsif Signature_Policy_Decision (Manifest.Signature) =
          Signature_Deny_Untrusted_Key then
           Authorize_Tool_Access'Result.Decision =
             Tool_Access_Deny_Untrusted_Key
        elsif Manifest.Granted_Tools (Requested_Tool) then
           Authorize_Tool_Access'Result.Decision = Tool_Access_Allow
        else
           Authorize_Tool_Access'Result.Decision =
             Tool_Access_Deny_Tool_Not_Granted)
       and then
       (if Authorize_Tool_Access'Result.Allowed then
           Authorize_Tool_Access'Result.Decision = Tool_Access_Allow
        else
           Authorize_Tool_Access'Result.Decision /= Tool_Access_Allow);

   function Tool_Access_Allowed
      (Manifest       : Capability_Manifest;
       Requested_Tool : Tool_Kind) return Boolean
    with
      Post =>
        Tool_Access_Allowed'Result =
          (Authorize_Tool_Access
             (Manifest       => Manifest,
              Requested_Tool => Requested_Tool).Decision = Tool_Access_Allow);

   type Operator_Permission_State is
     (Operator_Consent_Missing,
      Operator_Consent_Approved,
      Operator_Consent_Denied);

   function Tool_Requires_Operator_Consent
     (Requested_Tool : Tool_Kind) return Boolean
   with
     Post =>
       Tool_Requires_Operator_Consent'Result =
         (Requested_Tool in
            File_Write_Tool | Command_Exec_Tool | Network_Fetch_Tool);

   type Operator_Consent_Decision is
     (Operator_Consent_Allow_Not_Required,
      Operator_Consent_Allow_Approved,
      Operator_Consent_Deny_Missing,
      Operator_Consent_Deny_Explicit);

   function Operator_Consent_Policy_Decision
     (Requested_Tool   : Tool_Kind;
      Operator_Consent : Operator_Permission_State)
      return Operator_Consent_Decision
   with
     Post =>
       (if not Tool_Requires_Operator_Consent (Requested_Tool) then
           Operator_Consent_Policy_Decision'Result =
             Operator_Consent_Allow_Not_Required
        elsif Operator_Consent = Operator_Consent_Approved then
           Operator_Consent_Policy_Decision'Result =
             Operator_Consent_Allow_Approved
        elsif Operator_Consent = Operator_Consent_Denied then
           Operator_Consent_Policy_Decision'Result =
             Operator_Consent_Deny_Explicit
        else
           Operator_Consent_Policy_Decision'Result =
             Operator_Consent_Deny_Missing);

   function Operator_Consent_Allowed
     (Requested_Tool   : Tool_Kind;
      Operator_Consent : Operator_Permission_State) return Boolean
   with
     Post =>
       Operator_Consent_Allowed'Result =
         (Operator_Consent_Policy_Decision
            (Requested_Tool   => Requested_Tool,
             Operator_Consent => Operator_Consent) in
               Operator_Consent_Allow_Not_Required
               | Operator_Consent_Allow_Approved);

   --  SPARK-verified depth bound for multi-agent delegation.
   function Delegation_Allowed
     (Depth : Natural;
      Max   : Natural) return Boolean
   with
     Post => Delegation_Allowed'Result = (Depth < Max);

end Plugins.Capabilities;
