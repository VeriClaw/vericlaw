[← Back to README](../README.md)

# Getting Started

Three steps from nothing to a working AI assistant in your terminal and on Signal.

---

## Step 1: Install

VeriClaw v0.3.0 is installed by building from source. Pre-built binaries will be available on [GitHub Releases](https://github.com/VeriClaw/vericlaw/releases) from v1.0 onwards.

```bash
# Install Alire (Ada package manager)
curl -L https://alire.ada.dev/install.sh | bash

# Clone and build
git clone https://github.com/vericlaw/vericlaw
cd vericlaw
alr build -- -XBUILD_PROFILE=release
sudo cp bin/vericlaw /usr/local/bin/
```

Verify:

```bash
vericlaw version
```

Expected output:

```
vericlaw 0.3.0 (abc1234 2026-03-10 aarch64-linux-gnu)
```

---

## Step 2: Onboard

```bash
vericlaw onboard
```

The wizard walks you through six steps and leaves you with a fully working product at the end. You do not need to run anything else.

```
$ vericlaw onboard

VeriClaw — first-time setup

[1/6] AI provider
  Which provider would you like to use?
  1. Anthropic (Claude) — recommended
  2. OpenAI-compatible (Azure, Gemini, Ollama, OpenRouter, etc.)
  > 1

  Enter your Anthropic API key (starts with sk-ant-):
  > sk-ant-api03-xxxxx
  ✓ Key validated — connected to claude-sonnet-4

[2/6] Signal phone number
  Enter the phone number linked to your Signal account:
  > +447700900000
  ✓ Phone number saved

[3/6] Signal pairing
  Scan this QR code with Signal on your phone:
  Signal → Settings → Linked Devices → +
  ┌─────────────────────┐
  │ ▄▄▄▄▄ █ █▄█ ▄▄▄▄▄  │
  │ █   █ ██▄██ █   █  │
  │ ...                 │
  └─────────────────────┘
  Waiting for pairing...
  ✓ Signal linked successfully

[4/6] Workspace
  VeriClaw will store files in ~/vericlaw-workspace
  Press Enter to accept, or type a different path:
  > [Enter]
  ✓ Workspace created

[5/6] System check
  Config         ✓  valid
  Provider       ✓  Anthropic (responding)
  Signal         ✓  linked and ready
  Memory         ✓  SQLite (new database)
  Workspace      ✓  writable
  Security       ✓  4/4 SPARK packages verified

  All checks passed.

[6/6] Done

✓ Setup complete. VeriClaw is ready to use.

  vericlaw chat           Start VeriClaw (CLI + Signal)
  vericlaw chat --local   Start without Signal

Config saved to ~/.vericlaw/config.json
```

API key validation happens immediately at step 1 — you won't get to step 6 with a bad key.

> **Note (v0.3.0):** Signal steps (2–3) are shown in the wizard but Signal messaging is not yet functional — `vericlaw-signal` builds cleanly as a Rust scaffold but presage device linking is not wired to the Ada runtime in v0.3.0. Full Signal integration ships in v1.1. Skip those steps or use `vericlaw chat --local` for CLI-only mode.

---

## Step 3: Chat

```bash
vericlaw chat
```

```
VeriClaw v0.3.0 — type /help for commands, /exit to quit

you> Hello, what can you do?

vericlaw> I'm VeriClaw, a security-first AI assistant. I can help you
with questions, run commands in your workspace, fetch web content,
set reminders, and process voice messages and images. What would you
like to work on?
```

That's it. You now have:

- **CLI chat** — interactive terminal session with streaming output
- **Signal** — not yet functional in v0.3.0; full integration in v1.1

---

## What you get after the three steps

| Capability | How to use it |
|---|---|
| CLI chat | `vericlaw chat` |
| CLI chat without Signal | `vericlaw chat --local` |
| File operations | Ask VeriClaw to read or write files in your workspace |
| Web fetch | Ask VeriClaw to fetch a URL |
| Shell commands | Ask VeriClaw to run an allowlisted command |
| Custom system prompt | Edit `~/.vericlaw/system.md` |

> Signal chat (send/receive), voice messages, and image processing via Signal require v1.1. See [channels.md](channels.md) for Signal's current status.

---

## CLI commands

```
vericlaw onboard          Set up VeriClaw for the first time
vericlaw doctor           Check that everything is working
vericlaw chat             Start VeriClaw (CLI + Signal)
vericlaw chat --local     Start without Signal
vericlaw status           Show current provider, Signal link status, memory stats
vericlaw version          Show version and build info
```

### doctor

Runs a health check and shows a scannable report:

```
$ vericlaw doctor

VeriClaw v0.3.0 — system check

  Config         ✓  ~/.vericlaw/config.json (valid)
  Provider       ✓  Anthropic — claude-sonnet-4 (responding)
  Signal         ✓  +447700900000 (linked, bridge running)
  Memory         ✓  SQLite — ~/vericlaw-workspace/memory.db (12 sessions)
  Workspace      ✓  ~/vericlaw-workspace (writable)
  Security       ✓  SPARK proofs — 4/4 packages verified

All checks passed.
```

If something is wrong, doctor shows the exact failure and a fix:

```
  Signal         ✗  Bridge not responding
                    The Signal bridge process may have stopped.
                    → Run: vericlaw onboard --repair-signal
```

---

## Chat slash commands

These work in `vericlaw chat` (CLI mode only). Signal uses natural language instead — see below.

| Command | What it does |
|---|---|
| `/help` | Show available commands |
| `/clear` | Clear conversation history for this session |
| `/memory` | Show what VeriClaw remembers from past sessions |
| `/export` | Save this conversation to a markdown file in your workspace |
| `/exit` | End the chat |

---

## Signal UX

Signal is not a CLI. There are no slash commands on Signal — use natural language:

- **"What do you remember about me?"** → equivalent to `/memory`
- **"Start fresh"** or **"Forget what we were talking about"** → equivalent to `/clear`
- **Voice messages** — speak naturally; VeriClaw transcribes and responds to the content
- **Images** — send a photo; VeriClaw can describe it, answer questions about it, or act on it
- **Short messages work best** — VeriClaw defaults to concise responses on Signal; ask for more detail if you need it

---

## Customising the system prompt

VeriClaw loads `~/.vericlaw/system.md` as the system prompt if it exists. Create it to change how VeriClaw behaves:

```bash
cat > ~/.vericlaw/system.md << 'EOF'
You are a personal assistant helping me manage my projects and to-do list.
Keep responses short and actionable.
EOF
```

Changes take effect the next time you run `vericlaw chat` or restart the service.

---

## What's next?

- **[Providers](providers.md)** — Configure Anthropic, OpenAI-compatible endpoints, Ollama
- **[Troubleshooting](troubleshooting.md)** — Fix common setup issues
- **[Security Proofs](security-proofs.md)** — How VeriClaw's SPARK proofs work
- **[Pi Deployment](pi-deployment.md)** — Run VeriClaw on a Raspberry Pi 4
