package body Security.Audit with SPARK_Mode is
   function Redaction_Metadata_Valid
     (Payload : Redacted_Payload) return Boolean is
   begin
      return Payload.Subject_Set
        and then Payload.Classification_Set
        and then Payload.Redaction_Metadata_Valid;
   end Redaction_Metadata_Valid;

   function Payload_Is_Redacted (Payload : Redacted_Payload) return Boolean is
   begin
      return Redaction_Metadata_Valid (Payload)
        and then not Payload.Includes_Secret_Material
        and then not Payload.Includes_Token_Material;
   end Payload_Is_Redacted;

   function Evaluate_Append_Payload
     (Payload : Redacted_Payload) return Append_Decision is
   begin
      if not Redaction_Metadata_Valid (Payload) then
         return Append_Deny_Invalid_Redaction_Metadata;
      elsif Payload.Includes_Secret_Material then
         return Append_Deny_Unredacted_Secret_Material;
      elsif Payload.Includes_Token_Material then
         return Append_Deny_Unredacted_Token_Material;
      end if;
      return Append_Allow;
   end Evaluate_Append_Payload;

   function Append_Policy_Decision
     (Kind    : Event_Kind;
      Payload : Redacted_Payload) return Append_Decision is
   begin
      case Kind is
         when Event_Auth_Request =>
            return Evaluate_Append_Payload (Payload);
         when Event_Auth_Denied =>
            return Evaluate_Append_Payload (Payload);
         when Event_Secret_Ingest =>
            return Evaluate_Append_Payload (Payload);
         when Event_Secret_Store =>
            return Evaluate_Append_Payload (Payload);
         when Event_Secret_Injection_Denied =>
            return Evaluate_Append_Payload (Payload);
      end case;
   end Append_Policy_Decision;

   function Append_Allowed
     (Kind    : Event_Kind;
      Payload : Redacted_Payload) return Boolean is
   begin
      return Append_Policy_Decision (Kind => Kind, Payload => Payload) =
        Append_Allow;
   end Append_Allowed;

   function Retention_Policy_Decision
     (Current_Entries    : Natural;
      Max_Entries        : Natural;
      Oldest_Age_Seconds : Natural;
      Max_Age_Seconds    : Natural) return Retention_Decision is
      Needs_Entry_Prune : constant Boolean := Current_Entries >= Max_Entries;
      Needs_Age_Prune : constant Boolean :=
        Current_Entries > 0 and then Oldest_Age_Seconds > Max_Age_Seconds;
   begin
      if Max_Entries = 0 or else Max_Age_Seconds = 0 then
         return Retention_Deny_Invalid_Limits;
      elsif Needs_Entry_Prune and then Needs_Age_Prune then
         return Retention_Drop_Oldest_Max_Entries_And_Age;
      elsif Needs_Entry_Prune then
         return Retention_Drop_Oldest_Max_Entries;
      elsif Needs_Age_Prune then
         return Retention_Drop_Oldest_Max_Age;
      end if;
      return Retention_Keep;
   end Retention_Policy_Decision;

   function Retention_Allows_Append
     (Current_Entries    : Natural;
      Max_Entries        : Natural;
      Oldest_Age_Seconds : Natural;
      Max_Age_Seconds    : Natural) return Boolean is
   begin
      return Retention_Policy_Decision
        (Current_Entries    => Current_Entries,
         Max_Entries        => Max_Entries,
         Oldest_Age_Seconds => Oldest_Age_Seconds,
         Max_Age_Seconds    => Max_Age_Seconds) /= Retention_Deny_Invalid_Limits;
   end Retention_Allows_Append;
end Security.Audit;
