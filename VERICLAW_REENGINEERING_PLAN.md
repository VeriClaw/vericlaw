# VeriClaw Re-Engineering Plan

**Date:** 2026-03-10
**Status:** Active — targeting v1.0-minimal ship
**Author:** Eugene + Claude (Principal Engineer / Chief Business Analyst)

---

## 1. Why this document exists

VeriClaw has grown into a sprawling design that tries to be everything at once: a multi-channel gateway, an operator platform, a service daemon, a formal-verification showcase, and a personal AI assistant. At v0.2.0 with a solo developer, this breadth is unsustainable. The project feels heavy and off-track because it *is* heavy and off-track.

This document defines what VeriClaw should look like today, what gets cut, where cut material goes, and what the ship criteria are for a v1.0-minimal release that can be built, deployed, and used in a single day.

---

## 2. Strategic position

### 2.1 The competitive landscape (March 2026)

| Project | Language | Binary size | RAM | Differentiator | Weakness |
|---------|----------|-------------|-----|----------------|----------|
| OpenClaw | TypeScript/Node.js | Heavy | 100MB+ | Category creator, massive community, 100k+ GitHub stars, huge skill ecosystem | Documented security problems: prompt injection, data exfiltration via skills, broad permissions model |
| ZeroClaw | Rust | ~3.4 MB | ~5 MB | Trait-based architecture, fast cold start, memory safety | Multiple competing forks fighting over legitimacy; conventional memory safety, not formal proofs |
| NullClaw | Zig | ~678 KB | ~1 MB | Smallest footprint, IoT/edge targeting, hardware peripheral support | Extremely new, questions about real-world testing depth |
| PicoClaw | Go | Small | <10 MB | Sipeed hardware backing, RISC-V native, 95% AI-generated code | Early development, limited autonomy, backed by hardware vendor agenda |
| **VeriClaw** | **Ada/SPARK** | **~5.3 MB** | **Low** | **Formally verified security core — unique in the entire ecosystem** | **Overscoped, not yet shippable as a usable product** |

### 2.2 Where VeriClaw wins

Every competitor claims security. None can prove it. OpenClaw has active CrowdStrike advisories. ZeroClaw and NullClaw rely on language-level memory safety (Rust's borrow checker, Zig's manual memory management) — which prevents memory bugs but says nothing about policy correctness. Nobody else has SPARK proofs on security-critical decision logic.

VeriClaw's moat is formal verification of the policy layer. Everything else is table stakes.

### 2.3 The one-liner

> **VeriClaw: the only AI agent runtime with formally verified security. Runs on a Pi. Talks over Signal.**

---

## 3. What VeriClaw must be today

### 3.1 The minimal shippable product

VeriClaw v1.0-minimal is exactly this — no more, no less:

1. **One channel:** Signal (via signal-cli sidecar)
2. **One provider:** Anthropic (or OpenAI-compatible for Ollama fallback)
3. **One storage backend:** SQLite with conversation history and basic memory
4. **The SPARK security core:** Actually proven, actually passing GNATprove at Silver level
5. **CLI mode:** For local development and testing
6. **One deployment target:** Raspberry Pi 4 (or any Linux aarch64/x86_64 box)

That's it. That is the entire product.

### 3.2 Why Signal

Signal is the security-conscious person's messenger. It's open source, end-to-end encrypted, and trusted by journalists, activists, and security engineers. Pairing the only formally-verified AI agent runtime with the most trusted secure messenger is a natural market fit that no competitor is explicitly targeting.

OpenClaw supports Signal as one of 20+ channels. VeriClaw should support Signal as *the* channel, done exceptionally well.

### 3.3 Provider strategy: Anthropic + OpenAI-compatible

Multi-provider failover chains are premature optimisation. But limiting to a single provider is unnecessarily restrictive when one extra implementation unlocks the entire ecosystem.

VeriClaw ships with two provider implementations:

1. **Anthropic (native, first-class).** Claude is the best model for agent work. Tool-calling, streaming, and error handling are implemented against Anthropic's API directly. This is the default and the most tested path.

2. **OpenAI-compatible (generic).** A single implementation that works with any endpoint following the OpenAI chat completions API format. This immediately covers Azure AI Foundry, Google Gemini (via its OpenAI-compatible mode), Ollama, OpenRouter, Groq, DeepSeek, Mistral, and dozens of others. The user provides a `base_url`, `api_key`, and `model` — VeriClaw handles the rest.

This is two implementations, not five. The OpenAI-compatible format is a de facto standard — by supporting it generically, VeriClaw avoids writing and maintaining separate adapters for every provider while still giving users real choice.

No failover chain. No ordered routing. The user picks one provider in their config. If they want to switch, they change one config value. Simple.

### 3.4 The zero-dependency user experience

**Core principle: the user never leaves the CLI.** They never install a separate bridge, never configure a sidecar, never run Docker alongside VeriClaw. Everything is baked into the single binary or managed automatically by VeriClaw itself.

This means:

- **Signal integration is a bundled Rust companion binary.** A thin Rust binary called `vericlaw-signal`, built on the presage library, ships in the release archive alongside the main Ada binary. No JVM, no Node.js, no Docker. VeriClaw spawns it as a managed child process and communicates via JSON-over-stdin/stdout. The user never sees it, installs it, or configures it.
- **SQLite is statically linked.** No system `libsqlite3` dependency. This is standard for Ada projects using GNATCOLL — just ensure the static build path is the default.
- **libcurl is statically linked or the HTTP client is native.** The user should not need to install libcurl. If the Ada HTTP stack (AWS) can handle outbound HTTPS to Anthropic's API, use that and drop the libcurl dependency entirely. If libcurl is needed, it must be statically linked into the release binary.
- **The release artifact is a single archive** containing two statically-linked binaries: `vericlaw` (Ada) and `vericlaw-signal` (Rust/presage). No `node_modules`, no `package.json`, no JVM, no Docker. Total archive size: ~10-15 MB.

### 3.5 The user journey for v1.0-minimal

```
1. Install
   curl -fsSL https://vericlaw.dev/install.sh | sh
   → detects OS/arch, downloads binaries, adds to PATH
2. vericlaw onboard
   → choose provider (Anthropic or OpenAI-compatible)
   → enter API key, validates it live
   → prompts for Signal phone number
   → pairs Signal via QR code in the terminal
   → creates workspace directory
   → writes config
   → runs health check automatically
   → prints: "You're ready. Run: vericlaw chat"
3. vericlaw chat
   → local CLI chat, working immediately
   → Signal is already listening in the background
   → send yourself a message on Signal to verify
```

**Three steps. Not five, not four. Three.** Download, onboard, chat. The user starts in the CLI and finishes in the CLI with a fully working product. At no point do they open a browser, install a package, edit a config file, or run a separate service.

The `doctor` command still exists for troubleshooting, but it is not part of the happy path. Onboard runs the equivalent checks itself and only succeeds if everything passes.

`vericlaw signal` as a separate command is also eliminated from the default flow — Signal starts automatically when VeriClaw starts. If the user wants CLI-only mode without Signal, they can use `vericlaw chat --local`. But the default is: everything is on.

---

## 4. What to do with the existing codebase

### 4.1 Guiding principle

Nothing is deleted. Everything that isn't in the v1.0-minimal critical path moves to a `future/` directory in the repo with its own README explaining what it is and when it comes back. This preserves all the work done while making `src/` clean and focused.

### 4.2 What stays in `src/`

| Component | Directory | Why it stays |
|-----------|-----------|-------------|
| Agent loop | `src/agent/` | Core orchestration — strip to single-provider, single-channel path |
| Security core (SPARK) | `src/security/` | **The differentiator.** This is the reason VeriClaw exists. Every package here must have passing GNATprove results. |
| Anthropic provider | `src/providers/anthropic.ads/adb` | First-class native implementation — Claude as the primary model |
| OpenAI-compatible provider | `src/providers/openai_compat.ads/adb` | Generic implementation covering Azure AI Foundry, Gemini, Ollama, OpenRouter, Groq, DeepSeek, and any OpenAI-format endpoint |
| Provider interface spec | `src/providers/provider.ads` | Clean interface that both implementations conform to |
| Signal channel adapter | `src/channels/signal.ads/adb` | The one channel — manages the bundled Signal bridge as a child process, no user-facing sidecar |
| Channel interface spec | `src/channels/channel.ads` | Keep the interface clean |
| CLI channel | `src/channels/cli.ads/adb` | Essential for development and local testing |
| Signal bridge manager | `src/signal/` | **New.** Lifecycle management for the bundled `vericlaw-signal` Rust binary: spawning, stdin/stdout JSON IPC, health monitoring, restart on crash. This is what makes Signal "baked in" — VeriClaw manages the companion process invisibly. |
| SQLite memory | `src/memory/` | Strip to core: conversation history, basic facts, FTS5 search, cron schedule storage |
| Config loader | `src/config/` | Simplify to only load what v1.0-minimal needs; reads `~/.vericlaw/system.md` for system prompt customisation |
| Terminal UI | `src/terminal/` | CLI rendering, keep it |
| Tools: file, web_fetch, shell, cron, export | `src/tools/` | Five tools that make VeriClaw a useful agent. Shell is allowlist-gated by SPARK policy. Cron enables proactive behaviour. Export enables session record-keeping. |

### 4.3 What moves to `future/`

Create `future/` at the repo root. Move each component into its own subdirectory with a brief `README.md` explaining what it does and what milestone brings it back.

| Component | Current location | Moves to | Return milestone |
|-----------|-----------------|----------|-----------------|
| Telegram channel | `src/channels/telegram.*` | `future/channels/telegram/` | v1.1 (second native channel) |
| All other channel adapters | `src/channels/adapters-*` | `future/channels/` | v1.2+ |
| OpenAI provider (named) | `src/providers/openai.*` | `future/providers/openai/` | v1.1 (dedicated OpenAI with native features beyond compat layer) |
| Google Gemini provider (named) | `src/providers/gemini.*` | `future/providers/gemini/` | v1.1 (dedicated Gemini with native features beyond compat layer) |
| Azure provider (named) | `src/providers/azure.*` | `future/providers/azure/` | v1.1 (dedicated Azure with native features beyond compat layer) |
| Provider failover chain | `src/providers/routing.*` | `future/providers/failover/` | v1.2 |
| HTTP gateway/API | `src/http/` | `future/gateway/` | v1.3 (gateway mode) |
| Observability/metrics | `src/observability/` | `future/observability/` | v1.3 |
| Sandbox module | `src/sandbox/` | `future/sandbox/` | v1.2 |
| Vector memory (sqlite-vec) | `src/memory/vector*` | `future/memory/vector/` | v1.1 |
| Context compaction | `src/memory/compact*` | `future/memory/compaction/` | v1.1 |
| Tool: git (dedicated) | `src/tools/git.*` | `future/tools/git/` | v1.1 |
| Tool: brave search | `src/tools/brave.*` | `future/tools/brave/` | v1.2 |
| Tool: browser | `src/tools/browser.*` | `future/tools/browser/` | v1.3 |
| Tool: spawn/delegate | `src/tools/spawn.*, delegate.*` | `future/tools/subagents/` | v1.3 |
| Operator console | `operator-console/` | `future/operator-console/` | v1.3 |

### 4.4 What moves to `future/bridges/`

All Node.js bridge sidecars except Signal move out of the repo root.

| Bridge | Current location | Moves to |
|--------|-----------------|----------|
| wa-bridge | `wa-bridge/` | `future/bridges/whatsapp/` |
| slack-bridge | `slack-bridge/` | `future/bridges/slack/` |
| discord-bridge | `discord-bridge/` | `future/bridges/discord/` |
| email-bridge | `email-bridge/` | `future/bridges/email/` |
| irc-bridge | `irc-bridge/` | `future/bridges/irc/` |
| matrix-bridge | `matrix-bridge/` | `future/bridges/matrix/` |
| mcp-bridge | `mcp-bridge/` | `future/bridges/mcp/` |
| browser-bridge | `browser-bridge/` | `future/bridges/browser/` |
| bridge-common | `bridge-common/` | `future/bridges/common/` |

**Signal bridge** stays at root level as it's the only active channel integration.

### 4.5 What moves to `future/deploy/`

| Component | Current location | Moves to |
|-----------|-----------------|----------|
| macOS launchd service | `deploy/macos/` | `future/deploy/macos/` |
| Windows service | `deploy/windows/` | `future/deploy/windows/` |
| Full docker-compose.yml | `docker-compose.yml` | `future/deploy/compose-full/` |
| Homebrew formula | `packaging/homebrew/` | `future/packaging/homebrew/` |
| Scoop manifest | `packaging/scoop/` | `future/packaging/scoop/` |
| APT packaging | `packaging/apt/` | `future/packaging/apt/` |
| Winget template | `packaging/winget/` | `future/packaging/winget/` |

**Keep:** A simple `deploy/systemd/` unit file for running on the Pi, and a minimal `Dockerfile` for the single-service case.

### 4.6 Simplified repo layout after cleanup

```
vericlaw/
├── README.md                  (rewritten — see section 7)
├── ARCHITECTURE.md            (simplified to match v1.0-minimal)
├── SECURITY.md                (focused on what's actually proven)
├── CONTRIBUTING.md
├── CHANGELOG.md
├── LICENSE                    (resolve: MIT or GPL v3?)
├── alire.toml
├── vericlaw.gpr
├── spark.adc
├── Makefile
├── Dockerfile                 (single-service, minimal)
├── install.sh                 (curl-friendly installer — detects OS/arch, downloads, installs)
├── config/
│   └── config.example.json    (Anthropic + Signal + CLI only)
├── src/
│   ├── agent/                 (single-loop orchestration)
│   ├── channels/
│   │   ├── channel.ads        (interface)
│   │   ├── cli.ads/adb        (local dev)
│   │   └── signal.ads/adb     (the channel)
│   ├── providers/
│   │   ├── provider.ads       (interface)
│   │   ├── anthropic.ads/adb  (native Anthropic/Claude)
│   │   └── openai_compat.ads/adb (generic OpenAI-compatible — covers Azure, Gemini, Ollama, etc.)
│   ├── security/              (SPARK — the crown jewels)
│   ├── signal/                (bridge lifecycle: provision, start, pair, health, restart)
│   ├── memory/                (SQLite, history, facts, FTS5)
│   ├── config/                (simplified loader)
│   ├── terminal/              (CLI rendering)
│   └── tools/
│       ├── file.ads/adb       (workspace-scoped file I/O)
│       ├── web_fetch.ads/adb  (basic HTTP fetch)
│       ├── shell.ads/adb      (allowlisted command execution)
│       ├── cron.ads/adb       (scheduling — reminders and recurring tasks)
│       └── export.ads/adb     (session export to markdown)
├── vericlaw-signal/            (Rust companion binary — presage-based Signal bridge)
│   ├── Cargo.toml
│   ├── Cargo.lock
│   └── src/
│       └── main.rs            (~300 lines: presage wrapper, JSON-over-stdin/stdout IPC)
├── tests/
├── deploy/
│   └── systemd/
├── scripts/
├── docs/
│   ├── getting-started.md
│   ├── troubleshooting.md     (new — replaces signal-setup.md, covers all recovery paths)
│   ├── security-proofs.md     (new — what's actually proven and how to verify)
│   ├── pi-deployment.md       (new — dedicated Pi 4 guide)
│   └── providers.md           (Anthropic + OpenAI-compatible setup guide)
├── future/                    (everything else, preserved with READMEs)
│   ├── README.md
│   ├── bridges/
│   ├── channels/
│   ├── providers/
│   ├── gateway/
│   ├── observability/
│   ├── tools/
│   ├── operator-console/
│   ├── deploy/
│   └── packaging/
└── .github/
    └── workflows/             (simplified CI — build + prove + test only)
```

---

## 5. The SPARK security core — what must actually be proven

This is VeriClaw's entire reason to exist. The security core must not be aspirational. Every package listed here must have passing GNATprove results at Silver level before v1.0-minimal ships.

### 5.1 Must-prove packages for v1.0-minimal

| Package | What it proves | Why it matters |
|---------|---------------|----------------|
| `security-policy` | Allowlist decisions are total functions with no runtime exceptions; deny is the default for any input not explicitly allowed | This is the front door. If the policy check is wrong, everything else is irrelevant. |
| `security-secrets` | Secret storage handles are always zeroed after use; no secret can be read without explicit unlock; encrypted-at-rest invariant holds | API keys are the highest-value target for any attacker. |
| `security-audit` | Every security decision is logged; audit trail cannot be silently dropped; redaction of secrets in log output is complete | If you can't prove the audit trail is reliable, you can't prove anything happened correctly. |
| `channels-security` | Per-session rate limiting has no integer overflow; rate limit state transitions are monotonic; allowlist check always runs before message dispatch | Rate limiting bugs are a classic source of denial-of-service and bypass vulnerabilities. |

### 5.2 Nice-to-prove (v1.1 targets)

| Package | What it proves |
|---------|---------------|
| `gateway-auth` | Token validation is constant-time; pairing codes have sufficient entropy |
| `security-secrets-crypto` | No plaintext secret survives past the decryption scope |
| `channels-adapters-signal` | Input sanitisation is complete for Signal message payloads |

### 5.3 How to verify

The repo must include a `make prove` target that runs GNATprove on all must-prove packages and produces a clear pass/fail summary. The CI pipeline runs this on every commit. No PR merges with proof regressions.

```makefile
prove:
	gnatprove -P vericlaw.gpr --level=2 --prover=z3,cvc4,altergo \
	  --timeout=60 --report=fail \
	  -u security-policy \
	  -u security-secrets \
	  -u security-audit \
	  -u channels-security
```

### 5.4 What to do if proofs don't currently pass

Be honest about it. If a package has `SPARK_Mode (On)` but incomplete contracts or failing proofs, the options are:

1. **Fix the contracts and make them pass.** This is the right answer for the four must-prove packages.
2. **Downgrade to Ada with documented contracts.** If a package can't be proven in time, remove `SPARK_Mode`, add strong precondition/postcondition assertions, and document it as "contract-checked, not yet formally proved" in `SECURITY.md`. This is honest and still better than what competitors offer.
3. **Never claim something is proven when it isn't.** The SECURITY.md must only list packages that actually pass GNATprove. Aspirational proofs go in the roadmap, not the security documentation.

---

## 6. Tools and capabilities for v1.0-minimal

### 6.1 Built-in tools

| Tool | Capability | Security boundary |
|------|-----------|-------------------|
| `file` | Read/write files within the workspace directory | Workspace-scoped, path traversal blocked, validated by SPARK policy |
| `web_fetch` | HTTP GET to fetch web content | URL validated against egress policy, no private/internal network access |
| `shell` | Execute allowlisted commands in the workspace | **Allowlist-only.** Only commands explicitly listed in config can run. Default allowlist: `ls`, `cat`, `grep`, `head`, `tail`, `wc`, `find`, `sort`, `diff`, `echo`, `date`, `python3`, `git`. No `rm -rf`, no `sudo`, no pipe to bash. SPARK policy validates every invocation against the allowlist before execution. |
| `cron` | Schedule recurring or one-shot tasks | Tasks stored in SQLite. Agent loop fires on schedule, processes the prompt, sends result to the active channel. Rate-limited by security policy. |

### 6.2 Shell tool design

The shell tool is what makes VeriClaw an agent rather than a chatbot. Without it, the agent can answer questions and read files. With it, the agent can actually do things — run scripts, query APIs, interact with version control, process data.

The security model is strict:

- **Allowlist is explicit.** Only commands listed in `security.shell_allowlist` in config can execute. There is no wildcard, no "allow all" mode.
- **The allowlist check is in the SPARK security core.** This is not a string comparison in application code — it's a formally verified policy decision.
- **Commands run in the workspace directory.** No `cd /` followed by operations outside the sandbox.
- **No shell expansion by default.** Commands are executed directly, not via `sh -c`. This prevents injection via backticks, `$()`, pipes to unexpected commands, etc.
- **Timeout enforced.** Every command has a configurable timeout (default: 30 seconds). Runaway processes are killed.
- **Output is truncated.** Commands that produce more than a configurable limit (default: 10,000 characters) are truncated with a note. This prevents the agent from consuming unbounded context.

Default allowlist in config:

```json
{
  "security": {
    "shell_allowlist": [
      "ls", "cat", "grep", "head", "tail", "wc", "find",
      "sort", "diff", "echo", "date", "python3", "git"
    ],
    "shell_timeout_seconds": 30,
    "shell_max_output_chars": 10000
  }
}
```

Users can extend the allowlist in their config. The docs should include clear guidance: "Adding `curl` is reasonable. Adding `bash` defeats the purpose of the allowlist. Adding `sudo` is never appropriate."

### 6.3 Cron/scheduling design

The cron tool enables two capabilities that users expect from a modern AI agent:

1. **One-shot reminders.** "Remind me in 2 hours to check the build." VeriClaw stores a scheduled task in SQLite, fires it at the right time, and sends the message to Signal (or CLI if active).

2. **Recurring tasks.** "Every morning at 8am, check this URL and tell me if the content has changed." VeriClaw stores the schedule, wakes up on the interval, runs the prompt through the agent loop (which can use tools like `web_fetch` or `shell`), and sends the result.

Implementation:

- Schedules are stored in the SQLite memory database as structured records: `{id, prompt, schedule_type, cron_expression_or_timestamp, channel, last_run, next_run}`.
- A lightweight scheduler thread (Ada task) checks for due tasks every 30 seconds. This is not a full cron daemon — it's a simple poll loop.
- Each scheduled task fires through the normal agent loop with the normal security pipeline. There is no privilege escalation for scheduled tasks.
- Rate limiting applies to scheduled tasks the same as to interactive messages.
- `vericlaw status` shows active scheduled tasks.
- Users can list and cancel scheduled tasks via natural language ("what reminders do I have?" / "cancel the morning check").

### 6.4 System prompt customisation

VeriClaw supports a `~/.vericlaw/system.md` file that gets prepended to the system prompt. This is how users make the agent their own:

```markdown
# My VeriClaw

I'm Eugene. I'm based in Hollington, Staffordshire, UK.
I prefer metric units and Celsius.

I work on hardware and open-source software projects.
My main project is VeriClaw itself.

When I ask you to run code, use Python 3 unless I say otherwise.
Keep responses concise unless I ask for detail.
```

If the file exists, its contents are prepended to the configured `system_prompt`. If it doesn't exist, VeriClaw uses the config system prompt alone. The file is read at startup and on config reload — no restart needed if you edit it.

This is trivial to implement (read a file, concatenate strings) but it's the difference between a generic assistant and one that knows your name, your preferences, and your context from the first message.

### 6.5 Voice message support

Signal users send voice messages constantly — while driving, walking, cooking. If VeriClaw can't process them, it's deaf to a huge portion of how people actually use a phone messenger.

**What this does in plain language:**

You send a voice note on Signal. VeriClaw listens to it, converts your speech to text using a fast online service, then processes your words exactly as if you'd typed them. It replies with text, not a robot voice. You talk, it reads and responds. Simple.

The speech-to-text service is separate from your AI provider. Think of it like this: your AI provider (Anthropic, Gemini, etc.) is VeriClaw's brain — it thinks and responds. The speech-to-text service is VeriClaw's ear — it just converts your voice into words so the brain can read them. You need both, but they're different things and you can choose them independently.

**Recommended setup:** Groq offers a free, fast speech-to-text service that works out of the box. You get a free API key from console.groq.com and VeriClaw handles the rest. A 30-second voice note is transcribed in under a tenth of a second. Most users will never need anything else.

**Other options:** If you already have an OpenAI API key, that works too — same technology (Whisper), just a different provider. If you're privacy-conscious and don't want audio leaving your machine, you can run a local Whisper model, though it's slower and requires downloading a model file. If your company runs its own transcription server, VeriClaw can point at that instead. Any service that speaks the OpenAI-compatible audio transcription API format works.

**Architecture:**

- The presage bridge receives a voice message attachment (OGG/Opus format — this is what Signal uses natively).
- It saves the audio to a temp file and signals VeriClaw via the JSON IPC: `{"type": "incoming", "from": "+44...", "body": "", "audio": "/tmp/vericlaw-voice-xxxxx.ogg"}`.
- VeriClaw sends the OGG file directly to the configured transcription endpoint. No format conversion needed — Groq, OpenAI, and all major Whisper-compatible APIs accept OGG natively.
- The transcribed text is processed through the normal agent loop as if the user had typed it.
- VeriClaw replies with text on Signal (not voice). Synthesised voice replies are a v1.1 feature.

**Config:**

```json
{
  "voice": {
    "transcription_url": "https://api.groq.com/openai/v1/audio/transcriptions",
    "transcription_api_key_env": "GROQ_API_KEY",
    "transcription_model": "whisper-large-v3-turbo"
  }
}
```

The config is provider-agnostic — it's just a URL, a key, and a model name. To switch providers:

| Provider | URL | Model | Cost |
|----------|-----|-------|------|
| Groq (recommended) | `https://api.groq.com/openai/v1/audio/transcriptions` | `whisper-large-v3-turbo` | Free (25 MB limit) |
| OpenAI | `https://api.openai.com/v1/audio/transcriptions` | `whisper-1` | $0.006/minute |
| Local (faster-whisper server) | `http://localhost:8000/v1/audio/transcriptions` | `large-v3` | Free, runs on your hardware |

**Fallback when voice is not configured:**

If VeriClaw receives a voice message without a configured transcription endpoint, it replies:

"I received your voice message but can't process audio yet. Please send text instead, or ask me how to set up voice transcription."

**Onboarding:**

Voice setup is an optional step during `vericlaw onboard`. After Signal pairing, onboard asks:

```
[optional] Voice messages
  VeriClaw can transcribe voice notes you send on Signal.
  This requires a speech-to-text service (Groq is free and recommended).
  
  Set up voice transcription now?
  1. Yes, with Groq (free — needs a Groq API key)
  2. Yes, with a different provider (enter URL and key)
  3. Skip for now (you can set this up later)
  > 1

  Get a free API key at: https://console.groq.com/keys
  Enter your Groq API key:
  > gsk_xxxxx
  ✓ Voice transcription enabled — Groq whisper-large-v3-turbo
```

The key design choice: voice setup is **optional during onboard**, not required. VeriClaw works fine without it — you just get a clear message if you send a voice note without it configured. This keeps the happy path fast (six steps, not seven) while making voice easy to add.

### 6.6 Image handling

People photograph error messages, screenshot dashboards, snap whiteboards, and send them to their AI agent. If VeriClaw can't see images, it's missing a core phone use case.

Architecture:

- The presage bridge receives an image attachment (JPEG, PNG, WebP).
- It saves the image and signals VeriClaw via JSON IPC: `{"type": "incoming", "from": "+44...", "body": "what does this say?", "image": "/tmp/vericlaw-img-xxxxx.jpg"}`.
- VeriClaw encodes the image as base64 and includes it in the LLM request using the provider's vision API. Both Anthropic (Claude) and OpenAI-compatible endpoints support image inputs in the messages array.
- The agent processes the image alongside any text the user sent and responds normally.

This covers:

- "What does this error message say?" (photographed screen)
- "Read the text in this image" (OCR)
- "What's in this photo?" (general vision)
- "Is this wiring diagram correct?" (technical images)
- "Summarise this whiteboard" (meeting notes)

No config needed — image handling is on by default if the provider supports vision (Anthropic Claude and most OpenAI-compatible endpoints do). If the provider doesn't support vision, VeriClaw replies: "My current AI provider doesn't support image analysis. Try switching to Anthropic or a vision-capable model."

### 6.7 Heartbeat pattern (documented recipe, not new code)

OpenClaw's heartbeat — the agent waking up proactively to check on things — is one of its most loved features. VeriClaw achieves this through a cron task with a smart meta-prompt. No new code needed; the docs should include this recipe:

```
Set up a recurring task: every day at 7:00am, run this prompt:

"Check the following and message me only if something needs my attention:
1. Any reminders due today
2. Run 'git status' in ~/projects/vericlaw and tell me if there are uncommitted changes
3. Fetch https://news.ycombinator.com and tell me the top 3 stories
4. Check the weather in Hollington, Staffordshire

If nothing needs attention, stay quiet — don't message me."
```

This gives VeriClaw proactive behaviour without a dedicated heartbeat subsystem. The agent decides whether to reach out based on what it finds, using the tools it already has (cron, shell, web_fetch, memory).

The docs should include 3-4 heartbeat recipes for common patterns: morning briefing, project status check, URL monitoring, and accountability check-in.

### 6.8 Session export

`/export` in chat mode (or `vericlaw chat --export <session-id>`) writes the current or specified session to a markdown file in the workspace:

```
~/vericlaw-workspace/exports/session-2026-03-10-143022.md
```

The export includes the full conversation with timestamps, tool calls and results, and any facts stored during the session. This is useful for record-keeping, sharing conversations, and debugging.

### 6.9 What still moves to `future/tools/`

| Tool | Return milestone |
|------|-----------------|
| `git` (dedicated, beyond shell allowlist) | v1.1 |
| `brave_search` | v1.2 |
| `browser` | v1.3 |
| `spawn` / `delegate` (sub-agents) | v1.3 |
| Email integration (IMAP / Gmail API) | v1.1 |
| Calendar integration (CalDAV / Google Calendar API) | v1.1 |
| Voice reply / TTS (synthesised voice responses) | v1.1 |

---

## 7. README rewrite guidance

The current README describes a project that doesn't exist yet as a shippable product. The new README should describe what VeriClaw actually is and does today.

### Structure

```
# VeriClaw

One-paragraph description: what it is, what makes it different.

## What makes VeriClaw different

3-4 sentences about SPARK-verified security. Link to SECURITY.md
for the proof details. No feature laundry lists.

## Quick start

  curl -fsSL https://vericlaw.dev/install.sh | sh
  vericlaw onboard
  vericlaw chat

## Supported providers

Anthropic (Claude) natively, plus any OpenAI-compatible endpoint
(Azure AI Foundry, Google Gemini, Ollama, OpenRouter, Groq, DeepSeek, etc.)

## Deploy on Raspberry Pi 4

Brief instructions or link to docs/pi-deployment.md.

## Security

What's proven, what's not. Link to docs/security-proofs.md.

## Roadmap

Brief, honest list of what's coming next.

## License

Resolve and state clearly: MIT or GPL v3 with commercial dual-license.
```

No feature comparison tables with 10 channels. No claims about edge-friendly 5.3 MB binaries unless that's been measured on the stripped-down build. No screenshots of an operator console that isn't shipping.

---

## 8. UX review and redesign

The current VeriClaw CLI was designed for a project with 13 commands, 10 channels, a gateway mode, and an operator console. That UX needs to be stripped back to match the v1.0-minimal scope — but more importantly, several design choices need rethinking even beyond scope reduction.

### 8.1 Assessment of the current CLI

**What's good:**

- `vericlaw onboard` as the first-run entry point is the right pattern. OpenClaw, NullClaw, ZeroClaw, and PicoClaw all do this. Users expect a guided setup wizard.
- `vericlaw doctor` as a health check is genuinely useful and should stay.
- Colour-coded output with `--no-color` / `NO_COLOR` support is correct and accessible.
- Slash commands in chat mode (`/help`, `/clear`, `/memory`, `/exit`) are intuitive.

**What's problematic:**

- **Too many top-level commands.** The current 13 commands (`onboard`, `doctor`, `config validate`, `config edit`, `reset`, `chat`, `agent`, `gateway`, `channels login`, `status`, `export`, `update-check`, `version`) present a wall of options to a new user. Most of these are irrelevant to v1.0-minimal and several are redundant even in the full product.
- **`chat` vs `agent` is confusing.** The deep dive describes `chat` as interactive mode and `agent "..."` as one-shot mode. From a user's perspective, these are the same capability with different invocation styles. They should be one command with a flag, not two commands.
- **`config validate` and `config edit` are developer ergonomics pretending to be user commands.** Validation should happen automatically at load time and fail loudly. Editing should be "open the file in your editor" — wrapping `$EDITOR` in a subcommand adds complexity without real value.
- **`channels login --channel whatsapp` exposes internal architecture.** Users shouldn't need to know about "channels" as a concept. They should think "I want to connect Signal" — the fact that Signal is a channel adapter backed by a sidecar is an implementation detail.
- **`gateway` as a top-level command implies two modes of operation** (CLI mode vs gateway mode) which doubles the testing and documentation surface. For v1.0-minimal, there is no gateway mode.
- **The styled banner is unnecessary weight.** ASCII art banners are a common pattern in CLI tools but they push useful information below the fold. A clean one-line version identifier is better.
- **`/edit N` in chat mode is over-engineered.** Editing the Nth message in history is a power-user feature that adds complexity to the conversation state machine. Cut it for v1.0-minimal.

### 8.2 Redesigned command surface for v1.0-minimal

The goal: a new user should be able to discover every command by running `vericlaw` with no arguments and reading the output in under 10 seconds.

```
$ vericlaw

VeriClaw v1.0.0 — AI agent with formally verified security

Usage:
  vericlaw onboard          Set up VeriClaw for the first time
  vericlaw doctor            Check that everything is working
  vericlaw chat              Start VeriClaw (CLI + Signal)
  vericlaw chat --local      Start VeriClaw (CLI only, no Signal)
  vericlaw status            Show current configuration and health
  vericlaw version           Show version and build info
  vericlaw help <command>    Show detailed help for a command

Options:
  --no-color                 Disable colour output
  --config <path>            Use a specific config file
```

That's **five commands** plus help and a flag. Signal isn't a separate command — it starts automatically with `vericlaw chat`. The user who just wants local CLI mode uses `--local`.

Here's the rationale for each cut:

| Removed command | Why |
|----------------|-----|
| `config validate` | Validation runs automatically when any command loads config. Bad config = immediate error with clear message. No separate command needed. |
| `config edit` | Tell users the path (`~/.vericlaw/config.json`) and let them use their own editor. Don't wrap `$EDITOR`. |
| `reset` | Dangerous command that shouldn't be one typo away. If someone needs to reset, document the manual steps (`rm -rf ~/.vericlaw`). Bring back as a command in v1.1 with a confirmation prompt. |
| `agent "..."` | Merge into `chat`. Use `vericlaw chat -m "Summarise this repo"` for one-shot mode. One command, two invocation styles. |
| `gateway` | No gateway mode in v1.0-minimal. Returns in v1.3. |
| `channels login` | Signal pairing is handled by `vericlaw onboard`. No separate channel management needed. |
| `export` | Nice-to-have, not ship-critical. Returns in v1.1. |
| `update-check` | Premature. When there's a package manager or auto-update story, this makes sense. For now, users check GitHub Releases. |

### 8.3 Onboarding flow redesign

The current onboard asks the user to pick from multiple providers and channels, then defers Signal setup to a separate command. For v1.0-minimal, the flow should be linear, fully self-contained, and leave the user with a working product at the end:

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

Key design decisions:

- **The user finishes onboard with a fully working product.** There are no "next steps" that are required — only optional commands.
- **Signal bridge is a bundled binary — no provisioning delay.** `vericlaw-signal` ships in the release archive. At step 3, VeriClaw spawns it and initiates the linking flow. No downloads, no JVM startup, no waiting. The presage library handles the Signal protocol natively in Rust.
- **Health check runs as the final onboard step, not as a separate command.** If onboard completes successfully, the system is known-good. `vericlaw doctor` exists for later troubleshooting but is never part of the first-run path.
- **Numbered steps with a known total.** Users can see progress and know when they're done.
- **Validation happens inline.** The API key is tested immediately at step 1, not deferred.
- **Sensible defaults with the option to override.** Workspace path defaults to `~/vericlaw-workspace`; the user can change it but doesn't have to.

### 8.4 Doctor output redesign

`vericlaw doctor` should produce a clean, scannable health report:

```
$ vericlaw doctor

VeriClaw v1.0.0 — system check

  Config         ✓  ~/.vericlaw/config.json (valid)
  Provider       ✓  Anthropic — claude-sonnet-4 (responding)
  Signal         ✓  +447700900000 (linked, bridge running)
  Memory         ✓  SQLite — ~/vericlaw-workspace/memory.db (12 sessions)
  Workspace      ✓  ~/vericlaw-workspace (writable)
  Security       ✓  SPARK proofs — 4/4 packages verified
  Tools          ✓  file, web_fetch, shell, cron (enabled) · export (available)

All checks passed.
```

If something fails:

```
  Signal         ✗  Bridge not responding
                    The Signal bridge process may have stopped.
                    → Run: vericlaw onboard --repair-signal
                    → Or check: docs/troubleshooting.md
```

Design principles:

- **Every line is component + status + detail.** Scannable at a glance.
- **Failures include actionable next steps that stay inside VeriClaw.** Never tell the user to install or run something external.
- **The SPARK proof status is visible in doctor output.** This is the differentiator; show it proudly.
- **No banner, no ASCII art, no decorative output.** Every line communicates information.

### 8.5 Chat mode redesign

The interactive chat mode should feel lightweight and fast:

```
$ vericlaw chat

VeriClaw v1.0.0 — type /help for commands, /exit to quit

you> Hello, what can you do?

vericlaw> I'm VeriClaw, a security-first AI assistant. I can help you
with questions, run commands in your workspace, fetch web content,
set reminders, and process voice messages and images. What would you
like to work on?

you> /help

  /help       Show this message
  /clear      Clear conversation history
  /memory     Show what I remember from past sessions
  /export     Save this conversation to a markdown file
  /exit       End the chat

you> /exit
```

Changes from current design:

- **No styled banner.** One line with version and hint about `/help`.
- **`/edit N` removed.** Comes back in v1.1 if there's actual user demand.
- **Prompt is `you>` and `vericlaw>`.** Clear, minimal, obvious who is speaking. Not `[User]` or `[Assistant]` — those feel like a demo. Not `>` alone — that's ambiguous.
- **Streaming output.** Text appears token-by-token in CLI mode. This is a must for perceived responsiveness. If the Anthropic streaming integration isn't working end-to-end, fix it before shipping.

### 8.6 Signal UX considerations

Signal is not a CLI. The UX constraints are completely different:

- **Messages are short.** Nobody sends a 500-word message on Signal. Responses should default to concise, with the option to expand ("Want me to go into more detail?").
- **No slash commands.** Signal users shouldn't need to learn a command syntax. Natural language only. The agent should recognise intent from phrases like "what do you remember" (equivalent to `/memory`) and "start fresh" (equivalent to `/clear`).
- **Voice messages work.** Users send a voice note, VeriClaw transcribes it via Whisper (API or local) and processes it as text. The reply comes back as text, not synthesised audio. This is the natural phone interaction — speak when your hands are busy, read the answer when you're ready. Voice reply (TTS) is a v1.1 feature.
- **Images work.** Users send a photo, VeriClaw forwards it to the LLM vision endpoint alongside any text caption. "What does this error say?", "Read the text in this", "Is this wiring diagram right?" — these are core phone use cases. If the provider doesn't support vision, VeriClaw says so plainly.
- **Response time matters more than response length.** A fast short acknowledgement ("Working on it...") followed by the full response is better than silence for 10 seconds followed by a wall of text.
- **Rich formatting is limited.** Signal supports basic markdown (bold, italic, monospace) but not tables, headers, or complex formatting. Responses must be formatted for plain text readability.
- **Error messages must be human-readable.** If the provider is down or the rate limit is hit, the user gets "I'm having trouble connecting to my AI provider right now. Try again in a moment." — not a stack trace or error code.
- **First message from a new user should explain what VeriClaw is and can do.** Don't assume context. A brief "Hi! I'm VeriClaw, your AI assistant. I can help with questions, run commands, handle voice and images, set reminders, and look things up online. What do you need?" on first contact.

### 8.7 Error UX principles

Every error in VeriClaw should follow this pattern:

```
✗  [What happened]
   [Why it happened, in one sentence]
   → [What to do about it]
```

Examples:

```
✗  Cannot connect to Anthropic API
   The API key in your config may be invalid or expired.
   → Run: vericlaw onboard (to re-enter your key)
   → Or check: https://console.anthropic.com/settings/keys

✗  Signal bridge not responding
   VeriClaw manages the Signal bridge automatically, but it may need re-pairing.
   → Run: vericlaw onboard --repair-signal

✗  Config file not found
   Expected config at ~/.vericlaw/config.json
   → Run: vericlaw onboard (to create one)
```

Never show raw exception text. Never show Ada exception traces to end users. Catch everything at the boundary and translate to human language.

### 8.8 UX items to move to `future/`

| Feature | Current state | Returns at |
|---------|-------------|------------|
| Styled ASCII banner | Exists in CLI | v1.1 (optional, behind a flag) |
| `/edit N` command | Documented | v1.1 |
| `config edit` command | Documented | v1.1 (if users ask for it) |
| `reset` command | Documented | v1.1 (with confirmation prompt) |
| `update-check` command | Documented | v1.2 (with real update mechanism) |
| Gateway boot status panel | Documented | v1.3 |
| Operator console browser UI | Exists in `operator-console/` | v1.3 |
| Multi-channel status display | Documented | v1.3 |

---

## 9. CI/CD simplification

### 9.1 What the pipeline does for v1.0-minimal

1. **Build (Ada)** — `alr build` on Ubuntu (x86_64 and aarch64 cross-compile) + macOS (arm64, x86_64 via CI runner or cross-compile)
2. **Build (Rust)** — `cargo build --release` in `vericlaw-signal/` for all targets (linux-x86_64, linux-aarch64, macos-arm64, macos-x86_64, all musl/static where applicable)
3. **Prove** — `make prove` on all must-prove SPARK packages. Fails the pipeline if any proof regresses.
4. **Test** — `make test` runs AUnit tests for agent loop, provider adapters, channel adapter, memory, and security packages. Rust tests run via `cargo test` in `vericlaw-signal/`.
5. **Lint** — Warnings-as-errors, GNAT style checks. `cargo clippy` for Rust.
6. **Release** — On tag: build release archives for all targets, publish SHA256 checksums, create GitHub Release, update `install.sh` latest version pointer.

That's five steps. No AFL++ fuzzing (move to v1.1), no CodeQL (move to v1.1), no Trivy container scanning (move to v1.2 when Docker deployment is a real path), no competitive benchmarking, no supply-chain verification, no package-manager publishing.

### 9.2 What moves to `future/ci/`

- Fuzzing workflows
- CodeQL analysis
- Trivy scanning
- Homebrew/Scoop/APT publishing
- Competitive benchmark gates
- Conformance suite
- Supply-chain verification scripts

---

## 10. Configuration simplification

### 10.1 v1.0-minimal config.json

Anthropic example (default after onboard):

```json
{
  "agent_name": "VeriClaw",
  "system_prompt": "You are VeriClaw, a security-first AI assistant.",
  "provider": {
    "kind": "anthropic",
    "api_key_env": "ANTHROPIC_API_KEY",
    "model": "claude-sonnet-4-20250514"
  },
  "channels": [
    { "kind": "cli", "enabled": true },
    { "kind": "signal", "enabled": true, "phone": "+44..." }
  ],
  "tools": {
    "file": true,
    "web_fetch": true,
    "shell": true,
    "cron": true
  },
  "memory": {
    "max_history": 50,
    "facts_enabled": true
  },
  "security": {
    "allowlist": ["+44..."],
    "rate_limit_per_minute": 10,
    "workspace": "~/vericlaw-workspace",
    "shell_allowlist": [
      "ls", "cat", "grep", "head", "tail", "wc", "find",
      "sort", "diff", "echo", "date", "python3", "git"
    ],
    "shell_timeout_seconds": 30,
    "shell_max_output_chars": 10000
  }
}
```

OpenAI-compatible example (Azure AI Foundry, Gemini, Ollama, etc.):

```json
{
  "agent_name": "VeriClaw",
  "system_prompt": "You are VeriClaw, a security-first AI assistant.",
  "provider": {
    "kind": "openai-compatible",
    "base_url": "https://your-resource.openai.azure.com/openai/deployments/gpt-4o",
    "api_key_env": "AZURE_API_KEY",
    "model": "gpt-4o",
    "extra_headers": {
      "api-version": "2024-12-01-preview"
    }
  }
}
```

Ollama local example:

```json
{
  "provider": {
    "kind": "openai-compatible",
    "base_url": "http://localhost:11434/v1",
    "api_key": "ollama",
    "model": "llama3.2:3b"
  }
}
```

Note: `provider` is singular, not `providers[]`. No failover chain. No gateway bind config. No bridge URLs. No metrics endpoints.

---

## 11. License resolution

The deep dive document says MIT. Previous work referenced GPL v3 with commercial dual-licensing. These are fundamentally different strategies and it needs to be resolved before shipping.

**Recommendation:** MIT. Here's why:

- Every competitor (OpenClaw, ZeroClaw, NullClaw, PicoClaw) is MIT.
- GPL v3 discourages corporate adoption and contribution.
- The dual-license commercial model requires enforcement resources that a solo developer doesn't have.
- VeriClaw's moat is the SPARK proofs, not the license. Even if someone forks it, they need the Ada/SPARK expertise to maintain the proofs. That's a high barrier.

If there's a strong reason for GPL v3, document it. Otherwise, standardise on MIT and move on.

---

## 12. Deployment: the Pi 4 showcase

### 12.1 Why the Pi 4

- Reinforces the "native, small, edge-friendly" identity
- Security-conscious users often want to run infrastructure on hardware they physically control
- Concrete, photographable deployment — good for blog posts and demos
- ~£40-50, already owned by many in the target audience

### 12.2 Minimal deployment recipe

```
1. Download release binary for aarch64
   wget https://github.com/vericlaw/vericlaw/releases/latest/download/vericlaw-linux-aarch64.tar.gz
   tar xf vericlaw-linux-aarch64.tar.gz
2. Run onboard
   ./vericlaw onboard
   (API key → Signal number → QR code pairing → workspace → health check → done)
3. Install as a service (optional)
   sudo ./vericlaw service install
   (writes systemd unit, enables on boot)
```

**Three steps.** The user does not install signal-cli, does not install Node.js, does not run Docker, does not edit config files, does not set up a JVM. The release binary contains everything. `vericlaw service install` writes its own systemd unit file and enables itself — the user doesn't write unit files either.

Create `docs/pi-deployment.md` with this exact walkthrough, tested and verified.

### 12.3 Azure VM as development environment

Continue using the Azure Ubuntu VM for development and CI. The Pi is the deployment showcase, not the dev environment. Keep using Termius on iOS for SSH into Azure as the mobile development workflow.

---

## 13. Install script

### 13.1 One-line install

The fastest path to a working VeriClaw should be:

```bash
curl -fsSL https://vericlaw.dev/install.sh | sh
```

Or from GitHub directly:

```bash
curl -fsSL https://raw.githubusercontent.com/vericlaw/vericlaw/main/install.sh | sh
```

After the script completes, the user runs `vericlaw onboard` and they're done.

### 13.2 What the script does

1. **Detects OS and architecture.** Supports Linux (x86_64, aarch64) and macOS (arm64, x86_64). Fails with a clear message on unsupported platforms (Windows — point them to the GitHub Releases page for manual download).
2. **Downloads the correct release archive** from GitHub Releases. Uses the latest release tag. Verifies the download with a SHA256 checksum published alongside the release.
3. **Extracts the binaries** (`vericlaw` and `vericlaw-signal`) to a sensible location — `~/.vericlaw/bin/` by default, or `/usr/local/bin/` if run with `sudo`.
4. **Adds the install directory to `$PATH`** by appending to `~/.bashrc`, `~/.zshrc`, or `~/.profile` (whichever exists). Tells the user to restart their shell or `source` the file.
5. **Prints the next step:** `Run: vericlaw onboard`

The script does not run `onboard` itself. Installation and setup are two separate actions — the user should see the install succeed before committing to configuration.

### 13.3 What the script does NOT do

- Does not require `sudo` (installs to user directory by default).
- Does not install a JVM, Node.js, Docker, or any other runtime.
- Does not modify system files beyond `$PATH` configuration.
- Does not phone home, track analytics, or send telemetry.
- Does not auto-update. Updates are manual: run the install script again or download a new release.

### 13.4 Script design principles

- **The entire script should be readable in under 2 minutes.** Keep it short — under 100 lines. No dependency on Python, Ruby, or anything beyond POSIX sh, `curl`, `tar`, and `uname`.
- **Every action is logged to the terminal.** The user sees what's happening at each step.
- **Failures are clear.** If `curl` isn't available, if the architecture isn't supported, if the checksum doesn't match — say exactly what went wrong and what to do about it.
- **Respect `VERICLAW_INSTALL_DIR` for custom install locations.** Power users may want to install elsewhere.
- **The script itself is committed to the repo** at `install.sh` in the root. It's versioned alongside the project.

### 13.5 macOS support implications

Adding macOS to the install script means the CI pipeline needs to produce three release targets:

| Target | Binary | Notes |
|--------|--------|-------|
| `linux-x86_64` | `vericlaw` + `vericlaw-signal` | Primary development and server target |
| `linux-aarch64` | `vericlaw` + `vericlaw-signal` | Pi 4 and ARM servers |
| `macos-universal` | `vericlaw` + `vericlaw-signal` | macOS arm64 + x86_64 fat binary, or separate builds |

The Ada binary cross-compiles via Alire. The Rust binary cross-compiles trivially for all three targets. macOS fat binaries can be produced with `lipo` if needed, or ship separate `macos-arm64` and `macos-x86_64` archives and let the install script pick the right one.

macOS doesn't have `systemd`, so `vericlaw service install` would need a `launchd` plist — but that's a v1.1 concern. For v1.0-minimal on macOS, users just run `vericlaw chat` manually or set up their own launch agent.

---

## 14. Milestones after v1.0-minimal

| Version | Target | What's added |
|---------|--------|-------------|
| v1.0-minimal | **Ship day** | CLI + Signal + Anthropic + OpenAI-compatible + shell (allowlisted) + cron + file + web_fetch + voice transcription + image handling + system.md + session export + SPARK proofs + SQLite memory + install script + Pi/macOS deployment |
| v1.1 | +2 weeks | Telegram channel, email integration (IMAP/Gmail), calendar integration (CalDAV/Google Calendar), voice reply (TTS), dedicated git tool, vector memory, context compaction, macOS launchd service |
| v1.2 | +4 weeks | Brave search tool, sandbox module, fuzzing in CI, dedicated named provider adapters (OpenAI, Gemini, Azure) |
| v1.3 | +8 weeks | HTTP gateway mode, operator console, Docker Compose multi-service, metrics/observability, browser bridge |
| v2.0 | +16 weeks | Multi-channel gateway, sub-agents, MCP support, package manager distribution, skills/plugin system |

Each milestone has a clear definition of done. Nothing moves from `future/` back into `src/` without tests, documentation, and (where applicable) SPARK proofs.

---

## 15. What success looks like

After executing this plan, VeriClaw is:

- **Three steps to working product** — curl, onboard, chat. No external dependencies. No Docker. No npm. No JVM. Everything is baked in.
- **Actually useful from day one** — shell execution (allowlisted), scheduled tasks, file operations, web fetching, session export, and a personalised system prompt make VeriClaw a real working agent, not a demo
- **Honestly scoped** — the README describes exactly what it does, no more
- **Provably secure** — SECURITY.md lists packages with passing GNATprove results, not aspirations
- **Competitively positioned** — the only agent runtime with formal verification, targeting security-conscious users on the most trusted secure messenger
- **Ready to grow** — clean interfaces for providers, channels, and tools make it straightforward to bring `future/` components back in on a planned schedule

The project stops feeling heavy because it stops *being* heavy. Everything that isn't the core value proposition is preserved but removed from the critical path. What ships is small, real, and defensible.

---

## Appendix A: Decision log

| Decision | Rationale |
|----------|-----------|
| Everything baked in, zero external dependencies | The user starts and finishes in the CLI. No sidecar installs, no Docker, no JVM, no npm. Onboard handles provisioning. This is the single most important UX decision. |
| Signal bridge via presage (Rust) companion binary | A thin Rust binary (~300 lines) using the presage library replaces signal-cli. No JVM. Compiles to ~5-10 MB static binary. Starts instantly, cross-compiles to aarch64 trivially. VeriClaw spawns it as a managed child process with JSON-over-stdin/stdout IPC. Total release archive stays under 15 MB. |
| Static linking for SQLite and HTTP | The release binary must run on a fresh Linux install with no `apt install` step. Zero runtime dependencies beyond libc. |
| Onboard includes health check as final step | The user should never need to run `doctor` on the happy path. If onboard succeeds, the system works. `doctor` is for troubleshooting later. |
| `vericlaw chat` starts Signal automatically | Signal is not a separate mode. It's always on unless `--local` is passed. One command starts everything. |
| Signal as sole channel | Security alignment, open source, differentiates from competitors' "all channels" approach |
| Anthropic + OpenAI-compatible (two providers) | Anthropic as first-class native implementation; OpenAI-compatible as a generic adapter that immediately covers Azure AI Foundry, Gemini, Ollama, OpenRouter, Groq, DeepSeek, and dozens more. Two implementations, not five. |
| Install script (`curl \| sh`) | Standard pattern for CLI tools. Detects OS/arch, downloads correct binary, adds to PATH. Under 100 lines, POSIX sh only. User never leaves the terminal. |
| macOS support in v1.0 | Install script and CI produce Linux (x86_64, aarch64) and macOS (arm64, x86_64) builds. Rust and Ada both cross-compile for all targets. |
| MIT license (recommended) | Matches all competitors, enables adoption, SPARK expertise is the real moat |
| `future/` directory instead of deletion | Preserves all existing work, clear path to re-integration, no git history damage |
| Four must-prove packages | Minimum credible set for "formally verified security" claim |
| Pi 4 as showcase target | Physical ownership narrative, photographable, affordable, reinforces edge-native identity |
| No gateway mode in v1.0 | Removes the entire HTTP/API/metrics surface and its maintenance burden |
| Five tools (file, web_fetch, shell, cron, export) | Shell with allowlist is what makes it an agent not a chatbot. Cron enables proactive behaviour (reminders, recurring checks). Export is small and expected. All security-reviewed via SPARK allowlist policy. |
| Shell allowlist in SPARK security core | The allowlist check is formally verified, not a string comparison in app code. This is VeriClaw's answer to OpenClaw's "anything goes" shell access. |
| System prompt via ~/.vericlaw/system.md | Trivial to implement (read file, prepend). Transforms a generic assistant into the user's personalised agent. Every competitor has this. |
| Voice message transcription via Whisper | Provider-agnostic OpenAI-compatible transcription endpoint. Groq recommended as default (free, fast, accepts OGG natively). No format conversion, no ffmpeg dependency. Voice setup is optional during onboard. Fallback reply: "please send text instead." |
| Image handling via LLM vision API | Core phone use case — photographed errors, screenshots, whiteboards. Both Anthropic and OpenAI-compatible endpoints support vision. No new tool needed, just pass the image to the provider. |
| Heartbeat as a documented cron recipe, not new code | Achieves the same proactive behaviour as OpenClaw's heartbeat using existing cron + tools. A smart meta-prompt decides whether to message the user. Zero engineering cost, just good docs. |
| Email and calendar deferred to v1.1 | Each requires OAuth flows and substantial integration surface. High value but not achievable for day-one ship. |
| Six CLI commands (not thirteen) | New users should read the full help in 10 seconds; every command removed is cognitive load removed |
| Merge `agent` into `chat -m` | One capability, one command, two invocation styles — not two commands |
| Signal UX: no slash commands | Messaging users expect natural language, not CLI syntax; intent recognition handles `/memory` and `/clear` equivalents |
| Inline validation in onboard | Don't defer failures to `doctor`; validate API keys and Signal pairing immediately so the user knows setup worked |
| Error format: what / why / do | Every error must be actionable; raw exceptions never reach the user |

## Appendix B: Resolved decisions and remaining questions

### Resolved

**Signal bridge strategy: presage Rust companion binary (Option C)**

The Signal integration uses a thin Rust binary built on the presage library (whisperfish/presage), which implements the Signal protocol in pure Rust via libsignal-service-rs. This binary is called `vericlaw-signal` and is bundled in the release archive alongside the main VeriClaw Ada binary.

Architecture:
- `vericlaw-signal` is ~300 lines of Rust wrapping presage's `Manager` struct.
- It links as a secondary Signal device (like Signal Desktop), not a registered phone.
- Communication with the VeriClaw Ada process is via JSON-over-stdin/stdout (simple, no sockets, no HTTP, no port allocation).
- VeriClaw spawns it as a child process and manages its lifecycle (start, health check, restart on crash) via Ada tasks.
- presage uses SQLite for its own protocol state, stored in `~/.vericlaw/signal/` — separate from VeriClaw's memory database.

Why this over alternatives:
- signal-cli (Java) requires bundling a JVM: ~40 MB archive size, ~100+ MB runtime memory. Kills the "small native binary" story.
- GraalVM native compilation of signal-cli is experimental and broken on aarch64.
- libsignal C FFI directly from Ada is months of engineering work.
- presage compiles to a ~5-10 MB static Rust binary with instant startup and trivial aarch64 cross-compilation.

Risks to monitor:
- presage's API is explicitly marked unstable. Pin to a specific git commit and test on every update.
- presage is community-maintained (Whisperfish team), not official Signal. It may lag behind protocol changes.
- Signal could break unofficial clients at any time (though they haven't targeted presage/whisperfish so far).

Build requirements:
- Rust toolchain added to CI for building `vericlaw-signal`. This is the only Rust component in the project.
- Cross-compilation targets: `x86_64-unknown-linux-gnu` and `aarch64-unknown-linux-gnu` (musl for fully static builds).
- The Rust binary is built separately and placed into the release archive alongside the Ada binary. The Ada build does not depend on Rust.

Release archive contents:
```
vericlaw-linux-aarch64.tar.gz
├── vericlaw              (~5 MB, Ada binary, statically linked)
├── vericlaw-signal       (~5-10 MB, Rust binary, statically linked)
└── README.txt            (quick-start: run ./vericlaw onboard)
```

Total estimated archive size: **10-15 MB** (competitive with ZeroClaw's 3.4 MB core, far smaller than signal-cli + JRE at ~50 MB).

### Remaining questions

1. **Do the four must-prove SPARK packages currently pass GNATprove?** If not, this is job one. Everything else is secondary.
2. **Can all Ada native dependencies be statically linked?** SQLite and any TLS library must be statically linked for the zero-dependency promise. Verify the Alire/GNAT build can produce a fully static binary on both x86_64 and aarch64.
3. **Is the config schema validated at load time?** If not, add it. A bad config should fail loudly, not silently misbehave.
4. **What is the Anthropic provider's streaming behaviour?** Does it work end-to-end in CLI mode? Does it degrade gracefully when streaming isn't available?
5. **Does the terminal rendering handle non-ASCII cleanly?** The tick/cross symbols (✓/✗) in doctor output need to work in common terminal emulators on Linux (Pi) and macOS. Test in Termius on iOS as well, since that's part of the dev workflow.
6. **Does presage support QR code generation for device linking?** The presage example CLI opens a PNG image for QR scanning. For a headless/SSH use case, VeriClaw needs to render the QR code as UTF-8 block characters in the terminal. Verify this works in Termius on iOS over SSH.
7. **What happens when the user sends a message while the agent is already processing one?** Define the queuing/rejection behaviour for Signal messages. A simple "I'm still working on your last request" acknowledgement is better than silent queueing or dropped messages.
8. **What is the JSON-over-stdin/stdout IPC protocol between VeriClaw and vericlaw-signal?** Define the message format now — it should be minimal. Incoming messages: `{"type": "incoming", "from": "+44...", "body": "...", "image": null, "audio": null}`. Image and audio fields carry temp file paths when attachments are present. Outgoing: `{"type": "send", "to": "+44...", "body": "..."}`. Keep it simple enough that it could be reimplemented for any future channel bridge.
9. **What is the presage version/commit to pin to?** Check the latest presage release, verify it compiles and links as a secondary device successfully on both x86_64 and aarch64, and pin that commit in the build.
10. **Does presage handle voice and image attachments?** **Resolved: Yes.** Presage lists "fetch, decrypt and store attachments" as a feature. The purple-presage Pidgin plugin confirms sending and receiving attachments works. Signal voice notes (OGG/Opus) and images (JPEG/PNG) are standard attachments that presage decrypts and makes available as raw bytes. No blocker.
11. **Which Whisper endpoint to recommend as default?** **Resolved: Provider-agnostic with Groq as documented default.** The implementation accepts any OpenAI-compatible `/v1/audio/transcriptions` endpoint. Groq is recommended in docs and onboarding because it's free, fast (~300x real-time), and accepts OGG natively — no format conversion needed. Users can swap in OpenAI, a local faster-whisper server, or any compatible endpoint by changing the URL. Voice setup is optional during onboard — VeriClaw works without it and gives a clear "please send text instead" reply if a voice note arrives without transcription configured.
