# IRC Setup Guide

Connect VeriClaw to IRC using **irc-bridge** — a Node.js sidecar that connects to any IRC server and exposes a REST API.

## How it works

```
IRC server ←──TCP/TLS──→ irc-bridge (Node.js)
                                ↕ REST polling
                           VeriClaw (Ada)
```

`irc-bridge` connects to the IRC server, joins the configured channels, queues incoming messages, and exposes a simple REST API that VeriClaw polls every 2 seconds.

---

## 1. Choose an IRC server

VeriClaw works with any IRC server. Popular public networks:

- **Libera.Chat** — `irc.libera.chat:6697` (TLS) — free, registration optional
- **OFTC** — `irc.oftc.net:6697` (TLS)
- **Self-hosted** — [Ergo](https://ergo.chat/) is easy to run with Docker

To register a nick on Libera.Chat (recommended):

```
/nick vericlaw
/msg NickServ REGISTER yourpassword your@email.com
```

After registration, set `IRC_NICK` and `IRC_PASS` in your environment.

---

## 2. Configure docker-compose

Copy the example config and fill in your values:

```bash
cp config/irc.example.json config/config.json
# Edit config.json: set api_key, allowlist
```

In your shell or a `.env` file, set:

```bash
export IRC_HOST=irc.libera.chat      # IRC server hostname
export IRC_PORT=6697                  # IRC server port (6697 = TLS)
export IRC_TLS=true                   # use TLS (recommended)
export IRC_NICK=vericlaw              # bot nick
export IRC_PASS=yourpassword          # NickServ password (optional)
export IRC_CHANNELS=#general,#help    # comma-separated channels to join
```

---

## 3. Start the stack

```bash
docker compose up irc-bridge vericlaw -d
```

Check that the bridge connected:

```bash
docker compose logs irc-bridge
# Should show: Connected to IRC
```

---

## 4. Test it

Send a message in one of the configured channels. VeriClaw will reply within a few seconds.

You can also test the bridge REST API directly:

```bash
# Check health
curl http://localhost:3005/health

# Poll for messages
curl http://localhost:3005/sessions/irc/messages

# Send a message
curl -X POST http://localhost:3005/sessions/irc/messages \
  -H 'Content-Type: application/json' \
  -d '{"target": "#general", "text": "Hello from VeriClaw!"}'
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Bridge logs `Error: connect ECONNREFUSED` | Check `IRC_HOST` and `IRC_PORT` values |
| Bot joins but never responds | Ensure the nick is in `allowlist` or set `allowlist: "*"` |
| Nick collision on connect | Change `IRC_NICK` to something unique |
| TLS handshake errors | Try `IRC_TLS=false` or verify the server supports TLS on that port |
| Messages not appearing | Check the channel name includes `#` prefix in `IRC_CHANNELS` |

---

## Config reference

```json
{
  "kind": "irc",
  "enabled": true,
  "bridge_url": "http://irc-bridge:3005",
  "allowlist": "*",
  "max_rps": 3
}
```

| Field | Description |
|-------|-------------|
| `bridge_url` | URL of the irc-bridge service |
| `allowlist` | Comma-separated IRC nicks; `*` = allow everyone |
| `max_rps` | Max messages per second per nick |

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IRC_HOST` | `irc.libera.chat` | IRC server hostname |
| `IRC_PORT` | `6697` | IRC server port |
| `IRC_TLS` | `true` | Enable TLS (`false` to disable) |
| `IRC_NICK` | `vericlaw` | Bot nick |
| `IRC_PASS` | *(empty)* | NickServ password |
| `IRC_CHANNELS` | `#general` | Comma-separated channels to join |
