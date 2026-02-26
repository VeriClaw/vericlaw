with Runtime.Memory;

procedure Memory_Backend_Suite_Policy is
   use Runtime.Memory;

   Default_Backend_Config : constant Backend_Config := (others => <>);
   Markdown_Enabled_Config : constant Backend_Config :=
     (Default_Backend  => SQLite_Backend,
      Markdown_Enabled => True,
      Qdrant_Enabled   => False);
   Qdrant_Enabled_Config : constant Backend_Config :=
     (Default_Backend  => SQLite_Backend,
      Markdown_Enabled => False,
      Qdrant_Enabled   => True);
   Invalid_Default_Config : constant Backend_Config :=
     (Default_Backend  => Markdown_Backend,
      Markdown_Enabled => True,
      Qdrant_Enabled   => False);
   Default_Backend_Runtime : constant Backend_Runtime_Availability :=
     (others => <>);
   SQLite_Unavailable_Runtime : constant Backend_Runtime_Availability :=
     (SQLite_Available   => False,
      Markdown_Available => False,
      Qdrant_Available   => False);
   Markdown_Runtime_Ready : constant Backend_Runtime_Availability :=
     (SQLite_Available   => True,
      Markdown_Available => True,
      Qdrant_Available   => False);
   Qdrant_Runtime_Ready : constant Backend_Runtime_Availability :=
     (SQLite_Available   => True,
      Markdown_Available => False,
      Qdrant_Available   => True);

   Default_Retention : constant Retention_Config := (others => <>);
   Entries_First_Retention : constant Retention_Config :=
     (Max_Entries => 1_000, Max_Age_Days => 30, Mode => Prune_By_Entries_First);
   Invalid_Entries_Retention : constant Retention_Config :=
     (Max_Entries => Max_Retention_Entries + 1,
      Max_Age_Days => 30,
      Mode => Prune_By_Age_First);
   Invalid_Age_Retention : constant Retention_Config :=
     (Max_Entries => 1_000,
      Max_Age_Days => Max_Retention_Age_Days + 1,
      Mode => Prune_By_Age_First);
begin
   pragma Assert (Backend_Config_Valid (Default_Backend_Config));
   pragma Assert
     (Backend_Policy_Decision (Invalid_Default_Config) =
        Backend_Config_Deny_Default_Not_SQLite);
   pragma Assert
     (Select_Backend_Decision (Default_Backend_Config, SQLite_Backend) =
        Backend_Allow_SQLite_Default);
   pragma Assert
     (Select_Backend_Decision (Default_Backend_Config, Markdown_Backend) =
        Backend_Deny_Markdown_Disabled);
   pragma Assert
     (Select_Backend_Decision (Default_Backend_Config, Qdrant_Backend) =
        Backend_Deny_Qdrant_Disabled);
   pragma Assert
     (Select_Backend_Decision (Markdown_Enabled_Config, Markdown_Backend) =
        Backend_Allow_Markdown_Explicit);
   pragma Assert
     (Select_Backend_Decision (Qdrant_Enabled_Config, Qdrant_Backend) =
        Backend_Allow_Qdrant_Explicit);
   pragma Assert
      (Select_Backend_Decision (Invalid_Default_Config, SQLite_Backend) =
         Backend_Deny_Default_Not_SQLite);
   pragma Assert
      (not Backend_Request_Allowed (Default_Backend_Config, Markdown_Backend));
   pragma Assert
     (Backend_Runtime_Policy_Decision
        (Config            => Default_Backend_Config,
         Requested_Backend => SQLite_Backend,
         Availability      => Default_Backend_Runtime) =
           Backend_Runtime_Allow_SQLite);
   pragma Assert
     (Backend_Runtime_Policy_Decision
        (Config            => Default_Backend_Config,
         Requested_Backend => SQLite_Backend,
         Availability      => SQLite_Unavailable_Runtime) =
           Backend_Runtime_Deny_SQLite_Unavailable);
   pragma Assert
     (Backend_Runtime_Policy_Decision
        (Config            => Markdown_Enabled_Config,
         Requested_Backend => Markdown_Backend,
         Availability      => Default_Backend_Runtime) =
           Backend_Runtime_Deny_Markdown_Unavailable);
   pragma Assert
     (Backend_Runtime_Policy_Decision
        (Config            => Markdown_Enabled_Config,
         Requested_Backend => Markdown_Backend,
         Availability      => Markdown_Runtime_Ready) =
           Backend_Runtime_Allow_Markdown);
   pragma Assert
     (Backend_Runtime_Policy_Decision
        (Config            => Qdrant_Enabled_Config,
         Requested_Backend => Qdrant_Backend,
         Availability      => Default_Backend_Runtime) =
           Backend_Runtime_Deny_Qdrant_Unavailable);
   pragma Assert
     (Backend_Runtime_Policy_Decision
        (Config            => Qdrant_Enabled_Config,
         Requested_Backend => Qdrant_Backend,
         Availability      => Qdrant_Runtime_Ready) =
           Backend_Runtime_Allow_Qdrant);
   pragma Assert
     (not Backend_Runtime_Request_Allowed
        (Config            => Qdrant_Enabled_Config,
         Requested_Backend => Qdrant_Backend,
         Availability      => Default_Backend_Runtime));

   pragma Assert (Retention_Config_Valid (Default_Retention));
   pragma Assert
     (Retention_Policy_Decision (Invalid_Entries_Retention) =
        Retention_Config_Deny_Max_Entries);
   pragma Assert
     (Retention_Policy_Decision (Invalid_Age_Retention) =
        Retention_Config_Deny_Max_Age);
   pragma Assert
     (Retention_Governance_Decision
        (Config          => Default_Retention,
         Current_Entries => 900,
         Oldest_Age_Days => 29) = Retention_No_Prune);
   pragma Assert
     (Retention_Governance_Decision
        (Config          => Default_Retention,
         Current_Entries => 1_001,
         Oldest_Age_Days => 29) = Retention_Prune_Entries);
   pragma Assert
     (Retention_Governance_Decision
        (Config          => Default_Retention,
         Current_Entries => 900,
         Oldest_Age_Days => 31) = Retention_Prune_Age);
   pragma Assert
     (Retention_Governance_Decision
        (Config          => Default_Retention,
         Current_Entries => 1_001,
         Oldest_Age_Days => 31) = Retention_Prune_Age_Then_Entries);
   pragma Assert
     (Retention_Governance_Decision
        (Config          => Entries_First_Retention,
         Current_Entries => 1_001,
         Oldest_Age_Days => 31) = Retention_Prune_Entries_Then_Age);
   pragma Assert
      (Retention_Governance_Decision
         (Config          => Invalid_Entries_Retention,
          Current_Entries => 1,
          Oldest_Age_Days => 1) = Retention_Deny_Insecure_Config);
   pragma Assert
     (Memory_Runtime_Policy_Decision
        (Backend           => Default_Backend_Config,
         Requested_Backend => SQLite_Backend,
         Availability      => Default_Backend_Runtime,
         Retention         => Default_Retention,
         Current_Entries   => 900,
         Oldest_Age_Days   => 29) = Memory_Runtime_Allow_No_Prune);
   pragma Assert
     (Memory_Runtime_Policy_Decision
        (Backend           => Default_Backend_Config,
         Requested_Backend => SQLite_Backend,
         Availability      => Default_Backend_Runtime,
         Retention         => Default_Retention,
         Current_Entries   => 1_001,
         Oldest_Age_Days   => 29) = Memory_Runtime_Allow_Prune_Entries);
   pragma Assert
     (Memory_Runtime_Policy_Decision
        (Backend           => Markdown_Enabled_Config,
         Requested_Backend => Markdown_Backend,
         Availability      => Default_Backend_Runtime,
         Retention         => Default_Retention,
         Current_Entries   => 1,
         Oldest_Age_Days   => 1) = Memory_Runtime_Deny_Backend);
   pragma Assert
     (Memory_Runtime_Policy_Decision
        (Backend           => Default_Backend_Config,
         Requested_Backend => SQLite_Backend,
         Availability      => Default_Backend_Runtime,
         Retention         => Invalid_Entries_Retention,
         Current_Entries   => 1,
         Oldest_Age_Days   => 1) = Memory_Runtime_Deny_Insecure_Retention);
   pragma Assert
     (Memory_Runtime_Allowed
        (Backend           => Default_Backend_Config,
         Requested_Backend => SQLite_Backend,
         Availability      => Default_Backend_Runtime,
         Retention         => Default_Retention,
         Current_Entries   => 900,
         Oldest_Age_Days   => 29));
   pragma Assert
     (not Memory_Runtime_Allowed
        (Backend           => Default_Backend_Config,
         Requested_Backend => SQLite_Backend,
         Availability      => SQLite_Unavailable_Runtime,
         Retention         => Default_Retention,
         Current_Entries   => 900,
         Oldest_Age_Days   => 29));
end Memory_Backend_Suite_Policy;
