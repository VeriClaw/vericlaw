package Runtime.Memory with SPARK_Mode is
   type Backend_Kind is
     (SQLite_Backend,
      Markdown_Backend,
      Qdrant_Backend);

   type Backend_Config is record
      Default_Backend  : Backend_Kind := SQLite_Backend;
      Markdown_Enabled : Boolean := False;
      Qdrant_Enabled   : Boolean := False;
   end record;

   type Backend_Config_Decision is
     (Backend_Config_Allow,
      Backend_Config_Deny_Default_Not_SQLite);

   function Backend_Policy_Decision
     (Config : Backend_Config) return Backend_Config_Decision
   with
     Post =>
       (if Config.Default_Backend /= SQLite_Backend then
           Backend_Policy_Decision'Result =
             Backend_Config_Deny_Default_Not_SQLite
        else
           Backend_Policy_Decision'Result = Backend_Config_Allow);

   function Backend_Config_Valid (Config : Backend_Config) return Boolean
   with
     Post =>
       Backend_Config_Valid'Result =
         (Backend_Policy_Decision (Config) = Backend_Config_Allow);

   type Backend_Selection_Decision is
     (Backend_Allow_SQLite_Default,
      Backend_Allow_Markdown_Explicit,
      Backend_Allow_Qdrant_Explicit,
      Backend_Deny_Default_Not_SQLite,
      Backend_Deny_Markdown_Disabled,
      Backend_Deny_Qdrant_Disabled);

   function Select_Backend_Decision
     (Config            : Backend_Config;
      Requested_Backend : Backend_Kind) return Backend_Selection_Decision
   with
     Post =>
       (if not Backend_Config_Valid (Config) then
           Select_Backend_Decision'Result = Backend_Deny_Default_Not_SQLite
        elsif Requested_Backend = SQLite_Backend then
           Select_Backend_Decision'Result = Backend_Allow_SQLite_Default
        elsif Requested_Backend = Markdown_Backend then
           (if Config.Markdown_Enabled then
               Select_Backend_Decision'Result = Backend_Allow_Markdown_Explicit
            else
               Select_Backend_Decision'Result = Backend_Deny_Markdown_Disabled)
        else
           (if Config.Qdrant_Enabled then
               Select_Backend_Decision'Result = Backend_Allow_Qdrant_Explicit
            else
               Select_Backend_Decision'Result = Backend_Deny_Qdrant_Disabled));

   function Backend_Request_Allowed
     (Config            : Backend_Config;
      Requested_Backend : Backend_Kind) return Boolean
    with
      Post =>
        Backend_Request_Allowed'Result =
          (Select_Backend_Decision (Config, Requested_Backend) in
             Backend_Allow_SQLite_Default
             | Backend_Allow_Markdown_Explicit
             | Backend_Allow_Qdrant_Explicit);

   type Backend_Runtime_Availability is record
      SQLite_Available   : Boolean := True;
      Markdown_Available : Boolean := False;
      Qdrant_Available   : Boolean := False;
   end record;

   type Backend_Runtime_Decision is
     (Backend_Runtime_Allow_SQLite,
      Backend_Runtime_Allow_Markdown,
      Backend_Runtime_Allow_Qdrant,
      Backend_Runtime_Deny_Default_Not_SQLite,
      Backend_Runtime_Deny_Markdown_Disabled,
      Backend_Runtime_Deny_Qdrant_Disabled,
      Backend_Runtime_Deny_SQLite_Unavailable,
      Backend_Runtime_Deny_Markdown_Unavailable,
      Backend_Runtime_Deny_Qdrant_Unavailable);

   function Backend_Runtime_Policy_Decision
     (Config            : Backend_Config;
      Requested_Backend : Backend_Kind;
      Availability      : Backend_Runtime_Availability)
      return Backend_Runtime_Decision;

   function Backend_Runtime_Request_Allowed
     (Config            : Backend_Config;
      Requested_Backend : Backend_Kind;
      Availability      : Backend_Runtime_Availability) return Boolean
   with
     Post =>
       Backend_Runtime_Request_Allowed'Result =
         (Backend_Runtime_Policy_Decision
            (Config, Requested_Backend, Availability) in
              Backend_Runtime_Allow_SQLite
              | Backend_Runtime_Allow_Markdown
              | Backend_Runtime_Allow_Qdrant);

   Max_Retention_Entries  : constant Positive := 10_000;
   Max_Retention_Age_Days : constant Positive := 365;

   type Pruning_Mode is
     (Prune_By_Entries_First,
      Prune_By_Age_First);

   type Retention_Config is record
      Max_Entries : Positive := 1_000;
      Max_Age_Days : Positive := 30;
      Mode        : Pruning_Mode := Prune_By_Age_First;
   end record;

   type Retention_Config_Decision is
     (Retention_Config_Allow,
      Retention_Config_Deny_Max_Entries,
      Retention_Config_Deny_Max_Age);

   function Retention_Policy_Decision
     (Config : Retention_Config) return Retention_Config_Decision
   with
     Post =>
       (if Config.Max_Entries > Max_Retention_Entries then
           Retention_Policy_Decision'Result =
             Retention_Config_Deny_Max_Entries
        elsif Config.Max_Age_Days > Max_Retention_Age_Days then
           Retention_Policy_Decision'Result = Retention_Config_Deny_Max_Age
        else
           Retention_Policy_Decision'Result = Retention_Config_Allow);

   function Retention_Config_Valid (Config : Retention_Config) return Boolean
   with
     Post =>
       Retention_Config_Valid'Result =
         (Retention_Policy_Decision (Config) = Retention_Config_Allow);

   type Retention_Decision is
     (Retention_No_Prune,
      Retention_Prune_Entries,
      Retention_Prune_Age,
      Retention_Prune_Entries_Then_Age,
      Retention_Prune_Age_Then_Entries,
      Retention_Deny_Insecure_Config);

   function Retention_Governance_Decision
     (Config          : Retention_Config;
      Current_Entries : Natural;
      Oldest_Age_Days : Natural) return Retention_Decision
   with
     Post =>
       (if not Retention_Config_Valid (Config) then
           Retention_Governance_Decision'Result =
             Retention_Deny_Insecure_Config
        elsif Current_Entries > Config.Max_Entries
          and then Oldest_Age_Days > Config.Max_Age_Days
        then
           (if Config.Mode = Prune_By_Entries_First then
               Retention_Governance_Decision'Result =
                 Retention_Prune_Entries_Then_Age
            else
               Retention_Governance_Decision'Result =
                 Retention_Prune_Age_Then_Entries)
        elsif Current_Entries > Config.Max_Entries then
           Retention_Governance_Decision'Result = Retention_Prune_Entries
         elsif Oldest_Age_Days > Config.Max_Age_Days then
            Retention_Governance_Decision'Result = Retention_Prune_Age
         else
            Retention_Governance_Decision'Result = Retention_No_Prune);

   type Memory_Runtime_Decision is
     (Memory_Runtime_Allow_No_Prune,
      Memory_Runtime_Allow_Prune_Entries,
      Memory_Runtime_Allow_Prune_Age,
      Memory_Runtime_Allow_Prune_Entries_Then_Age,
      Memory_Runtime_Allow_Prune_Age_Then_Entries,
      Memory_Runtime_Deny_Backend,
      Memory_Runtime_Deny_Insecure_Retention);

   function Memory_Runtime_Policy_Decision
     (Backend           : Backend_Config;
      Requested_Backend : Backend_Kind;
      Availability      : Backend_Runtime_Availability;
      Retention         : Retention_Config;
      Current_Entries   : Natural;
      Oldest_Age_Days   : Natural) return Memory_Runtime_Decision;

   function Memory_Runtime_Allowed
     (Backend           : Backend_Config;
      Requested_Backend : Backend_Kind;
      Availability      : Backend_Runtime_Availability;
      Retention         : Retention_Config;
      Current_Entries   : Natural;
      Oldest_Age_Days   : Natural) return Boolean
   with
     Post =>
       Memory_Runtime_Allowed'Result =
         (Memory_Runtime_Policy_Decision
            (Backend           => Backend,
             Requested_Backend => Requested_Backend,
             Availability      => Availability,
             Retention         => Retention,
             Current_Entries   => Current_Entries,
             Oldest_Age_Days   => Oldest_Age_Days) in
               Memory_Runtime_Allow_No_Prune
               | Memory_Runtime_Allow_Prune_Entries
               | Memory_Runtime_Allow_Prune_Age
               | Memory_Runtime_Allow_Prune_Entries_Then_Age
               | Memory_Runtime_Allow_Prune_Age_Then_Entries);
end Runtime.Memory;
