# WhatsApp Setup Guide

Run VeriClaw as a WhatsApp AI assistant — fully headless, no browser required.

---

## How it works

VeriClaw uses a lightweight [Baileys](https://github.com/WhiskeySockets/Baileys) bridge (`wa-bridge`) as a WhatsApp companion. The bridge handles the WhatsApp Web protocol; VeriClaw polls it every 2 seconds and replies via the same REST API.

**Pairing is done with a 6-digit code** you enter in your WhatsApp app — no QR code scan, no browser, works on any headless server.

---

## Prerequisites

- Docker Engine 24+ (or Docker Desktop)
- Docker Compose v2 (`docker compose` command)
- An LLM API key (OpenAI, Anthropic, or any OpenAI-compatible endpoint)
- A phone with WhatsApp installed

---

## Quick Start (Docker Compose)

### Step 1 — Clone and configure

```bash
git clone https://github.com/VeriClaw/vericlaw.git
cd vericlaw
cp config/whatsapp.example.json config/config.json
```

Edit `config/config.json` — replace `sk-REPLACE_WITH_YOUR_API_KEY` with your actual key:

```json
{
  "providers": [
    {
      "kind": "openai",
      "api_key": "sk-your-actual-key-here",
      "model": "gpt-4o-mini"
    }
  ]
}
```

The `bridge_url` is already set to `http://wa-bridge:3000` — the correct hostname for the Docker Compose network.

---

### Step 2 — Start the WhatsApp bridge and get your pairing code

```bash
WA_PHONE=+1234567890 docker compose up wa-bridge
```

Replace `+1234567890` with **your WhatsApp phone number** (include country code, e.g. `+447700900000` for UK).

Within a few seconds you will see:

```
wa-bridge-1  | WhatsApp pairing code: ABCD-1234
wa-bridge-1  | Enter this in WhatsApp > Settings > Linked Devices > "Link with phone number"
```

---

### Step 3 — Enter the pairing code on your phone

On your phone (doesn't need to be near the server):

1. Open **WhatsApp**
2. Go to **Settings** → **Linked Devices**
3. Tap **Link a Device**
4. Tap **"Link with phone number instead"** (bottom of the QR screen)
5. Enter the code shown in the logs (e.g. `ABCD-1234`)

WhatsApp will confirm "Device linked" within seconds.

---

### Step 4 — Start the full stack

Press `Ctrl+C` to stop the wa-bridge (or open a new terminal), then:

```bash
docker compose up
```

Both services start. VeriClaw gateway begins polling the bridge every 2 seconds.

---

### Step 5 — Send a message

Send any WhatsApp message to **yourself** (the number you used for pairing). VeriClaw will reply via the AI agent.

> **Note:** The `allowlist` in `config.json` is set to `"*"` by default (allows any sender). To restrict access to specific numbers, change it to a comma-separated list of phone numbers in E.164 format: `"+447700900000,+15551234567"`.

---

## Running in the background

```bash
docker compose up -d          # detached mode
docker compose logs -f        # follow logs
docker compose down           # stop
```

---

## Re-pairing after logout

WhatsApp sessions can be logged out remotely (Settings → Linked Devices → tap device → Log out). If that happens:

```bash
docker compose down
docker volume rm vericlaw_wa-sessions    # clear saved session
WA_PHONE=+1234567890 docker compose up wa-bridge    # re-pair
```

Then follow Steps 3–4 again.

---

## Running without Docker Compose

If you already have a running VeriClaw binary and want to add WhatsApp:

### 1. Start the bridge manually

```bash
cd wa-bridge
npm install
WA_PHONE=+1234567890 WA_SESSION=vericlaw SESSIONS_DIR=./sessions node index.js
```

### 2. Update your config

Set `bridge_url` to `http://localhost:3000` in `~/.vericlaw/config.json`:

```json
{
  "channels": [
    {
      "kind": "whatsapp",
      "enabled": true,
      "bridge_url": "http://localhost:3000",
      "allowlist": "*",
      "max_rps": 3
    }
  ]
}
```

### 3. Start VeriClaw

```bash
./vericlaw gateway
```

---

## Provider alternatives

The example config uses OpenAI. You can swap to any provider:

**Anthropic Claude:**
```json
{"kind": "anthropic", "api_key": "sk-ant-...", "model": "claude-3-5-haiku-20241022"}
```

**Ollama (local, free):**
```json
{"kind": "openai_compatible", "api_key": "", "base_url": "http://host.docker.internal:11434", "model": "llama3.2"}
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `WhatsApp pairing code` never appears | Check that `WA_PHONE` is set correctly with country code (e.g. `+447700900000`) |
| Pairing code expired | Codes expire in ~60s. Re-run `docker compose up wa-bridge` to get a new one |
| Messages not arriving | Check `docker compose logs wa-bridge` — session status should be `open` |
| `session not open` errors in vericlaw logs | Bridge lost connection; it will auto-reconnect within 5s |
| Agent replies not sending | Confirm `bridge_url` in config matches the bridge hostname (`wa-bridge` in compose, `localhost` standalone) |
| `allowlist` blocking messages | Set `"allowlist": "*"` for testing, then restrict to your numbers |
| Logged out remotely | Delete the sessions volume and re-pair (see Re-pairing section above) |

---

## Architecture

```
Your Phone (WhatsApp) ←──── WhatsApp Protocol ────→ wa-bridge (Node.js + Baileys)
                                                           │
                                                      HTTP REST API
                                                    GET  /sessions/vericlaw/messages
                                                    POST /sessions/vericlaw/messages
                                                           │
                                               VeriClaw Agent (Ada/SPARK binary)
                                                     channels-whatsapp.adb
                                                     polls every 2 seconds
                                                           │
                                                    LLM Provider API
                                               (OpenAI / Anthropic / Ollama)
```
