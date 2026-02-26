package body Security.Secrets.Crypto with SPARK_Mode is
   type Byte is mod 2 ** 8;

   function To_Byte (Value : Character) return Byte is
   begin
      return Byte (Character'Pos (Value));
   end To_Byte;

   function To_Character (Value : Byte) return Character is
   begin
      return Character'Val (Integer (Value));
   end To_Character;

   function Message_Byte_At
     (Value : Secret_Message;
      Index : Message_Index) return Byte is
   begin
      if Index <= Value.Length then
         return To_Byte (Value.Data (Index));
      end if;
      return 0;
   end Message_Byte_At;

   function Key_Byte_At
     (Key   : Secret_Message;
      Index : Message_Index) return Byte is
      Key_Index : constant Message_Index :=
        Message_Index (((Index - 1) mod Key.Length) + 1);
   begin
      return To_Byte (Key.Data (Key_Index));
   end Key_Byte_At;

   function Nonce_Byte_At
     (Nonce : Secret_Nonce;
      Index : Message_Index) return Byte is
      Nonce_Position : constant Nonce_Index :=
        Nonce_Index (((Index - 1) mod Nonce_Length) + 1);
   begin
      return To_Byte (Nonce.Data (Nonce_Position));
   end Nonce_Byte_At;

   function Compute_Tag
     (Ciphertext     : Secret_Message;
      Payload_Length : Message_Length;
      Key            : Secret_Message;
      Nonce          : Secret_Nonce) return Byte is
      Accumulator : Byte := Byte (Payload_Length mod 256);
   begin
      if Payload_Length > 0 then
         for I in Message_Index range 1 .. Message_Index (Payload_Length) loop
            Accumulator := Accumulator xor To_Byte (Ciphertext.Data (I));
         end loop;
      end if;

      if Key.Length > 0 then
         for I in Message_Index range 1 .. Message_Index (Key.Length) loop
            Accumulator := Accumulator xor To_Byte (Key.Data (I));
         end loop;
      end if;

      Accumulator := Accumulator xor To_Byte (Nonce.Data (1));
      return Accumulator;
   end Compute_Tag;

   function Select_Runtime_Adapter
     (Production_Backend_Available : Boolean;
      Mode                         : Runtime_Mode := Runtime_Mode_Production)
      return Runtime_Adapter is
   begin
      if Mode = Runtime_Mode_Test then
         return (Backend                 => Deterministic_Backend,
                 Available               => True,
                 Deterministic_Test_Mode => True);
      end if;

      return (Backend                 => Libsodium_Backend,
              Available               => Production_Backend_Available,
              Deterministic_Test_Mode => False);
   end Select_Runtime_Adapter;

   function Adapter_Ready (Adapter : Runtime_Adapter) return Boolean is
   begin
      return
        (if Adapter.Backend = Deterministic_Backend then
            Adapter.Available and then Adapter.Deterministic_Test_Mode
         else
            Adapter.Available and then not Adapter.Deterministic_Test_Mode);
   end Adapter_Ready;

   function Constant_Time_Decision
     (Left, Right : Secret_Message) return Comparison_Decision is
      Accumulator : Byte :=
        Byte (Left.Length mod 256) xor Byte (Right.Length mod 256);
   begin
      for I in Message_Index loop
         Accumulator :=
           Accumulator
           xor (Message_Byte_At (Left, I) xor Message_Byte_At (Right, I));
      end loop;

      if Accumulator = 0 then
         return Compare_Match;
      end if;
      return Compare_Mismatch;
   end Constant_Time_Decision;

   function Constant_Time_Equals
     (Left, Right : Secret_Message) return Boolean is
   begin
      return Constant_Time_Decision (Left => Left, Right => Right) = Compare_Match;
   end Constant_Time_Equals;

   function Deterministic_Nonce (Seed : Natural) return Secret_Nonce is
      Result : Secret_Nonce := Null_Nonce;
      Rolling : Byte := Byte (Seed mod 256);
   begin
      Result.Is_Set := True;
      for I in Nonce_Index loop
         Rolling := Rolling xor Byte (Integer (I) mod 256) xor 16#5A#;
         Result.Data (I) := To_Character (Rolling);
      end loop;
      return Result;
   end Deterministic_Nonce;

   function To_Secret_Message (Value : String) return Secret_Message is
      Result : Secret_Message := Null_Message;
   begin
      if Value'Length > Max_Message_Length then
         return Result;
      end if;

      Result.Length := Value'Length;
      if Value'Length > 0 then
         for I in Message_Index range 1 .. Message_Index (Value'Length) loop
            Result.Data (I) := Value (Value'First + Integer (I) - 1);
         end loop;
      end if;

      return Result;
   end To_Secret_Message;

   function To_String (Value : Secret_Message) return String is
   begin
      if Value.Length = 0 then
         return "";
      end if;

      declare
         Result : String (1 .. Integer (Value.Length));
      begin
         for I in Result'Range loop
            Result (I) := Value.Data (Message_Index (I));
         end loop;
         return Result;
      end;
   end To_String;

   function Encrypt_AEAD_Core
     (Key       : Secret_Message;
      Plaintext : Secret_Message;
      Nonce     : Secret_Nonce) return Encryption_Result is
      Result : Encryption_Result :=
        (Success    => False,
         Status     => Runtime_Deny_Adapter_Unavailable,
         Ciphertext => Null_Message,
         Nonce      => Null_Nonce);
      Payload_Length : Message_Length;
      Tag            : Byte;
   begin
      Payload_Length := Plaintext.Length;
      for I in Message_Index range 1 .. Message_Index (Payload_Length) loop
         declare
            Mixed : constant Byte :=
              To_Byte (Plaintext.Data (I))
              xor Key_Byte_At (Key, I)
              xor Nonce_Byte_At (Nonce, I);
         begin
            Result.Ciphertext.Data (I) := To_Character (Mixed);
         end;
      end loop;

      Result.Ciphertext.Length := Payload_Length + 1;
      Tag :=
        Compute_Tag
          (Ciphertext     => Result.Ciphertext,
           Payload_Length => Payload_Length,
           Key            => Key,
           Nonce          => Nonce);
      Result.Ciphertext.Data (Message_Index (Result.Ciphertext.Length)) :=
        To_Character (Tag);
      Result.Nonce := Nonce;
      Result.Success := True;
      Result.Status := Runtime_Success;
      return Result;
   end Encrypt_AEAD_Core;

   function Decrypt_AEAD_Core
     (Key        : Secret_Message;
      Ciphertext : Secret_Message;
      Nonce      : Secret_Nonce) return Decryption_Result is
      Result : Decryption_Result :=
        (Success   => False,
         Status    => Runtime_Deny_Authentication_Failed,
         Plaintext => Null_Message);
      Payload_Length : Message_Length;
      Observed_Tag   : Secret_Message := Null_Message;
      Expected_Tag   : Secret_Message := Null_Message;
      Tag            : Byte;
   begin
      Payload_Length := Ciphertext.Length - 1;
      for I in Message_Index range 1 .. Message_Index (Payload_Length) loop
         declare
            Mixed : constant Byte :=
              To_Byte (Ciphertext.Data (I))
              xor Key_Byte_At (Key, I)
              xor Nonce_Byte_At (Nonce, I);
         begin
            Result.Plaintext.Data (I) := To_Character (Mixed);
         end;
      end loop;
      Result.Plaintext.Length := Payload_Length;

      Tag :=
        Compute_Tag
          (Ciphertext     => Ciphertext,
           Payload_Length => Payload_Length,
           Key            => Key,
           Nonce          => Nonce);
      Observed_Tag.Length := 1;
      Observed_Tag.Data (1) :=
        Ciphertext.Data (Message_Index (Ciphertext.Length));
      Expected_Tag.Length := 1;
      Expected_Tag.Data (1) := To_Character (Tag);

      if Constant_Time_Decision (Observed_Tag, Expected_Tag) /= Compare_Match then
         Result.Plaintext := Null_Message;
         Result.Status := Runtime_Deny_Authentication_Failed;
         return Result;
      end if;

      Result.Success := True;
      Result.Status := Runtime_Success;
      return Result;
   end Decrypt_AEAD_Core;

   function Encrypt
     (Config    : Secret_Config;
      Adapter   : Runtime_Adapter;
      Key       : Secret_Message;
      Plaintext : Secret_Message;
      Nonce     : Secret_Nonce) return Encryption_Result is
      Result : Encryption_Result :=
        (Success    => False,
         Status     => Runtime_Deny_Adapter_Unavailable,
         Ciphertext => Null_Message,
         Nonce      => Null_Nonce);
   begin
      if not Config_Valid (Config) then
         Result.Status := Runtime_Deny_Storage_Not_Encrypted;
         return Result;
      elsif not Adapter_Ready (Adapter) then
         return Result;
      elsif Key.Length = 0 then
         Result.Status := Runtime_Deny_Missing_Key_Material;
         return Result;
      elsif not Nonce.Is_Set then
         Result.Status := Runtime_Deny_Missing_Nonce;
         return Result;
      elsif Plaintext.Length = 0 then
         Result.Status := Runtime_Deny_Empty_Plaintext;
         return Result;
      elsif Plaintext.Length = Max_Message_Length then
         Result.Status := Runtime_Deny_Plaintext_Too_Long;
         return Result;
      end if;

      case Adapter.Backend is
         when Libsodium_Backend =>
            return Encrypt_AEAD_Core
              (Key       => Key,
               Plaintext => Plaintext,
               Nonce     => Nonce);
         when Deterministic_Backend =>
            return Encrypt_AEAD_Core
              (Key       => Key,
               Plaintext => Plaintext,
               Nonce     => Nonce);
      end case;
   end Encrypt;

   function Decrypt
     (Config     : Secret_Config;
      Adapter    : Runtime_Adapter;
      Key        : Secret_Message;
      Ciphertext : Secret_Message;
      Nonce      : Secret_Nonce) return Decryption_Result is
      Result : Decryption_Result :=
        (Success   => False,
         Status    => Runtime_Deny_Adapter_Unavailable,
         Plaintext => Null_Message);
   begin
      if not Config_Valid (Config) then
         Result.Status := Runtime_Deny_Storage_Not_Encrypted;
         return Result;
      elsif not Adapter_Ready (Adapter) then
         return Result;
      elsif Key.Length = 0 then
         Result.Status := Runtime_Deny_Missing_Key_Material;
         return Result;
      elsif not Nonce.Is_Set then
         Result.Status := Runtime_Deny_Missing_Nonce;
         return Result;
      elsif Ciphertext.Length = 0 then
         Result.Status := Runtime_Deny_Empty_Ciphertext;
         return Result;
      elsif Ciphertext.Length = 1 then
         Result.Status := Runtime_Deny_Ciphertext_Truncated;
         return Result;
      end if;

      case Adapter.Backend is
         when Libsodium_Backend =>
            return Decrypt_AEAD_Core
              (Key        => Key,
               Ciphertext => Ciphertext,
               Nonce      => Nonce);
         when Deterministic_Backend =>
            return Decrypt_AEAD_Core
              (Key        => Key,
               Ciphertext => Ciphertext,
               Nonce      => Nonce);
      end case;
   end Decrypt;

   function Rotation_Decision_Status
     (Decision : Rotation_Decision) return Runtime_Status is
   begin
      case Decision is
         when Rotation_Deny_Sealed_Key_Unavailable =>
            return Runtime_Deny_Sealed_Key_Unavailable;
         when Rotation_Deny_Reencrypt_Required =>
            return Runtime_Deny_Reencrypt_Required;
         when others =>
            return Runtime_Deny_Invalid_Key_Rotation;
      end case;
   end Rotation_Decision_Status;

   function Reencrypt_For_Rotation
     (Config              : Secret_Config;
      State               : Secret_State;
      Adapter             : Runtime_Adapter;
      Source_Key          : Secret_Message;
      Target_Key          : Secret_Message;
      Ciphertext          : Secret_Message;
      Nonce               : Secret_Nonce;
      Target_Key_Version  : Key_Version;
      Reencrypt_Requested : Boolean) return Reencrypt_Result is
      Decision : constant Rotation_Decision :=
        Rotation_Policy_Decision
          (Config              => Config,
           State               => State,
           Target_Key_Version  => Target_Key_Version,
           Reencrypt_Requested => Reencrypt_Requested);
      Decrypt_Outcome : Decryption_Result;
      Encrypt_Outcome : Encryption_Result;
      Result : Reencrypt_Result :=
        (Success    => False,
         Status     => Runtime_Deny_Invalid_Key_Rotation,
         Ciphertext => Null_Message,
         Nonce      => Null_Nonce);
   begin
      if Decision = Rotation_Allow_Noop then
         return
           (Success    => True,
            Status     => Runtime_Success,
            Ciphertext => Ciphertext,
            Nonce      => Nonce);
      elsif Decision /= Rotation_Allow_Reencrypt then
         Result.Status := Rotation_Decision_Status (Decision);
         return Result;
      end if;

      Decrypt_Outcome :=
        Decrypt
          (Config     => Config,
           Adapter    => Adapter,
           Key        => Source_Key,
           Ciphertext => Ciphertext,
           Nonce      => Nonce);
      if not Decrypt_Outcome.Success then
         Result.Status := Decrypt_Outcome.Status;
         return Result;
      end if;

      Encrypt_Outcome :=
        Encrypt
          (Config    => Config,
           Adapter   => Adapter,
           Key       => Target_Key,
           Plaintext => Decrypt_Outcome.Plaintext,
           Nonce     => Nonce);
      if not Encrypt_Outcome.Success then
         Result.Status := Encrypt_Outcome.Status;
         return Result;
      end if;

      return
        (Success    => True,
         Status     => Runtime_Success,
         Ciphertext => Encrypt_Outcome.Ciphertext,
         Nonce      => Encrypt_Outcome.Nonce);
   end Reencrypt_For_Rotation;

   function As_Secret_Result (Status : Runtime_Status) return Secret_Result is
   begin
      case Status is
         when Runtime_Success =>
            return (Success => True, Error => No_Error);
         when Runtime_Deny_Storage_Not_Encrypted =>
            return (Success => False, Error => Storage_Not_Encrypted);
         when Runtime_Deny_Adapter_Unavailable =>
            return (Success => False, Error => Crypto_Runtime_Unavailable);
         when Runtime_Deny_Missing_Key_Material =>
            return (Success => False, Error => Missing_Key_Material);
         when Runtime_Deny_Missing_Nonce =>
            return (Success => False, Error => Missing_Nonce);
         when Runtime_Deny_Empty_Plaintext | Runtime_Deny_Plaintext_Too_Long |
              Runtime_Deny_Empty_Ciphertext =>
            return (Success => False, Error => Invalid_Secret_Payload);
          when Runtime_Deny_Ciphertext_Truncated =>
             return (Success => False, Error => Ciphertext_Truncated);
          when Runtime_Deny_Authentication_Failed =>
             return (Success => False, Error => Authentication_Failed);
         when Runtime_Deny_Invalid_Key_Rotation =>
            return (Success => False, Error => Rotation_Denied);
         when Runtime_Deny_Sealed_Key_Unavailable =>
            return (Success => False, Error => Sealed_Key_Unavailable);
         when Runtime_Deny_Reencrypt_Required =>
            return (Success => False, Error => Reencryption_Required);
      end case;
   end As_Secret_Result;
end Security.Secrets.Crypto;
