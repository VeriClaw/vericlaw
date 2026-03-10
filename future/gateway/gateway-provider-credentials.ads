with Gateway.Provider.Registry;

package Gateway.Provider.Credentials with SPARK_Mode is
   use type Gateway.Provider.Registry.Provider_Id;

   type Provider_Token is record
      Provider      : Gateway.Provider.Registry.Provider_Id :=
        Gateway.Provider.Registry.Primary_Provider;
      Token_Present : Boolean := False;
   end record;

   type Credential_Decision is
     (Credential_Allow,
      Credential_Deny_Missing_Token,
      Credential_Deny_Provider_Mismatch,
      Credential_Deny_Cross_Provider_Fallback);

   function Bind_Token
     (Provider      : Gateway.Provider.Registry.Provider_Id;
      Token_Present : Boolean) return Provider_Token
   with
     Post =>
       (Bind_Token'Result.Provider = Provider
        and then Bind_Token'Result.Token_Present = Token_Present);

   function Access_Decision
     (Token              : Provider_Token;
      Requested_Provider : Gateway.Provider.Registry.Provider_Id;
      Is_Fallback        : Boolean) return Credential_Decision
   with
     Post =>
       (if not Token.Token_Present then
           Access_Decision'Result = Credential_Deny_Missing_Token
        elsif Token.Provider /= Requested_Provider and then Is_Fallback then
           Access_Decision'Result = Credential_Deny_Cross_Provider_Fallback
        elsif Token.Provider /= Requested_Provider then
           Access_Decision'Result = Credential_Deny_Provider_Mismatch
        else
           Access_Decision'Result = Credential_Allow);

   function Token_Authorizes
     (Token              : Provider_Token;
      Requested_Provider : Gateway.Provider.Registry.Provider_Id;
      Is_Fallback        : Boolean) return Boolean
   with
     Post =>
       Token_Authorizes'Result =
         (Access_Decision
            (Token              => Token,
             Requested_Provider => Requested_Provider,
             Is_Fallback        => Is_Fallback) = Credential_Allow);
end Gateway.Provider.Credentials;
