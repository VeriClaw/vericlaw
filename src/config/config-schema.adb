package body Config.Schema is

   function Default_Config return Agent_Config is
      C : Agent_Config;
   begin
      Set_Unbounded_String (C.Agent_Name,    "VeriClaw");
      Set_Unbounded_String (C.System_Prompt,
        "You are VeriClaw, a helpful AI assistant. You are security-conscious, "
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

   function Find_Channel
     (Cfg  : Agent_Config;
      Kind : Channel_Kind) return Channel_Config
   is
   begin
      for I in 1 .. Cfg.Num_Channels loop
         if Cfg.Channels (I).Kind = Kind then
            return Cfg.Channels (I);
         end if;
      end loop;
      return (Kind => Kind, others => <>);
   end Find_Channel;

end Config.Schema;
