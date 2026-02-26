with Gateway.Provider.Credentials;
with Security.Audit;
with Security.Policy;
with Security.Secrets;
with Security.Secrets.Crypto;

procedure Security_Secrets_Tests is
   use Gateway.Provider.Credentials;
   use Security.Audit;
   use Security.Policy;
   use Security.Secrets;
   use Security.Secrets.Crypto;

   OS_Default : constant Secret_Config :=
      (Source             => OS_Key_Store,
       Env_Key_Set        => False,
       Encrypted_At_Rest  => True,
       Active_Key_Version => 1,
       Require_Sealed_Key => False);
   Env_Config : constant Secret_Config :=
      (Source             => Env_Key,
       Env_Key_Set        => True,
       Encrypted_At_Rest  => True,
       Active_Key_Version => 1,
       Require_Sealed_Key => False);
   Insecure_Config : constant Secret_Config :=
      (Source             => Env_Key,
       Env_Key_Set        => True,
       Encrypted_At_Rest  => False,
       Active_Key_Version => 1,
       Require_Sealed_Key => False);
   Rotation_Config : constant Secret_Config :=
      (Source             => OS_Key_Store,
       Env_Key_Set        => False,
       Encrypted_At_Rest  => True,
       Active_Key_Version => 2,
       Require_Sealed_Key => True);
   Rotation_State : constant Secret_State :=
      (Stored_Key_Version => 1, Sealed_Key_Loaded => True);
   Sealed_Key_Missing_State : constant Secret_State :=
      (Stored_Key_Version => 1, Sealed_Key_Loaded => False);

   Secure_Metadata : constant Secret_Metadata :=
     (Identifier_Set     => True,
      Classification_Set => True,
      Redacted_For_Audit => True);
   Raw_Metadata : constant Secret_Metadata :=
     (Identifier_Set     => True,
      Classification_Set => True,
      Redacted_For_Audit => False);
   Secure_Audit_Payload : constant Redacted_Payload :=
     (Subject_Set              => True,
      Classification_Set       => True,
      Redaction_Metadata_Valid => True,
      Includes_Secret_Material => False,
      Includes_Token_Material  => False);
   Invalid_Metadata_Audit_Payload : constant Redacted_Payload :=
     (Subject_Set              => True,
      Classification_Set       => True,
      Redaction_Metadata_Valid => False,
      Includes_Secret_Material => False,
      Includes_Token_Material  => False);
   Secret_Leak_Audit_Payload : constant Redacted_Payload :=
     (Subject_Set              => True,
      Classification_Set       => True,
      Redaction_Metadata_Valid => True,
      Includes_Secret_Material => True,
      Includes_Token_Material  => False);
   Token_Leak_Audit_Payload : constant Redacted_Payload :=
     (Subject_Set              => True,
      Classification_Set       => True,
      Redaction_Metadata_Valid => True,
      Includes_Secret_Material => False,
      Includes_Token_Material  => True);

   Result : Secret_Result;
   Encrypt_Result : Encryption_Result;
   Decrypt_Result : Decryption_Result;
   Rotation_Result : Reencrypt_Result;
   Tampered : Secret_Message;

   Production_Runtime : constant Runtime_Adapter :=
     Select_Runtime_Adapter (Production_Backend_Available => True);
   Missing_Runtime : constant Runtime_Adapter :=
     Select_Runtime_Adapter (Production_Backend_Available => False);
   Deterministic_Test_Runtime : constant Runtime_Adapter :=
     Select_Runtime_Adapter
       (Production_Backend_Available => False,
        Mode                         => Runtime_Mode_Test);
   Deterministic_Runtime_Disabled : constant Runtime_Adapter :=
      (Backend                 => Deterministic_Backend,
       Available               => True,
       Deterministic_Test_Mode => False);
   Crypto_Key : constant Secret_Message := To_Secret_Message ("vericlaw-lab-key");
   Legacy_Crypto_Key : constant Secret_Message :=
      To_Secret_Message ("vericlaw-legacy-key");
   Rotated_Crypto_Key : constant Secret_Message :=
      To_Secret_Message ("vericlaw-rotated-key");
   Crypto_Plaintext : constant Secret_Message :=
      To_Secret_Message ("provider-token");
   Crypto_Nonce : constant Secret_Nonce := Deterministic_Nonce (Seed => 19);
begin
   pragma Assert (Config_Valid (OS_Default));
   pragma Assert (Config_Valid (Env_Config));
   pragma Assert (Config_Valid (Rotation_Config));
   pragma Assert
      (not Config_Valid
         ((Source             => OS_Key_Store,
           Env_Key_Set        => True,
           Encrypted_At_Rest  => True,
           Active_Key_Version => 1,
           Require_Sealed_Key => False)));
   pragma Assert
     (not Config_Valid
        ((Source             => Env_Key,
          Env_Key_Set        => True,
          Encrypted_At_Rest  => True,
          Active_Key_Version => 1,
          Require_Sealed_Key => True)));
   pragma Assert (State_Valid (Rotation_Config, Rotation_State));
   pragma Assert (not State_Valid (Rotation_Config, Sealed_Key_Missing_State));

   pragma Assert (Metadata_Valid (Secure_Metadata));
   pragma Assert (not Metadata_Valid (Raw_Metadata));
   pragma Assert (Metadata_Valid (Redact_For_Audit (Raw_Metadata)));
   pragma Assert (Redaction_Metadata_Valid (Secure_Audit_Payload));
   pragma Assert (Payload_Is_Redacted (Secure_Audit_Payload));
   pragma Assert (not Redaction_Metadata_Valid (Invalid_Metadata_Audit_Payload));
   pragma Assert
     (Append_Policy_Decision
        (Kind    => Event_Secret_Ingest,
         Payload => Secure_Audit_Payload) = Append_Allow);
   pragma Assert
     (Append_Policy_Decision
        (Kind    => Event_Secret_Ingest,
         Payload => Invalid_Metadata_Audit_Payload) =
          Append_Deny_Invalid_Redaction_Metadata);
   pragma Assert
     (Append_Policy_Decision
        (Kind    => Event_Secret_Ingest,
         Payload => Secret_Leak_Audit_Payload) =
          Append_Deny_Unredacted_Secret_Material);
   pragma Assert
     (Append_Policy_Decision
        (Kind    => Event_Secret_Ingest,
         Payload => Token_Leak_Audit_Payload) =
          Append_Deny_Unredacted_Token_Material);
   pragma Assert
     (not Append_Allowed
        (Kind    => Event_Secret_Ingest,
         Payload => Invalid_Metadata_Audit_Payload));
   pragma Assert
     (Retention_Policy_Decision
        (Current_Entries    => 0,
         Max_Entries        => 0,
         Oldest_Age_Seconds => 0,
         Max_Age_Seconds    => 60) = Retention_Deny_Invalid_Limits);
   pragma Assert
     (Retention_Policy_Decision
        (Current_Entries    => 10,
         Max_Entries        => 10,
         Oldest_Age_Seconds => 5,
         Max_Age_Seconds    => 60) = Retention_Drop_Oldest_Max_Entries);
   pragma Assert
     (Retention_Policy_Decision
        (Current_Entries    => 2,
         Max_Entries        => 10,
         Oldest_Age_Seconds => 61,
         Max_Age_Seconds    => 60) = Retention_Drop_Oldest_Max_Age);
   pragma Assert
     (Retention_Policy_Decision
        (Current_Entries    => 10,
         Max_Entries        => 10,
         Oldest_Age_Seconds => 61,
         Max_Age_Seconds    => 60) = Retention_Drop_Oldest_Max_Entries_And_Age);
   pragma Assert
     (Retention_Policy_Decision
        (Current_Entries    => 2,
         Max_Entries        => 10,
         Oldest_Age_Seconds => 60,
         Max_Age_Seconds    => 60) = Retention_Keep);
   pragma Assert
     (not Retention_Allows_Append
        (Current_Entries    => 0,
         Max_Entries        => 0,
         Oldest_Age_Seconds => 0,
         Max_Age_Seconds    => 60));
   pragma Assert
     (Retention_Allows_Append
        (Current_Entries    => 10,
         Max_Entries        => 10,
         Oldest_Age_Seconds => 61,
         Max_Age_Seconds    => 60));

   pragma Assert
      (Secret_Match_Policy_Decision
        (Host_Matches    => True,
         Pattern_Matches => True) = Secret_Match_Allow);
   pragma Assert
     (Secret_Match_Policy_Decision
        (Host_Matches    => False,
         Pattern_Matches => True) = Secret_Match_Deny_Host_Mismatch);
   pragma Assert
     (Secret_Match_Policy_Decision
        (Host_Matches    => True,
         Pattern_Matches => False) = Secret_Match_Deny_Pattern_Mismatch);
   pragma Assert
     (Secret_Match_Policy_Decision
        (Host_Matches    => False,
         Pattern_Matches => False) =
          Secret_Match_Deny_Host_And_Pattern_Mismatch);

   pragma Assert
     (Secret_Injection_Policy_Decision
        (Credential_Scope => Credential_Allow,
         Host_Matches     => True,
         Pattern_Matches  => True) = Secret_Injection_Allow);
   pragma Assert
     (Secret_Injection_Policy_Decision
        (Credential_Scope => Credential_Deny_Provider_Mismatch,
         Host_Matches     => True,
         Pattern_Matches  => True) =
          Secret_Injection_Deny_Provider_Mismatch);
   pragma Assert
     (Secret_Injection_Policy_Decision
        (Credential_Scope => Credential_Deny_Cross_Provider_Fallback,
         Host_Matches     => True,
         Pattern_Matches  => True) =
          Secret_Injection_Deny_Cross_Provider_Fallback);
   pragma Assert
     (not Secret_Injection_Allowed
        (Credential_Scope => Credential_Deny_Provider_Mismatch,
         Host_Matches     => True,
         Pattern_Matches  => True));

   Result :=
     Ingest (Config           => Env_Config,
             Metadata         => Secure_Metadata,
             Source_Available => True,
             Key_Material_Set => True);
   pragma Assert (Result.Success and then Result.Error = No_Error);

   Result :=
     Ingest (Config           => Env_Config,
             Metadata         => Raw_Metadata,
             Source_Available => True,
             Key_Material_Set => True);
   pragma Assert ((not Result.Success) and then Result.Error = Invalid_Metadata);

   Result :=
     Store (Config            => Insecure_Config,
            Ingestion         => (Success => True, Error => No_Error),
            Storage_Available => True);
   pragma Assert
     ((not Result.Success) and then Result.Error = Storage_Not_Encrypted);

   Result :=
      Store (Config            => Env_Config,
             Ingestion         => (Success => False, Error => No_Error),
             Storage_Available => True);
   pragma Assert
      ((not Result.Success) and then Result.Error = Secret_Not_Ingested);

   pragma Assert
     (Constant_Time_Decision
        (Left  => To_Secret_Message ("token-alpha"),
         Right => To_Secret_Message ("token-alpha")) = Compare_Match);
   pragma Assert
     (Constant_Time_Decision
        (Left  => To_Secret_Message ("token-alpha"),
         Right => To_Secret_Message ("token-beta")) = Compare_Mismatch);
   pragma Assert
     (not Constant_Time_Equals
        (Left  => To_Secret_Message ("token-alpha"),
         Right => To_Secret_Message ("token-alpha-extended")));
   pragma Assert (Production_Runtime.Backend = Libsodium_Backend);
   pragma Assert (Adapter_Ready (Production_Runtime));
   pragma Assert (not Adapter_Ready (Missing_Runtime));
   pragma Assert (Deterministic_Test_Runtime.Backend = Deterministic_Backend);
   pragma Assert (Adapter_Ready (Deterministic_Test_Runtime));
   pragma Assert
     (Rotation_Policy_Decision
        (Config              => Rotation_Config,
         State               => Rotation_State,
         Target_Key_Version  => Rotation_Config.Active_Key_Version,
         Reencrypt_Requested => True) = Rotation_Allow_Reencrypt);
   pragma Assert
     (Rotation_Allowed
        (Config              => Rotation_Config,
         State               => Rotation_State,
         Target_Key_Version  => Rotation_Config.Active_Key_Version,
         Reencrypt_Requested => True));
   pragma Assert
     (Rotation_Policy_Decision
        (Config              => Rotation_Config,
         State               => Sealed_Key_Missing_State,
         Target_Key_Version  => Rotation_Config.Active_Key_Version,
         Reencrypt_Requested => True) = Rotation_Deny_Sealed_Key_Unavailable);
   pragma Assert
     (Rotation_Policy_Decision
        (Config              => Rotation_Config,
         State               =>
           (Stored_Key_Version => Rotation_Config.Active_Key_Version,
            Sealed_Key_Loaded  => True),
         Target_Key_Version  => 1,
         Reencrypt_Requested => True) = Rotation_Deny_Version_Downgrade);
   pragma Assert
     (Rotation_Policy_Decision
        (Config              => Rotation_Config,
         State               => Rotation_State,
         Target_Key_Version  => Rotation_Config.Active_Key_Version,
         Reencrypt_Requested => False) = Rotation_Deny_Reencrypt_Required);
   pragma Assert
     (not Rotation_Allowed
        (Config              => Rotation_Config,
         State               =>
           (Stored_Key_Version => Rotation_Config.Active_Key_Version,
            Sealed_Key_Loaded  => True),
         Target_Key_Version  => 1,
         Reencrypt_Requested => True));

   Encrypt_Result :=
       Encrypt
         (Config    => Env_Config,
         Adapter   => Production_Runtime,
         Key       => Crypto_Key,
         Plaintext => Crypto_Plaintext,
         Nonce     => Crypto_Nonce);
   pragma Assert (Encrypt_Result.Success);
   pragma Assert (Encrypt_Result.Status = Runtime_Success);
   pragma Assert (Encrypt_Result.Ciphertext.Length = Crypto_Plaintext.Length + 1);

   Decrypt_Result :=
      Decrypt
        (Config     => Env_Config,
         Adapter    => Production_Runtime,
         Key        => Crypto_Key,
         Ciphertext => Encrypt_Result.Ciphertext,
         Nonce      => Encrypt_Result.Nonce);
   pragma Assert (Decrypt_Result.Success);
   pragma Assert (Decrypt_Result.Status = Runtime_Success);
   pragma Assert (To_String (Decrypt_Result.Plaintext) = "provider-token");

   Encrypt_Result :=
     Encrypt
       (Config    => Env_Config,
        Adapter   => Deterministic_Test_Runtime,
        Key       => Crypto_Key,
        Plaintext => Crypto_Plaintext,
        Nonce     => Crypto_Nonce);
   pragma Assert (Encrypt_Result.Success);
   pragma Assert (Encrypt_Result.Status = Runtime_Success);

   Encrypt_Result :=
     Encrypt
       (Config    => Env_Config,
        Adapter   => Missing_Runtime,
        Key       => Crypto_Key,
        Plaintext => Crypto_Plaintext,
        Nonce     => Crypto_Nonce);
   pragma Assert
     ((not Encrypt_Result.Success)
      and then Encrypt_Result.Status = Runtime_Deny_Adapter_Unavailable);

   Encrypt_Result :=
     Encrypt
       (Config    => Env_Config,
        Adapter   => Deterministic_Runtime_Disabled,
        Key       => Crypto_Key,
        Plaintext => Crypto_Plaintext,
        Nonce     => Crypto_Nonce);
   pragma Assert
     ((not Encrypt_Result.Success)
      and then Encrypt_Result.Status = Runtime_Deny_Adapter_Unavailable);

   Encrypt_Result :=
      Encrypt
        (Config    => Env_Config,
         Adapter   => Production_Runtime,
         Key       => Crypto_Key,
         Plaintext => Crypto_Plaintext,
         Nonce     => Null_Nonce);
   pragma Assert
     ((not Encrypt_Result.Success)
      and then Encrypt_Result.Status = Runtime_Deny_Missing_Nonce);

   Tampered :=
     Encrypt
       (Env_Config,
        Production_Runtime,
        Crypto_Key,
        Crypto_Plaintext,
        Crypto_Nonce).Ciphertext;
   Tampered.Data (Message_Index (Tampered.Length)) :=
     Character'Val ((Character'Pos (Tampered.Data (Message_Index (Tampered.Length))) + 1) mod 256);
   Decrypt_Result :=
      Decrypt
        (Config     => Env_Config,
         Adapter    => Production_Runtime,
         Key        => Crypto_Key,
         Ciphertext => Tampered,
         Nonce      => Crypto_Nonce);
   pragma Assert
      ((not Decrypt_Result.Success)
       and then Decrypt_Result.Status = Runtime_Deny_Authentication_Failed);

   Encrypt_Result :=
      Encrypt
        (Config    => Rotation_Config,
         Adapter   => Production_Runtime,
         Key       => Legacy_Crypto_Key,
         Plaintext => Crypto_Plaintext,
         Nonce     => Crypto_Nonce);
   pragma Assert (Encrypt_Result.Success);

   Rotation_Result :=
      Reencrypt_For_Rotation
        (Config              => Rotation_Config,
         State               => Rotation_State,
         Adapter             => Production_Runtime,
         Source_Key          => Legacy_Crypto_Key,
         Target_Key          => Rotated_Crypto_Key,
         Ciphertext          => Encrypt_Result.Ciphertext,
         Nonce               => Crypto_Nonce,
         Target_Key_Version  => Rotation_Config.Active_Key_Version,
         Reencrypt_Requested => True);
   pragma Assert (Rotation_Result.Success);
   pragma Assert (Rotation_Result.Status = Runtime_Success);

   Decrypt_Result :=
      Decrypt
        (Config     => Rotation_Config,
         Adapter    => Production_Runtime,
         Key        => Rotated_Crypto_Key,
         Ciphertext => Rotation_Result.Ciphertext,
         Nonce      => Rotation_Result.Nonce);
   pragma Assert (Decrypt_Result.Success);
   pragma Assert (To_String (Decrypt_Result.Plaintext) = "provider-token");

   Rotation_Result :=
      Reencrypt_For_Rotation
        (Config              => Rotation_Config,
         State               => Sealed_Key_Missing_State,
         Adapter             => Production_Runtime,
         Source_Key          => Legacy_Crypto_Key,
         Target_Key          => Rotated_Crypto_Key,
         Ciphertext          => Encrypt_Result.Ciphertext,
         Nonce               => Crypto_Nonce,
         Target_Key_Version  => Rotation_Config.Active_Key_Version,
         Reencrypt_Requested => True);
   pragma Assert
     ((not Rotation_Result.Success)
      and then Rotation_Result.Status = Runtime_Deny_Sealed_Key_Unavailable);

   Rotation_Result :=
      Reencrypt_For_Rotation
        (Config              => Rotation_Config,
         State               => Rotation_State,
         Adapter             => Production_Runtime,
         Source_Key          => Legacy_Crypto_Key,
         Target_Key          => Rotated_Crypto_Key,
         Ciphertext          => Encrypt_Result.Ciphertext,
         Nonce               => Crypto_Nonce,
         Target_Key_Version  => 1,
         Reencrypt_Requested => True);
   pragma Assert
     ((not Rotation_Result.Success)
      and then Rotation_Result.Status = Runtime_Deny_Invalid_Key_Rotation);

   Rotation_Result :=
      Reencrypt_For_Rotation
        (Config              => Rotation_Config,
         State               => Rotation_State,
         Adapter             => Production_Runtime,
         Source_Key          => Legacy_Crypto_Key,
         Target_Key          => Rotated_Crypto_Key,
         Ciphertext          => Encrypt_Result.Ciphertext,
         Nonce               => Crypto_Nonce,
         Target_Key_Version  => Rotation_Config.Active_Key_Version,
         Reencrypt_Requested => False);
   pragma Assert
     ((not Rotation_Result.Success)
      and then Rotation_Result.Status = Runtime_Deny_Reencrypt_Required);

   Result := As_Secret_Result (Runtime_Deny_Missing_Nonce);
   pragma Assert ((not Result.Success) and then Result.Error = Missing_Nonce);
   Result := As_Secret_Result (Runtime_Deny_Authentication_Failed);
   pragma Assert ((not Result.Success) and then Result.Error = Authentication_Failed);
   Result := As_Secret_Result (Runtime_Deny_Sealed_Key_Unavailable);
   pragma Assert ((not Result.Success) and then Result.Error = Sealed_Key_Unavailable);
   Result := As_Secret_Result (Runtime_Deny_Reencrypt_Required);
   pragma Assert ((not Result.Success) and then Result.Error = Reencryption_Required);
end Security_Secrets_Tests;
