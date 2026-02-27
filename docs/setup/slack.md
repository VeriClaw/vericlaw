# Slack Setup Guide

Connect VeriClaw to Slack using **Socket Mode** — no public URL or webhook endpoint needed.

## How it works

```
Slack ←──WebSocket──→ slack-bridge (Node.js)
                              ↕ REST polling
                         VeriClaw (Ada)
```

`slack-bridge` connects to Slack's Socket Mode WebSocket, queues incoming DMs, and exposes a simple REST API that VeriClaw polls every 2 seconds.

---

## 1. Create a Slack App

1. Go to [api.slack.com/apps](https://api.slack.com/apps) → **Create New App** → **From scratch**
2. Give it a name (e.g. *VeriClaw*) and pick your workspace

## 2. Enable Socket Mode

1. In the left sidebar → **Socket Mode** → toggle **Enable Socket Mode**
2. Click **Generate** to create an App-Level Token
   - Token name: `vericlaw-socket`
   - Scope: `connections:write`
3. Copy the token — it starts with `xapp-`

## 3. Add Bot Token Scopes

1. Left sidebar → **OAuth & Permissions** → **Bot Token Scopes**
2. Add these scopes:
   - `chat:write` — send messages
   - `im:history` — read direct messages
   - `mpim:history` — read group DMs
   - `channels:history` — read public channel messages (if using channels)

## 4. Subscribe to Events

1. Left sidebar → **Event Subscriptions** → toggle **Enable Events**
2. Under **Subscribe to bot events**, add:
   - `message.im` — direct messages
   - `message.mpim` — group DMs (optional)

## 5. Install App to Workspace

1. Left sidebar → **Install App** → **Install to Workspace**
2. Copy the **Bot User OAuth Token** — it starts with `xoxb-`

## 6. Find Your Slack User ID

1. In Slack, click your profile picture → **Profile**
2. Click **⋮** (More actions) → **Copy member ID**
3. It looks like `U0123456789`

---

## 7. Configure docker-compose

Copy the example config and fill in your values:

```bash
cp config/slack.example.json config/config.json
# Edit config.json: set api_key, allowlist (your Slack user ID)
```

In your shell or a `.env` file, set:

```bash
export SLACK_BOT_TOKEN=xoxb-your-bot-token
export SLACK_APP_TOKEN=xapp-your-app-token
```

## 8. Start the stack

```bash
docker compose up slack-bridge vericlaw -d
```

Check that the bridge is connected:

```bash
docker compose logs slack-bridge
# Should show: ⚡️  VeriClaw Slack bridge connected via Socket Mode
```

---

## 9. Test it

Send a direct message to your VeriClaw bot in Slack. It should reply within a few seconds.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Bridge exits with `invalid_auth` | Check `SLACK_BOT_TOKEN` starts with `xoxb-` |
| Bridge exits with `not_allowed_token_type` | Check `SLACK_APP_TOKEN` starts with `xapp-` |
| Bot doesn't respond | Ensure your Slack user ID is in `allowlist` in config.json |
| `channel and text required` in bridge logs | This is a bridge internal error — check Ada send logic |

## Config reference

```json
{
  "kind": "slack",
  "enabled": true,
  "bridge_url": "http://slack-bridge:3001",
  "allowlist": "U0123456789,U9876543210",
  "max_rps": 3
}
```

| Field | Description |
|-------|-------------|
| `bridge_url` | URL of the slack-bridge service |
| `allowlist` | Comma-separated Slack user IDs; `*` = allow everyone |
| `max_rps` | Max messages per second per user |
