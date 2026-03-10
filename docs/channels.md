# Channels

[← Back to README](../README.md)

VeriClaw supports 10 messaging channels, all running concurrently in `vericlaw gateway` mode via Ada tasks. Each channel gets its own memory handle backed by SQLite in WAL mode.

## Quick Reference

| Channel | Config `kind` | Bridge Required | Port | Setup Guide |
|---------|--------------|-----------------|------|-------------|
| CLI | `cli` | No | — | Built-in |
| Telegram | `telegram` | No | — | [Inline below](#telegram) |
| Signal | `signal` | Yes (`signal-cli`) | 8080 | [Inline below](#signal) |
| WhatsApp | `whatsapp` | Yes (`wa-bridge`) | 3100 | [Setup](setup/whatsapp.md) |
| Slack | `slack` | Yes (Socket Mode) | — | [Setup](setup/slack.md) |
| Discord | `discord` | Yes | — | [Setup](setup/discord.md) |
| Email | `email` | Yes (IMAP/SMTP) | — | [Setup](setup/email.md) |
| IRC | `irc` | Yes | — | [Setup](setup/irc.md) |
| Matrix | `matrix` | Yes | — | [Setup](setup/matrix.md) |
| Mattermost | `mattermost` | Yes (`mattermost-bridge`) | 3008 | [Inline below](#mattermost) |

---

## CLI

Works out of the box — no config needed.

```bash
vericlaw chat           # interactive conversation (streaming always-on)
vericlaw agent "..."    # one-shot mode
```

Streaming output is always-on — tokens print as they arrive.

---

## Telegram

No bridge required — VeriClaw speaks the Telegram Bot API natively.

1. Create a bot via [@BotFather](https://t.me/botfather) — copy the bot token.
2. Find your Telegram user ID via [@userinfobot](https://t.me/userinfobot).
3. Set `token` and `allowlist` (comma-separated IDs, or `"*"` for open — **not recommended**).
4. Run `vericlaw gateway`.

```jsonc
// channels.json
{ "kind": "telegram", "token": "123456:ABC-...", "allowlist": "42424242" }
```

---

## Signal

Requires [signal-cli](https://github.com/AsamK/signal-cli) running as a REST daemon.

```bash
java -jar signal-cli.jar -u +15551234567 daemon --http=127.0.0.1:8080
```

Set `bridge_url: "http://127.0.0.1:8080"` and `token: "+15551234567"` in config, then run `vericlaw gateway`.

---

## WhatsApp

Requires the bundled WA-Bridge (Baileys-based). See [docs/setup/whatsapp.md](setup/whatsapp.md) for headless pairing.

```bash
docker compose up wa-bridge
vericlaw channels login --channel whatsapp   # shows pairing code
```

Scan the pairing code with your phone, then start the gateway.

---

## Slack

Requires a Slack app in Socket Mode. See [docs/setup/slack.md](setup/slack.md) for app manifest and scopes.

```bash
export SLACK_BOT_TOKEN=xoxb-...
export SLACK_APP_TOKEN=xapp-...
docker compose up slack-bridge vericlaw
```

The bridge relays events over WebSocket — no public URL needed.

---

## Discord

Requires a Discord application with a bot token. See [docs/setup/discord.md](setup/discord.md) for permission setup.

```bash
export DISCORD_BOT_TOKEN=...
docker compose up discord-bridge vericlaw
```

Grant the bot **Send Messages** and **Read Message History** intents in the developer portal.

---

## Email

Polls an IMAP inbox every 30 seconds; replies via SMTP. See [docs/setup/email.md](setup/email.md).

```bash
# Gmail: enable IMAP + create an App Password (requires 2FA)
export EMAIL_USER=you@gmail.com  EMAIL_PASS=your-app-password
docker compose up email-bridge vericlaw
```

Each inbound email starts a new conversation thread.

---

## IRC

Connect to any IRC server. See [docs/setup/irc.md](setup/irc.md).

```bash
export IRC_HOST=irc.libera.chat  IRC_NICK=vericlaw  IRC_CHANNELS="#general"
docker compose up irc-bridge vericlaw
```

The bot joins the listed channels and responds to mentions or DMs.

---

## Matrix

Connect to any Matrix homeserver. See [docs/setup/matrix.md](setup/matrix.md).

```bash
export MATRIX_HOMESERVER=https://matrix.org
export MATRIX_TOKEN=syt_...
export MATRIX_USER_ID=@bot:matrix.org
docker compose up matrix-bridge vericlaw
```

Supports both encrypted and unencrypted rooms.

---

## Mattermost

Enterprise Slack alternative — self-hosted. Requires a bot account and personal access token on your Mattermost instance.

```bash
export MATTERMOST_URL=https://mattermost.example.com
export MATTERMOST_TOKEN=your-bot-token
export MATTERMOST_TEAM=my-team
export MATTERMOST_CHANNEL=town-square
docker compose up mattermost-bridge vericlaw
```

The bridge container (`mattermost-bridge`) listens on port 3008 and relays messages between VeriClaw and Mattermost via the bot token.

```jsonc
// channels.json
{
  "kind": "mattermost",
  "url": "https://mattermost.example.com",
  "token": "your-bot-token",
  "team": "my-team",
  "channel": "town-square"
}
```

```yaml
# docker-compose.yml (excerpt)
mattermost-bridge:
  image: vericlaw/mattermost-bridge:latest
  ports:
    - "3008:3008"
  environment:
    - MATTERMOST_URL=${MATTERMOST_URL}
    - MATTERMOST_TOKEN=${MATTERMOST_TOKEN}
    - MATTERMOST_TEAM=${MATTERMOST_TEAM}
    - MATTERMOST_CHANNEL=${MATTERMOST_CHANNEL}
```

---

## Multi-User Gateway

The gateway distinguishes between **operators** and **guests** — this is a key differentiator for shared deployments.

- **Operator**: When `allowlist` contains a specific user ID, that user gets full access with the complete system prompt and persistent memory.
- **Guest**: When `allowlist` is `"*"`, anyone else is sandboxed into an isolated memory namespace (`guest-{channel}-{user_id}`) with a modified system prompt including an advisory note. Guests **cannot** access operator memory or facts.

This model lets you expose a single bot to the public while keeping your private context secure.

---

## Running All Channels

Enable channels in your config, then start everything with a single command:

```bash
# Native — starts all enabled channels concurrently (Ada tasks)
vericlaw gateway

# Docker — full stack with all bridges
docker compose up
```

When the gateway starts, VeriClaw displays a **boot status panel** showing
your runtime configuration at a glance:

```
  model     gpt-4o (OPENAI)
  memory    ok (sqlite)
  channels  cli, telegram, whatsapp (3 active)
  gateway   http://127.0.0.1:8787

  Press Ctrl+C to stop.
```

All output is color-coded: green for healthy systems, yellow for warnings,
red for failures. Use `--no-color` to disable.

The gateway multiplexes all channels in one process. Each channel's lifecycle is managed by its own Ada task, so a crash in one channel does not affect the others.
