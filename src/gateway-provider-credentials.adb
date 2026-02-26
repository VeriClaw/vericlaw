package body Gateway.Provider.Credentials with SPARK_Mode is
   use type Gateway.Provider.Registry.Provider_Id;

   function Bind_Token
     (Provider      : Gateway.Provider.Registry.Provider_Id;
      Token_Present : Boolean) return Provider_Token is
   begin
      return (Provider => Provider, Token_Present => Token_Present);
   end Bind_Token;

   function Access_Decision
     (Token              : Provider_Token;
      Requested_Provider : Gateway.Provider.Registry.Provider_Id;
      Is_Fallback        : Boolean) return Credential_Decision is
   begin
      if not Token.Token_Present then
         return Credential_Deny_Missing_Token;
      elsif Token.Provider /= Requested_Provider and then Is_Fallback then
         return Credential_Deny_Cross_Provider_Fallback;
      elsif Token.Provider /= Requested_Provider then
         return Credential_Deny_Provider_Mismatch;
      else
         return Credential_Allow;
      end if;
   end Access_Decision;

   function Token_Authorizes
     (Token              : Provider_Token;
      Requested_Provider : Gateway.Provider.Registry.Provider_Id;
      Is_Fallback        : Boolean) return Boolean is
   begin
      return Access_Decision
        (Token              => Token,
         Requested_Provider => Requested_Provider,
         Is_Fallback        => Is_Fallback) = Credential_Allow;
   end Token_Authorizes;
end Gateway.Provider.Credentials;
