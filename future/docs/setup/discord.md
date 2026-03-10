# Discord Setup Guide for VeriClaw

Connect VeriClaw to Discord via a lightweight discord.js bridge.

## Prerequisites

- Docker and Docker Compose
- A Discord account
- A VeriClaw config with a provider API key

## Steps

### 1. Create a Discord Application and Bot

1. Go to [discord.com/developers/applications](https://discord.com/developers/applications)
2. Click **New Application**, give it a name (e.g. "VeriClaw")
3. Navigate to **Bot** in the left sidebar
4. Click **Add Bot** → confirm
5. Under **Privileged Gateway Intents**, enable **Message Content Intent**
6. Click **Reset Token** and copy the token — this is your `DISCORD_BOT_TOKEN`

### 2. Invite the Bot to Your Server

1. Go to **OAuth2 → URL Generator** in the left sidebar
2. Under **Scopes**, select `bot`
3. Under **Bot Permissions**, select:
   - Send Messages
   - Read Message History
4. Copy the generated URL and open it in your browser
5. Select your server and click **Authorize**

### 3. Find Your Discord User ID

1. Open Discord → **Settings → Advanced**
2. Enable **Developer Mode**
3. Right-click your username in any channel → **Copy User ID**

### 4. Configure VeriClaw

Copy the example config and fill in your values:

```bash
cp config/discord.example.json config/config.json
```

Edit `config/config.json`:

```json
{
  "channels": [
    {
      "kind": "discord",
      "enabled": true,
      "bridge_url": "http://discord-bridge:3002",
      "token": "",
      "allowlist": "YOUR_DISCORD_USER_ID",
      "max_rps": 3
    }
  ]
}
```

- **allowlist**: Comma-separated Discord user IDs allowed to interact with the bot.
  Use `"*"` to allow everyone (not recommended for production).
- **token**: Not used — the bot token is passed via the `DISCORD_BOT_TOKEN` environment variable.

### 5. Start the Services

```bash
DISCORD_BOT_TOKEN=your-token-here docker compose up discord-bridge vericlaw
```

Or set the variable in a `.env` file:

```
DISCORD_BOT_TOKEN=your-token-here
```

Then:

```bash
docker compose up discord-bridge vericlaw
```

### 6. Test

Send a message to the bot in your Discord server (in any channel the bot has access to).
The bot will reply via VeriClaw.

## Session Isolation

Each Discord channel gets its own conversation session:
`discord-{guild_id}-{channel_id}`. This means separate conversation histories
per channel.

## Troubleshooting

- **Bot not responding**: Check `docker compose logs discord-bridge` for errors.
- **"Used disallowed intents"**: Enable the **Message Content Intent** in the Discord Developer Portal under your bot's settings.
- **Bot responds to everyone**: Set `allowlist` to your user ID(s) in the config.
