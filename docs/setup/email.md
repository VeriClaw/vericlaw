# Email Setup Guide

Run VeriClaw as an email AI assistant — users send emails and get AI replies.

---

## How it works

VeriClaw uses a lightweight `email-bridge` Node.js service that polls an IMAP mailbox every 30 seconds for unread messages and sends replies via SMTP. VeriClaw polls the bridge's REST API and dispatches messages through the agent loop.

```
Sender ──email──▶ IMAP mailbox ──poll──▶ email-bridge (Node.js)
                                               │
                                          HTTP REST API
                                    GET  /sessions/email/messages
                                    POST /sessions/email/messages
                                               │
                                   VeriClaw Agent (Ada/SPARK)
                                     channels-email.adb
                                     polls every 30 seconds
                                               │
                                        LLM Provider API
                                   (OpenAI / Anthropic / Ollama)
                                               │
                                   SMTP ──reply──▶ Sender
```

---

## Prerequisites

- Docker Engine 24+ and Docker Compose v2
- A Gmail account (or any IMAP/SMTP provider)
- An LLM API key (OpenAI, Anthropic, or compatible)

For Gmail: **IMAP must be enabled** and you need an **App Password** (requires 2-Step Verification).

---

## Quick Start (Docker Compose)

### Step 1 — Enable IMAP and create an App Password (Gmail)

1. Go to [Google Account Security](https://myaccount.google.com/security)
2. Enable **2-Step Verification** if not already active
3. Go to **App Passwords** → create a new app password for "Mail"
4. Copy the 16-character password (e.g. `abcd efgh ijkl mnop`)

Enable IMAP:

1. Open Gmail → Settings → See all settings → Forwarding and POP/IMAP
2. Enable **IMAP Access** → Save Changes

### Step 2 — Configure

```bash
cp config/email.example.json config/config.json
```

Edit `config/config.json`:
- Replace `sk-REPLACE_WITH_YOUR_API_KEY` with your LLM API key
- Set `allowlist` to the email address(es) allowed to chat (comma-separated), or `"*"` for any sender

### Step 3 — Set environment variables

Create a `.env` file (or export variables):

```bash
EMAIL_USER=your@gmail.com
EMAIL_PASS=abcdefghijklmnop   # App Password (no spaces)
```

### Step 4 — Start

```bash
docker compose up email-bridge vericlaw
```

The bridge will start polling your inbox every 30 seconds. Send an email to your Gmail address from an allowlisted sender and VeriClaw will reply.

---

## Running without Docker Compose

### 1. Start the bridge manually

```bash
cd email-bridge
npm install
EMAIL_USER=your@gmail.com EMAIL_PASS=yourapppassword node index.js
```

### 2. Update config

Set `bridge_url` to `http://localhost:3003`:

```json
{
  "channels": [
    {
      "kind": "email",
      "enabled": true,
      "bridge_url": "http://localhost:3003",
      "allowlist": "allowed@example.com",
      "max_rps": 1
    }
  ]
}
```

### 3. Start VeriClaw

```bash
./vericlaw gateway
```

---

## Other IMAP/SMTP providers

Override the default Gmail endpoints via environment variables:

| Variable    | Default            | Example (Outlook)           |
|-------------|--------------------|-----------------------------|
| `IMAP_HOST` | `imap.gmail.com`   | `outlook.office365.com`     |
| `IMAP_PORT` | `993`              | `993`                       |
| `SMTP_HOST` | `smtp.gmail.com`   | `smtp.office365.com`        |
| `SMTP_PORT` | `587`              | `587`                       |
| `EMAIL_USER`| —                  | `you@outlook.com`           |
| `EMAIL_PASS`| —                  | your password / app password|

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `IMAP poll error: Invalid credentials` | Check `EMAIL_USER`/`EMAIL_PASS`; use App Password for Gmail |
| Bridge connects but no messages appear | Confirm IMAP is enabled in Gmail settings |
| `SMTP send error` | Verify `SMTP_HOST`/`SMTP_PORT` and credentials |
| Messages not arriving in queue | Emails must be **unread** — bridge marks them read on fetch |
| `Email: not configured, skipping` | Check `bridge_url` in config and that `enabled: true` is set |
| Allowlist blocking messages | Set `"allowlist": "*"` for testing, then restrict to specific addresses |
