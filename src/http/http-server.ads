--  HTTP gateway server using AWS (Ada Web Server).
--  Endpoints:
--    GET  /health          -- returns 200 OK with JSON status
--    POST /pair            -- pairing handshake (delegates to gateway-auth)
--    POST /webhook/telegram -- receives Telegram webhook updates
--    POST /webhook/signal  -- receives signal-cli push notifications
--    POST /webhook/whatsapp -- receives WA-Bridge push notifications

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Config.Schema;
with Memory.SQLite;

package HTTP.Server is

   --  Start the HTTP server on the configured bind host/port.
   --  Blocks until the server is stopped.
   procedure Run
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle);

   --  Stop the server gracefully.
   procedure Stop;

end HTTP.Server;
