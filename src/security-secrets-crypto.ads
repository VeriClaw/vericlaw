package Security.Secrets.Crypto with SPARK_Mode is
   Max_Message_Length : constant Positive := 128;
   Nonce_Length       : constant Positive := 24;

   subtype Message_Length is Natural range 0 .. Max_Message_Length;
   subtype Message_Index is Positive range 1 .. Max_Message_Length;
   subtype Nonce_Index is Positive range 1 .. Nonce_Length;

   type Message_Buffer is array (Message_Index) of Character;
   type Nonce_Buffer is array (Nonce_Index) of Character;

   type Secret_Message is record
      Length : Message_Length := 0;
      Data   : Message_Buffer := (others => Character'Val (0));
   end record;

   type Secret_Nonce is record
      Is_Set : Boolean := False;
      Data   : Nonce_Buffer := (others => Character'Val (0));
   end record;

   Null_Message : constant Secret_Message :=
     (Length => 0, Data => (others => Character'Val (0)));
   Null_Nonce : constant Secret_Nonce :=
     (Is_Set => False, Data => (others => Character'Val (0)));

   type Crypto_Backend is (Deterministic_Backend, Libsodium_Backend);

   type Runtime_Adapter is record
      Backend                 : Crypto_Backend := Libsodium_Backend;
      Available               : Boolean := False;
      Deterministic_Test_Mode : Boolean := False;
   end record;

   type Runtime_Mode is (Runtime_Mode_Production, Runtime_Mode_Test);

   function Select_Runtime_Adapter
     (Production_Backend_Available : Boolean;
      Mode                         : Runtime_Mode := Runtime_Mode_Production)
      return Runtime_Adapter
   with
      Post =>
        (if Mode = Runtime_Mode_Production then
            (Select_Runtime_Adapter'Result.Backend = Libsodium_Backend
             and then Select_Runtime_Adapter'Result.Available =
               Production_Backend_Available
             and then not Select_Runtime_Adapter'Result.Deterministic_Test_Mode)
         else
            (Select_Runtime_Adapter'Result.Backend = Deterministic_Backend
             and then Select_Runtime_Adapter'Result.Available
             and then Select_Runtime_Adapter'Result.Deterministic_Test_Mode));

   function Adapter_Ready (Adapter : Runtime_Adapter) return Boolean
   with
      Post =>
        (if Adapter.Backend = Deterministic_Backend then
            Adapter_Ready'Result =
              (Adapter.Available and then Adapter.Deterministic_Test_Mode)
         else
            Adapter_Ready'Result =
              (Adapter.Available and then not Adapter.Deterministic_Test_Mode));

   type Runtime_Status is
     (Runtime_Success,
      Runtime_Deny_Storage_Not_Encrypted,
      Runtime_Deny_Adapter_Unavailable,
      Runtime_Deny_Missing_Key_Material,
      Runtime_Deny_Missing_Nonce,
      Runtime_Deny_Empty_Plaintext,
      Runtime_Deny_Plaintext_Too_Long,
      Runtime_Deny_Empty_Ciphertext,
      Runtime_Deny_Ciphertext_Truncated,
      Runtime_Deny_Authentication_Failed,
      Runtime_Deny_Invalid_Key_Rotation,
      Runtime_Deny_Sealed_Key_Unavailable,
      Runtime_Deny_Reencrypt_Required);

   type Encryption_Result is record
      Success    : Boolean := False;
      Status     : Runtime_Status := Runtime_Deny_Adapter_Unavailable;
      Ciphertext : Secret_Message := Null_Message;
      Nonce      : Secret_Nonce := Null_Nonce;
   end record;

   type Decryption_Result is record
      Success   : Boolean := False;
      Status    : Runtime_Status := Runtime_Deny_Adapter_Unavailable;
      Plaintext : Secret_Message := Null_Message;
   end record;

   type Comparison_Decision is (Compare_Match, Compare_Mismatch);

   function Constant_Time_Decision
     (Left, Right : Secret_Message) return Comparison_Decision;

   function Constant_Time_Equals
     (Left, Right : Secret_Message) return Boolean
   with
     Post =>
       Constant_Time_Equals'Result =
         (Constant_Time_Decision (Left => Left, Right => Right) = Compare_Match);

   function Deterministic_Nonce (Seed : Natural) return Secret_Nonce
   with
     Post => Deterministic_Nonce'Result.Is_Set;

   function To_Secret_Message (Value : String) return Secret_Message
   with
     Post => To_Secret_Message'Result.Length <= Max_Message_Length;

   function To_String (Value : Secret_Message) return String
   with
     Pre => Value.Length <= Max_Message_Length;

   function Encrypt
     (Config    : Secret_Config;
      Adapter   : Runtime_Adapter;
      Key       : Secret_Message;
      Plaintext : Secret_Message;
      Nonce     : Secret_Nonce) return Encryption_Result
   with
     Post =>
       ((if Encrypt'Result.Success then Encrypt'Result.Status = Runtime_Success
         else Encrypt'Result.Status /= Runtime_Success)
        and then
          (if Encrypt'Result.Success then
             (Config_Valid (Config)
              and then Adapter_Ready (Adapter)
              and then Key.Length > 0
              and then Plaintext.Length > 0
              and then Nonce.Is_Set)
           else True));

   function Decrypt
     (Config     : Secret_Config;
      Adapter    : Runtime_Adapter;
      Key        : Secret_Message;
      Ciphertext : Secret_Message;
      Nonce      : Secret_Nonce) return Decryption_Result
   with
     Post =>
       ((if Decrypt'Result.Success then Decrypt'Result.Status = Runtime_Success
         else Decrypt'Result.Status /= Runtime_Success)
        and then
          (if Decrypt'Result.Success then
             (Config_Valid (Config)
              and then Adapter_Ready (Adapter)
              and then Key.Length > 0
              and then Ciphertext.Length > 1
              and then Nonce.Is_Set)
           else True));

   type Reencrypt_Result is record
      Success    : Boolean := False;
      Status     : Runtime_Status := Runtime_Deny_Invalid_Key_Rotation;
      Ciphertext : Secret_Message := Null_Message;
      Nonce      : Secret_Nonce := Null_Nonce;
   end record;

   function Reencrypt_For_Rotation
     (Config              : Secret_Config;
      State               : Secret_State;
      Adapter             : Runtime_Adapter;
      Source_Key          : Secret_Message;
      Target_Key          : Secret_Message;
      Ciphertext          : Secret_Message;
      Nonce               : Secret_Nonce;
      Target_Key_Version  : Key_Version;
      Reencrypt_Requested : Boolean) return Reencrypt_Result
   with
      Post =>
        (if Reencrypt_For_Rotation'Result.Success then
            Reencrypt_For_Rotation'Result.Status = Runtime_Success
         else
            Reencrypt_For_Rotation'Result.Status /= Runtime_Success);

   function As_Secret_Result (Status : Runtime_Status) return Secret_Result
   with
     Post =>
       ((if As_Secret_Result'Result.Success then Status = Runtime_Success
         else Status /= Runtime_Success)
        and then
          (if Status = Runtime_Success then
             As_Secret_Result'Result.Error = No_Error
           else As_Secret_Result'Result.Error /= No_Error));
end Security.Secrets.Crypto;
