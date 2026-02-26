package Security.Defaults with SPARK_Mode is
   Gateway_Bind_Host : constant String := "127.0.0.1";
   Allow_Public_Bind_Default : constant Boolean := False;
   Require_Pairing_Default : constant Boolean := True;
   Workspace_Only_Default : constant Boolean := True;
   Observability_Backend_Default : constant String := "none";
end Security.Defaults;
