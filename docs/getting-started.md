[← Back to README](../README.md)

# Getting Started

This guide walks you through VeriClaw from first install to running your AI assistant.

---

## Step 1: Install

The fastest path is building from source:

```bash
curl -L https://alire.ada.dev/install.sh | bash   # install Alire
git clone https://github.com/vericlaw/vericlaw && cd vericlaw
alr build -- -XBUILD_PROFILE=release
```

Or grab a pre-built binary from [GitHub Releases](https://github.com/VeriClaw/vericlaw/releases).

> See [installation.md](installation.md) for Docker, Homebrew, Scoop, APT, and Raspberry Pi options.

Verify your install:

```bash
vericlaw version
```

You should see something like:

```
vericlaw 0.2.0 (abc1234 2026-03-09 x86_64-linux-gnu)
Built with Ada 2022 + GNAT  |  https://github.com/vericlaw
```

---

## Step 2: Onboard

Run the interactive setup wizard:

```bash
vericlaw onboard
```

The wizard displays a **styled banner** and walks you through:

1. **Choose an LLM provider** — OpenAI, Anthropic, Ollama (local), or any OpenAI-compatible endpoint
2. **Enter your API key** (skipped for Ollama)
3. **Pick a model** — defaults to `gpt-4o` / `claude-3-5-sonnet` / `llama3.2`
4. **Name your agent** — defaults to "VeriClaw"
5. **Choose a channel** — CLI (terminal), Telegram, Signal, or WhatsApp

Each step shows a **green ✓ confirmation**, and the wizard finishes with:

```
✓ Config written to ~/.vericlaw/config.json

Next steps:
  1. vericlaw doctor   — verify your setup
  2. vericlaw chat     — start chatting
  3. vericlaw gateway  — run multi-channel daemon
```

> [!TIP]
> If you skip `onboard` and just run `vericlaw`, it auto-creates a starter config
> and shows a **welcome banner** suggesting you run `vericlaw onboard`.

---

## Step 3: Doctor

Verify everything is working:

```bash
vericlaw doctor
```

The doctor runs through health checks with **colored ✓/✗ indicators**:

- **Config** — validates your config file and shows provider/channel summary
- **Database** — tests SQLite memory connection
- **Bridges** — pings each enabled channel bridge (WhatsApp, Signal, etc.)
- **SPARK** — confirms security core is compile-time verified
- **Workspace** — checks write permissions

A green summary line at the end shows your pass count:

```
✓ Summary:  5 / 5 checks passed
```

> If any check fails, the doctor shows a red ✗ with the failure reason.
> Fix the issue and re-run `vericlaw doctor`.

---

## Step 4: Chat

Start an interactive conversation:

```bash
vericlaw chat
```

You'll see the **VeriClaw banner**, your provider info, and session ID:

```
 __     __        _  ____ _
 \ \   / /__ _ __(_)/ ___| | __ ___      __
  \ \ / / _ \ '__| | |   | |/ _` \ \ /\ / /
   \ V /  __/ |  | | |___| | (_| |\ V  V /
    \_/ \___|_|  |_|\____|_|\__,_| \_/\_/

  v0.2.0  —  formally verified AI runtime

  provider  gpt-4o
  session   a1b2c3d4
  type /help for commands, exit to quit

you> Hello!
vericlaw> Hi! I'm VeriClaw. How can I help?
```

### Chat Commands

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/clear` | Clear conversation history |
| `/memory` | Show session info and message count |
| `/edit N` | Fork conversation at message N and re-prompt |
| `exit` | Quit VeriClaw |

### One-Shot Mode

For scripting or quick questions:

```bash
vericlaw agent "Summarise the top 3 headlines today"
```

Add `--json` for machine-readable output.

---

## Step 5: Gateway (Multi-Channel)

To run VeriClaw across multiple messaging channels simultaneously:

```bash
vericlaw gateway
```

The gateway displays a **boot status panel** showing your configuration at a glance:

```
  model     gpt-4o (OPENAI)
  memory    ok (sqlite)
  channels  cli, telegram, whatsapp (3 active)
  gateway   http://127.0.0.1:8787

  Press Ctrl+C to stop.
```

Each enabled channel runs concurrently via Ada tasks. See [channels.md](channels.md) for setup guides.

For Docker deployments, copy the environment template first:

```bash
cp .env.example .env    # fill in your API keys and channel tokens
docker compose up
```

---

## What's Next?

- **[Providers](providers.md)** — Configure multi-provider routing with failover
- **[Channels](channels.md)** — Set up Telegram, WhatsApp, Slack, Discord, and more
- **[Tools](tools.md)** — Enable file I/O, shell, web search, and MCP tools
- **[Operations](operations.md)** — Monitoring, logging, and production deployment
