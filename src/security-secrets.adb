with Security.Audit;

package body Security.Secrets with SPARK_Mode is
   use type Security.Audit.Append_Decision;

   function Sealed_Key_Mode_Valid (Config : Secret_Config) return Boolean is
   begin
      return
        (if Config.Require_Sealed_Key then Config.Source = OS_Key_Store
         else True);
   end Sealed_Key_Mode_Valid;

   function Key_Source_Valid (Config : Secret_Config) return Boolean is
   begin
      return
         (if Config.Source = Env_Key then Config.Env_Key_Set else not Config.Env_Key_Set);
   end Key_Source_Valid;

   function Config_Valid (Config : Secret_Config) return Boolean is
   begin
      return Config.Encrypted_At_Rest
        and then Config.Active_Key_Version > 0
        and then Key_Source_Valid (Config)
        and then Sealed_Key_Mode_Valid (Config);
   end Config_Valid;

   function Metadata_Valid (Metadata : Secret_Metadata) return Boolean is
   begin
      return Metadata.Identifier_Set
        and then Metadata.Classification_Set
        and then Metadata.Redacted_For_Audit;
   end Metadata_Valid;

   function Redact_For_Audit (Metadata : Secret_Metadata) return Secret_Metadata is
   begin
      return (Identifier_Set     => Metadata.Identifier_Set,
              Classification_Set => Metadata.Classification_Set,
              Redacted_For_Audit => True);
   end Redact_For_Audit;

   function State_Valid
     (Config : Secret_Config;
      State  : Secret_State) return Boolean is
   begin
      return State.Stored_Key_Version > 0
        and then State.Stored_Key_Version <= Config.Active_Key_Version
        and then
          (if Config.Require_Sealed_Key then State.Sealed_Key_Loaded else True);
   end State_Valid;

   function Rotation_Policy_Decision
     (Config              : Secret_Config;
      State               : Secret_State;
      Target_Key_Version  : Key_Version;
      Reencrypt_Requested : Boolean) return Rotation_Decision is
   begin
      if not Config_Valid (Config) then
         return Rotation_Deny_Invalid_Config;
      elsif not State_Valid (Config, State) then
         if Config.Require_Sealed_Key and then not State.Sealed_Key_Loaded then
            return Rotation_Deny_Sealed_Key_Unavailable;
         end if;
         return Rotation_Deny_Invalid_State;
      elsif Target_Key_Version < Config.Active_Key_Version then
         return Rotation_Deny_Version_Downgrade;
      elsif Target_Key_Version > Config.Active_Key_Version then
         return Rotation_Deny_Target_Not_Active;
      elsif State.Stored_Key_Version = Target_Key_Version then
         return Rotation_Allow_Noop;
      elsif not Reencrypt_Requested then
         return Rotation_Deny_Reencrypt_Required;
      end if;

      return Rotation_Allow_Reencrypt;
   end Rotation_Policy_Decision;

   function Rotation_Allowed
     (Config              : Secret_Config;
      State               : Secret_State;
      Target_Key_Version  : Key_Version;
      Reencrypt_Requested : Boolean) return Boolean is
      Decision : constant Rotation_Decision :=
        Rotation_Policy_Decision
          (Config              => Config,
           State               => State,
           Target_Key_Version  => Target_Key_Version,
           Reencrypt_Requested => Reencrypt_Requested);
   begin
      return Decision in Rotation_Allow_Noop | Rotation_Allow_Reencrypt;
   end Rotation_Allowed;

   function Ingest
      (Config           : Secret_Config;
       Metadata         : Secret_Metadata;
       Source_Available : Boolean;
       Key_Material_Set : Boolean) return Secret_Result is
      Audit_Payload : constant Security.Audit.Redacted_Payload :=
        (Subject_Set              => Metadata.Identifier_Set,
         Classification_Set       => Metadata.Classification_Set,
         Redaction_Metadata_Valid => Metadata.Redacted_For_Audit,
         Includes_Secret_Material => False,
         Includes_Token_Material  => False);
      Audit_Decision : constant Security.Audit.Append_Decision :=
        Security.Audit.Append_Policy_Decision
          (Kind    => Security.Audit.Event_Secret_Ingest,
           Payload => Audit_Payload);
   begin
      if not Config.Encrypted_At_Rest then
         return (Success => False, Error => Storage_Not_Encrypted);
      elsif not Key_Source_Valid (Config) then
         return (Success => False, Error => Key_Source_Constraint_Violation);
      elsif Audit_Decision /= Security.Audit.Append_Allow then
         return (Success => False, Error => Invalid_Metadata);
      elsif not Metadata_Valid (Metadata) then
         return (Success => False, Error => Invalid_Metadata);
      elsif not Source_Available then
         return (Success => False, Error => Key_Source_Unavailable);
      elsif not Key_Material_Set then
         return (Success => False, Error => Missing_Key_Material);
      end if;

      return (Success => True, Error => No_Error);
   end Ingest;

   function Store
     (Config            : Secret_Config;
      Ingestion         : Secret_Result;
      Storage_Available : Boolean) return Secret_Result is
   begin
      if not Ingestion.Success then
         if Ingestion.Error = No_Error then
            return (Success => False, Error => Secret_Not_Ingested);
         end if;
         return Ingestion;
      elsif not Config.Encrypted_At_Rest then
         return (Success => False, Error => Storage_Not_Encrypted);
      elsif not Key_Source_Valid (Config) then
         return (Success => False, Error => Key_Source_Constraint_Violation);
      elsif not Storage_Available then
         return (Success => False, Error => Storage_Backend_Unavailable);
      end if;

      return (Success => True, Error => No_Error);
   end Store;
end Security.Secrets;
