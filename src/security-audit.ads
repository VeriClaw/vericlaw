package Security.Audit with SPARK_Mode is
   type Event_Kind is
     (Event_Auth_Request,
      Event_Auth_Denied,
      Event_Secret_Ingest,
      Event_Secret_Store,
      Event_Secret_Injection_Denied);

   type Redacted_Payload is record
      Subject_Set              : Boolean := False;
      Classification_Set       : Boolean := False;
      Redaction_Metadata_Valid : Boolean := False;
      Includes_Secret_Material : Boolean := False;
      Includes_Token_Material  : Boolean := False;
   end record;

   function Redaction_Metadata_Valid
     (Payload : Redacted_Payload) return Boolean
   with
     Post =>
       Redaction_Metadata_Valid'Result =
         (Payload.Subject_Set
          and then Payload.Classification_Set
          and then Payload.Redaction_Metadata_Valid);

   function Payload_Is_Redacted (Payload : Redacted_Payload) return Boolean
   with
     Post =>
       Payload_Is_Redacted'Result =
         (Redaction_Metadata_Valid (Payload)
          and then not Payload.Includes_Secret_Material
          and then not Payload.Includes_Token_Material);

   type Append_Decision is
     (Append_Allow,
      Append_Deny_Invalid_Redaction_Metadata,
      Append_Deny_Unredacted_Secret_Material,
      Append_Deny_Unredacted_Token_Material);

   function Append_Policy_Decision
     (Kind    : Event_Kind;
      Payload : Redacted_Payload) return Append_Decision
   with
     Post =>
       (if not Redaction_Metadata_Valid (Payload) then
           Append_Policy_Decision'Result =
             Append_Deny_Invalid_Redaction_Metadata
        elsif Payload.Includes_Secret_Material then
           Append_Policy_Decision'Result =
             Append_Deny_Unredacted_Secret_Material
        elsif Payload.Includes_Token_Material then
           Append_Policy_Decision'Result =
             Append_Deny_Unredacted_Token_Material
        else
           Append_Policy_Decision'Result = Append_Allow);

   function Append_Allowed
     (Kind    : Event_Kind;
      Payload : Redacted_Payload) return Boolean
   with
     Post =>
       Append_Allowed'Result =
         (Append_Policy_Decision (Kind => Kind, Payload => Payload) =
            Append_Allow);

   type Retention_Decision is
     (Retention_Keep,
      Retention_Drop_Oldest_Max_Entries,
      Retention_Drop_Oldest_Max_Age,
      Retention_Drop_Oldest_Max_Entries_And_Age,
      Retention_Deny_Invalid_Limits);

   function Retention_Policy_Decision
     (Current_Entries    : Natural;
      Max_Entries        : Natural;
      Oldest_Age_Seconds : Natural;
      Max_Age_Seconds    : Natural) return Retention_Decision
   with
     Post =>
       (if Max_Entries = 0 or else Max_Age_Seconds = 0 then
           Retention_Policy_Decision'Result = Retention_Deny_Invalid_Limits
        elsif Current_Entries >= Max_Entries
          and then Current_Entries > 0
          and then Oldest_Age_Seconds > Max_Age_Seconds
        then
           Retention_Policy_Decision'Result =
             Retention_Drop_Oldest_Max_Entries_And_Age
        elsif Current_Entries >= Max_Entries then
           Retention_Policy_Decision'Result =
             Retention_Drop_Oldest_Max_Entries
        elsif Current_Entries > 0
          and then Oldest_Age_Seconds > Max_Age_Seconds
        then
           Retention_Policy_Decision'Result = Retention_Drop_Oldest_Max_Age
        else
           Retention_Policy_Decision'Result = Retention_Keep);

   function Retention_Allows_Append
     (Current_Entries    : Natural;
      Max_Entries        : Natural;
      Oldest_Age_Seconds : Natural;
      Max_Age_Seconds    : Natural) return Boolean
   with
     Post =>
       Retention_Allows_Append'Result =
         (Retention_Policy_Decision
            (Current_Entries    => Current_Entries,
             Max_Entries        => Max_Entries,
             Oldest_Age_Seconds => Oldest_Age_Seconds,
             Max_Age_Seconds    => Max_Age_Seconds) /=
            Retention_Deny_Invalid_Limits);
end Security.Audit;
