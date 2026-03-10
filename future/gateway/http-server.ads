--  HTTP gateway server using AWS (Ada Web Server).
--  Endpoints:
--    GET  /health             -- returns 200 OK with JSON status
--    POST /pair               -- pairing handshake (delegates to gateway-auth)
--    POST /webhook/telegram   -- receives Telegram webhook updates
--    POST /webhook/signal     -- receives signal-cli push notifications
--    POST /webhook/whatsapp   -- receives WA-Bridge push notifications
--    GET  /api/plugins        -- localhost-only extensibility and plugin discovery status
--    POST /api/chat           -- non-streaming chat (localhost only)
--    POST /api/chat/stream    -- SSE streaming chat (localhost only)

with Config.Schema;
with Memory.SQLite;

package HTTP.Server
  with SPARK_Mode => Off
is

   --  Start the HTTP server on the configured bind host/port.
   --  Blocks until the server is stopped.
   procedure Run
     (Cfg : Config.Schema.Agent_Config;
      Mem : aliased in out Memory.SQLite.Memory_Handle);

   --  Stop the server gracefully.
   procedure Stop;

end HTTP.Server;
