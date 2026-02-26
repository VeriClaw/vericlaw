package body Runtime.Memory with SPARK_Mode is
   function Backend_Policy_Decision
     (Config : Backend_Config) return Backend_Config_Decision is
   begin
      if Config.Default_Backend /= SQLite_Backend then
         return Backend_Config_Deny_Default_Not_SQLite;
      end if;
      return Backend_Config_Allow;
   end Backend_Policy_Decision;

   function Backend_Config_Valid (Config : Backend_Config) return Boolean is
   begin
      return Backend_Policy_Decision (Config) = Backend_Config_Allow;
   end Backend_Config_Valid;

   function Select_Backend_Decision
     (Config            : Backend_Config;
      Requested_Backend : Backend_Kind) return Backend_Selection_Decision is
   begin
      if not Backend_Config_Valid (Config) then
         return Backend_Deny_Default_Not_SQLite;
      elsif Requested_Backend = SQLite_Backend then
         return Backend_Allow_SQLite_Default;
      elsif Requested_Backend = Markdown_Backend then
         if Config.Markdown_Enabled then
            return Backend_Allow_Markdown_Explicit;
         end if;
         return Backend_Deny_Markdown_Disabled;
      else
         if Config.Qdrant_Enabled then
            return Backend_Allow_Qdrant_Explicit;
         end if;
         return Backend_Deny_Qdrant_Disabled;
      end if;
   end Select_Backend_Decision;

   function Backend_Request_Allowed
     (Config            : Backend_Config;
      Requested_Backend : Backend_Kind) return Boolean is
   begin
      return Select_Backend_Decision (Config, Requested_Backend) in
        Backend_Allow_SQLite_Default
        | Backend_Allow_Markdown_Explicit
        | Backend_Allow_Qdrant_Explicit;
   end Backend_Request_Allowed;

   function Backend_Runtime_Policy_Decision
     (Config            : Backend_Config;
      Requested_Backend : Backend_Kind;
      Availability      : Backend_Runtime_Availability)
      return Backend_Runtime_Decision is
      Selection_Decision : constant Backend_Selection_Decision :=
        Select_Backend_Decision (Config, Requested_Backend);
   begin
      case Selection_Decision is
         when Backend_Allow_SQLite_Default =>
            if Availability.SQLite_Available then
               return Backend_Runtime_Allow_SQLite;
            end if;
            return Backend_Runtime_Deny_SQLite_Unavailable;
         when Backend_Allow_Markdown_Explicit =>
            if Availability.Markdown_Available then
               return Backend_Runtime_Allow_Markdown;
            end if;
            return Backend_Runtime_Deny_Markdown_Unavailable;
         when Backend_Allow_Qdrant_Explicit =>
            if Availability.Qdrant_Available then
               return Backend_Runtime_Allow_Qdrant;
            end if;
            return Backend_Runtime_Deny_Qdrant_Unavailable;
         when Backend_Deny_Default_Not_SQLite =>
            return Backend_Runtime_Deny_Default_Not_SQLite;
         when Backend_Deny_Markdown_Disabled =>
            return Backend_Runtime_Deny_Markdown_Disabled;
         when Backend_Deny_Qdrant_Disabled =>
            return Backend_Runtime_Deny_Qdrant_Disabled;
      end case;
   end Backend_Runtime_Policy_Decision;

   function Backend_Runtime_Request_Allowed
     (Config            : Backend_Config;
      Requested_Backend : Backend_Kind;
      Availability      : Backend_Runtime_Availability) return Boolean is
   begin
      return Backend_Runtime_Policy_Decision
        (Config, Requested_Backend, Availability) in
          Backend_Runtime_Allow_SQLite
          | Backend_Runtime_Allow_Markdown
          | Backend_Runtime_Allow_Qdrant;
   end Backend_Runtime_Request_Allowed;

   function Retention_Policy_Decision
     (Config : Retention_Config) return Retention_Config_Decision is
   begin
      if Config.Max_Entries > Max_Retention_Entries then
         return Retention_Config_Deny_Max_Entries;
      elsif Config.Max_Age_Days > Max_Retention_Age_Days then
         return Retention_Config_Deny_Max_Age;
      end if;
      return Retention_Config_Allow;
   end Retention_Policy_Decision;

   function Retention_Config_Valid (Config : Retention_Config) return Boolean is
   begin
      return Retention_Policy_Decision (Config) = Retention_Config_Allow;
   end Retention_Config_Valid;

   function Retention_Governance_Decision
     (Config          : Retention_Config;
      Current_Entries : Natural;
      Oldest_Age_Days : Natural) return Retention_Decision is
   begin
      if not Retention_Config_Valid (Config) then
         return Retention_Deny_Insecure_Config;
      elsif Current_Entries > Config.Max_Entries
        and then Oldest_Age_Days > Config.Max_Age_Days
      then
         if Config.Mode = Prune_By_Entries_First then
            return Retention_Prune_Entries_Then_Age;
         end if;
         return Retention_Prune_Age_Then_Entries;
      elsif Current_Entries > Config.Max_Entries then
         return Retention_Prune_Entries;
      elsif Oldest_Age_Days > Config.Max_Age_Days then
         return Retention_Prune_Age;
      end if;

      return Retention_No_Prune;
   end Retention_Governance_Decision;

   function Memory_Runtime_Policy_Decision
     (Backend           : Backend_Config;
      Requested_Backend : Backend_Kind;
      Availability      : Backend_Runtime_Availability;
      Retention         : Retention_Config;
      Current_Entries   : Natural;
      Oldest_Age_Days   : Natural) return Memory_Runtime_Decision is
      Backend_Decision : constant Backend_Runtime_Decision :=
        Backend_Runtime_Policy_Decision
          (Config            => Backend,
           Requested_Backend => Requested_Backend,
           Availability      => Availability);
      Retention_Result : constant Retention_Decision :=
        Retention_Governance_Decision
          (Config          => Retention,
           Current_Entries => Current_Entries,
           Oldest_Age_Days => Oldest_Age_Days);
   begin
      if Backend_Decision not in
        Backend_Runtime_Allow_SQLite
        | Backend_Runtime_Allow_Markdown
        | Backend_Runtime_Allow_Qdrant
      then
         return Memory_Runtime_Deny_Backend;
      end if;

      case Retention_Result is
         when Retention_No_Prune =>
            return Memory_Runtime_Allow_No_Prune;
         when Retention_Prune_Entries =>
            return Memory_Runtime_Allow_Prune_Entries;
         when Retention_Prune_Age =>
            return Memory_Runtime_Allow_Prune_Age;
         when Retention_Prune_Entries_Then_Age =>
            return Memory_Runtime_Allow_Prune_Entries_Then_Age;
         when Retention_Prune_Age_Then_Entries =>
            return Memory_Runtime_Allow_Prune_Age_Then_Entries;
         when Retention_Deny_Insecure_Config =>
            return Memory_Runtime_Deny_Insecure_Retention;
      end case;
   end Memory_Runtime_Policy_Decision;

   function Memory_Runtime_Allowed
     (Backend           : Backend_Config;
      Requested_Backend : Backend_Kind;
      Availability      : Backend_Runtime_Availability;
      Retention         : Retention_Config;
      Current_Entries   : Natural;
      Oldest_Age_Days   : Natural) return Boolean is
   begin
      return Memory_Runtime_Policy_Decision
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
           | Memory_Runtime_Allow_Prune_Age_Then_Entries;
   end Memory_Runtime_Allowed;
end Runtime.Memory;
