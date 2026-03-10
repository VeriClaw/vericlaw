# Matrix Setup Guide

Connect VeriClaw to Matrix using **matrix-bridge** — a Node.js sidecar that connects to a Matrix homeserver and exposes a REST API.

## How it works

```
Matrix homeserver ←──HTTPS──→ matrix-bridge (Node.js)
                                      ↕ REST polling
                                 VeriClaw (Ada)
```

`matrix-bridge` connects to your Matrix homeserver using an access token, listens for room messages, queues them, and exposes a simple REST API that VeriClaw polls every 2 seconds.

---

## 1. Create a Matrix account for the bot

You can use [matrix.org](https://matrix.org) or any homeserver (Element, Synapse self-hosted, etc.).

1. Register a new account for the bot (e.g. `@vericlaw:matrix.org`)
2. Log in and obtain an **access token**:

   **Via Element web:**
   - Settings → Help & About → scroll to the bottom → **Access Token**
   - Click to reveal and copy

   **Via curl:**
   ```bash
   curl -X POST https://matrix.org/_matrix/client/v3/login \
     -H 'Content-Type: application/json' \
     -d '{"type":"m.login.password","user":"vericlaw","password":"yourpassword"}'
   # Copy "access_token" from the response
   ```

3. Note your full **User ID** (e.g. `@vericlaw:matrix.org`)

---

## 2. Invite the bot to a room

In Element or any Matrix client:

1. Open the room (or create one)
2. Invite `@vericlaw:matrix.org` (your bot's user ID)
3. Accept the invite from the bot account

---

## 3. Configure docker-compose

Copy the example config and fill in your values:

```bash
cp config/matrix.example.json config/config.json
# Edit config.json: set api_key, allowlist (your Matrix user ID)
```

In your shell or a `.env` file, set:

```bash
export MATRIX_HOMESERVER=https://matrix.org    # your homeserver URL
export MATRIX_TOKEN=syt_your_access_token      # bot access token
export MATRIX_USER_ID=@vericlaw:matrix.org     # bot user ID
```

---

## 4. Start the stack

```bash
docker compose up matrix-bridge vericlaw -d
```

Check that the bridge connected:

```bash
docker compose logs matrix-bridge
# Should show: Matrix bridge listening on port 3006
```

---

## 5. Test it

Send a message in a room where the bot is a member. VeriClaw will reply within a few seconds.

You can also test the bridge REST API directly:

```bash
# Check health
curl http://localhost:3006/health

# Poll for messages
curl http://localhost:3006/sessions/matrix/messages

# Send a message
curl -X POST http://localhost:3006/sessions/matrix/messages \
  -H 'Content-Type: application/json' \
  -d '{"room": "!roomid:matrix.org", "text": "Hello from VeriClaw!"}'
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Bridge logs `M_UNKNOWN_TOKEN` | Access token is invalid or expired — regenerate it |
| Bot joins but never responds | Ensure your Matrix user ID is in `allowlist` in config.json |
| Bridge crashes on startup | Check `MATRIX_HOMESERVER` URL is reachable and includes `https://` |
| No messages received | Confirm the bot account has been invited and joined the room |
| Rate limit errors from homeserver | Reduce `max_rps` in config.json |

---

## Config reference

```json
{
  "kind": "matrix",
  "enabled": true,
  "bridge_url": "http://matrix-bridge:3006",
  "allowlist": "@youruser:matrix.org",
  "max_rps": 3
}
```

| Field | Description |
|-------|-------------|
| `bridge_url` | URL of the matrix-bridge service |
| `allowlist` | Comma-separated Matrix user IDs; `*` = allow everyone |
| `max_rps` | Max messages per second per user |

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MATRIX_HOMESERVER` | `https://matrix.org` | Matrix homeserver base URL |
| `MATRIX_TOKEN` | *(required)* | Bot access token |
| `MATRIX_USER_ID` | *(required)* | Bot user ID (e.g. `@vericlaw:matrix.org`) |
