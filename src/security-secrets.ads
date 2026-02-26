package Security.Secrets with SPARK_Mode is
   type Key_Source is (Env_Key, OS_Key_Store);
   subtype Key_Version is Natural range 0 .. 255;

   type Secret_Config is record
      Source            : Key_Source := OS_Key_Store;
      Env_Key_Set       : Boolean := False;
      Encrypted_At_Rest : Boolean := True;
      Active_Key_Version : Key_Version := 1;
      Require_Sealed_Key : Boolean := False;
   end record;

   function Key_Source_Valid (Config : Secret_Config) return Boolean
   with
     Post =>
       Key_Source_Valid'Result =
         ((Config.Source = Env_Key and then Config.Env_Key_Set)
          or else
          (Config.Source = OS_Key_Store and then not Config.Env_Key_Set));

   function Config_Valid (Config : Secret_Config) return Boolean
   with
      Post =>
         Config_Valid'Result =
           (Config.Encrypted_At_Rest
            and then Config.Active_Key_Version > 0
            and then Key_Source_Valid (Config)
            and then
              (if Config.Require_Sealed_Key then Config.Source = OS_Key_Store
               else True));

   type Secret_Metadata is record
      Identifier_Set     : Boolean := False;
      Classification_Set : Boolean := False;
      Redacted_For_Audit : Boolean := True;
   end record;

   function Metadata_Valid (Metadata : Secret_Metadata) return Boolean
   with
     Post =>
       Metadata_Valid'Result =
         (Metadata.Identifier_Set
          and then Metadata.Classification_Set
          and then Metadata.Redacted_For_Audit);

   function Redact_For_Audit (Metadata : Secret_Metadata) return Secret_Metadata
   with
      Post =>
        (Redact_For_Audit'Result.Identifier_Set = Metadata.Identifier_Set
         and then
         Redact_For_Audit'Result.Classification_Set = Metadata.Classification_Set
         and then Redact_For_Audit'Result.Redacted_For_Audit);

   type Secret_State is record
      Stored_Key_Version : Key_Version := 1;
      Sealed_Key_Loaded  : Boolean := False;
   end record;

   function State_Valid
     (Config : Secret_Config;
      State  : Secret_State) return Boolean
   with
      Post =>
        State_Valid'Result =
          (State.Stored_Key_Version > 0
           and then State.Stored_Key_Version <= Config.Active_Key_Version
           and then
             (if Config.Require_Sealed_Key then State.Sealed_Key_Loaded
              else True));

   type Rotation_Decision is
     (Rotation_Allow_Noop,
      Rotation_Allow_Reencrypt,
      Rotation_Deny_Invalid_Config,
      Rotation_Deny_Invalid_State,
      Rotation_Deny_Sealed_Key_Unavailable,
      Rotation_Deny_Version_Downgrade,
      Rotation_Deny_Target_Not_Active,
      Rotation_Deny_Reencrypt_Required);

   function Rotation_Policy_Decision
     (Config              : Secret_Config;
      State               : Secret_State;
      Target_Key_Version  : Key_Version;
      Reencrypt_Requested : Boolean) return Rotation_Decision;

   function Rotation_Allowed
     (Config              : Secret_Config;
      State               : Secret_State;
      Target_Key_Version  : Key_Version;
      Reencrypt_Requested : Boolean) return Boolean
   with
      Post =>
        Rotation_Allowed'Result =
          (Rotation_Policy_Decision
             (Config              => Config,
              State               => State,
              Target_Key_Version  => Target_Key_Version,
              Reencrypt_Requested => Reencrypt_Requested)
           in Rotation_Allow_Noop | Rotation_Allow_Reencrypt);

   type Secret_Error is
      (No_Error,
      Storage_Not_Encrypted,
      Key_Source_Constraint_Violation,
      Invalid_Metadata,
      Key_Source_Unavailable,
      Missing_Key_Material,
      Secret_Not_Ingested,
      Storage_Backend_Unavailable,
      Crypto_Runtime_Unavailable,
       Missing_Nonce,
       Invalid_Secret_Payload,
       Ciphertext_Truncated,
       Authentication_Failed,
       Invalid_Key_Version,
       Sealed_Key_Unavailable,
       Rotation_Denied,
       Reencryption_Required);

   type Secret_Result is record
      Success : Boolean := False;
      Error   : Secret_Error := Secret_Not_Ingested;
   end record;

   function Ingest
     (Config           : Secret_Config;
      Metadata         : Secret_Metadata;
      Source_Available : Boolean;
      Key_Material_Set : Boolean) return Secret_Result
   with
     Post =>
       ((if Ingest'Result.Success then Ingest'Result.Error = No_Error
         else Ingest'Result.Error /= No_Error)
        and then
          (if Ingest'Result.Success then
              (Config_Valid (Config)
               and then Metadata_Valid (Metadata)
               and then Source_Available
               and then Key_Material_Set)
           else True));

   function Store
     (Config            : Secret_Config;
      Ingestion         : Secret_Result;
      Storage_Available : Boolean) return Secret_Result
   with
     Post =>
       ((if Store'Result.Success then Store'Result.Error = No_Error
         else Store'Result.Error /= No_Error)
        and then
          (if Store'Result.Success then
              (Config_Valid (Config)
               and then Ingestion.Success
               and then Storage_Available)
           else True));
end Security.Secrets;
