package body Plugins.Capabilities with SPARK_Mode is
   function Signature_Policy_Decision
     (State : Signature_Verification_State) return Signature_Decision is
   begin
      case State is
         when Manifest_Unsigned =>
            return Signature_Deny_Unsigned;
         when Manifest_Signed_Untrusted_Key =>
            return Signature_Deny_Untrusted_Key;
         when Manifest_Signed_Trusted_Key =>
            return Signature_Allow;
      end case;
   end Signature_Policy_Decision;

   function Authorize_Tool_Access
     (Manifest       : Capability_Manifest;
      Requested_Tool : Tool_Kind) return Tool_Access_Result is
      Signature_Result : constant Signature_Decision :=
        Signature_Policy_Decision (Manifest.Signature);
   begin
      case Signature_Result is
         when Signature_Deny_Unsigned =>
            return
              (Allowed  => False,
               Decision => Tool_Access_Deny_Unsigned_Manifest);
         when Signature_Deny_Untrusted_Key =>
            return
              (Allowed  => False,
               Decision => Tool_Access_Deny_Untrusted_Key);
         when Signature_Allow =>
            if Manifest.Granted_Tools (Requested_Tool) then
               return (Allowed => True, Decision => Tool_Access_Allow);
            end if;
            return
              (Allowed  => False,
               Decision => Tool_Access_Deny_Tool_Not_Granted);
      end case;
   end Authorize_Tool_Access;

   function Tool_Access_Allowed
      (Manifest       : Capability_Manifest;
       Requested_Tool : Tool_Kind) return Boolean is
   begin
      return
        Authorize_Tool_Access
          (Manifest       => Manifest,
           Requested_Tool => Requested_Tool).Allowed;
   end Tool_Access_Allowed;

   function Tool_Requires_Operator_Consent
     (Requested_Tool : Tool_Kind) return Boolean is
   begin
      return Requested_Tool in
        File_Write_Tool | Command_Exec_Tool | Network_Fetch_Tool;
   end Tool_Requires_Operator_Consent;

   function Operator_Consent_Policy_Decision
     (Requested_Tool   : Tool_Kind;
      Operator_Consent : Operator_Permission_State)
      return Operator_Consent_Decision is
   begin
      if not Tool_Requires_Operator_Consent (Requested_Tool) then
         return Operator_Consent_Allow_Not_Required;
      elsif Operator_Consent = Operator_Consent_Approved then
         return Operator_Consent_Allow_Approved;
      elsif Operator_Consent = Operator_Consent_Denied then
         return Operator_Consent_Deny_Explicit;
      end if;
      return Operator_Consent_Deny_Missing;
   end Operator_Consent_Policy_Decision;

   function Operator_Consent_Allowed
     (Requested_Tool   : Tool_Kind;
      Operator_Consent : Operator_Permission_State) return Boolean is
   begin
      return Operator_Consent_Policy_Decision
        (Requested_Tool   => Requested_Tool,
         Operator_Consent => Operator_Consent) in
           Operator_Consent_Allow_Not_Required
           | Operator_Consent_Allow_Approved;
   end Operator_Consent_Allowed;
end Plugins.Capabilities;
