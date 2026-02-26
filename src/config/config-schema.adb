package body Config.Schema is

   function Default_Config return Agent_Config is
      C : Agent_Config;
   begin
      Set_Unbounded_String (C.Agent_Name,    "Quasar");
      Set_Unbounded_String (C.System_Prompt,
        "You are Quasar, a helpful AI assistant. You are security-conscious, "
        & "accurate, and concise. When using tools, always explain what you "
        & "are doing and why.");

      --  Default gateway binds loopback only (matches security SLOs).
      Set_Unbounded_String (C.Gateway.Bind_Host, "127.0.0.1");
      C.Gateway.Bind_Port := 8787;

      --  Memory defaults.
      C.Memory.Max_History := 50;
      C.Memory.Facts_Enabled := True;

      return C;
   end Default_Config;

end Config.Schema;
