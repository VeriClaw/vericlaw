# VeriClaw

**Formally verified AI runtime. 5 MB binary. 10 channels. Zero trust compromises.**

[![CI](https://github.com/VeriClaw/vericlaw/actions/workflows/ci.yml/badge.svg)](https://github.com/VeriClaw/vericlaw/actions/workflows/ci.yml)
[![Release](https://github.com/VeriClaw/vericlaw/actions/workflows/publish.yml/badge.svg)](https://github.com/VeriClaw/vericlaw/actions/workflows/publish.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Ada/SPARK](https://img.shields.io/badge/Ada%2FSPARK-2022-orange.svg)](https://www.adacore.com/about-spark)

> [!NOTE]
> **VeriClaw is in active development (v0.2.0-dev).** Core runtime, CLI, and multi-platform
> builds are functional. APIs and config formats may still change. See the
> [changelog](CHANGELOG.md) for what shipped recently.

VeriClaw is a **security-first, edge-friendly AI assistant runtime** written in
Ada/SPARK — the only agent runtime in its class with **formally verified security
policies**. It runs your AI assistant across 10 messaging channels simultaneously,
routes between 5 LLM provider families with automatic failover, and ships as a
single static binary under 6 MB with a **polished, colored CLI**.

---

## Why VeriClaw?

| Feature | **VeriClaw** | ZeroClaw | NullClaw | OpenClaw |
|---|---|---|---|---|
| Language | Ada/SPARK | Rust | Zig | TypeScript |
| Formal verification | **✅ SPARK Silver** | ❌ | ❌ | ❌ |
| Binary size | **5.3 MB** | 8.8 MB | 0.66 MB | N/A |
| Container image | **37.1 MB** ✨ | 42 MB | 48 MB | — |
| LLM providers | 5 families | 12+ | 22+ | 15+ |
| Channels | 10 | 25+ | 17 | 40+ |
| Streaming output | ✅ | ✅ | ✅ | ✅ |
| MCP client | ✅ | ✅ | ❌ | ✅ |
| Cron scheduler | ✅ | ❌ | ❌ | ✅ |
| Parallel tool calls | ✅ Ada tasks | ✅ Tokio | ❌ | ✅ |
| Provably correct security | **✅** | ❌ | ❌ | ❌ |

> VeriClaw's differentiator is **provable security**: SPARK Silver proofs guarantee absence of
> runtime errors in the auth, secrets, audit, and policy modules. No other claw-type runtime
> offers formal verification at this level.

---

## Quick Start

### 1. Install

```bash
# Requires Alire (Ada package manager)
curl -L https://alire.ada.dev/install.sh | bash
git clone https://github.com/vericlaw/vericlaw && cd vericlaw
alr build -- -XBUILD_PROFILE=release
```

Or with Docker:
```bash
docker build -f Dockerfile.release -t vericlaw .
```

> 📦 See [docs/installation.md](docs/installation.md) for Homebrew, Scoop, APT,
> Docker, Raspberry Pi, and all platform options.

### 2. Configure

```bash
vericlaw onboard    # interactive wizard — asks for provider, API key, model, channel
```

Or create `~/.vericlaw/config.json` manually
([example](config/config.example.json)):

### 3. Run

```bash
vericlaw chat                           # interactive CLI conversation
vericlaw agent "Summarise today's news" # one-shot mode
vericlaw gateway                        # start all channels concurrently
vericlaw doctor                         # verify config and connectivity
```

> [!TIP]
> All CLI output is **color-coded** — green ✓ for success, red ✗ for failures.
> Use `--no-color` to disable.

---

## Features

### 🔒 Security (Formally Verified)
SPARK Silver proofs on auth, secrets, audit, and channel policy. Fail-closed
defaults — empty allowlist denies all. Encrypted secrets (ChaCha20-Poly1305).
Tamper-evident audit log with syslog forwarding. Workspace isolation with
path-traversal blocking proved in SPARK. → [SECURITY.md](SECURITY.md)

### 🤖 LLM Providers (5 Families)
OpenAI, Anthropic, Azure AI Foundry, Google Gemini, and any OpenAI-compatible
endpoint (Ollama, Groq, OpenRouter, LiteLLM, LM Studio). Multi-provider routing
with ordered primary → failover → long-tail fallback. Streaming always-on in CLI.
→ [docs/providers.md](docs/providers.md)

> [!TIP]
> **Provider Aliases** — 9 OpenAI-compatible presets (Groq, Mistral, DeepSeek,
> xAI, OpenRouter, Perplexity, Together, Fireworks, Cerebras) auto-fill base URL
> and defaults in `vericlaw onboard`.

### 💬 Channels (10, Concurrent)
CLI, Telegram, Signal, WhatsApp, Slack, Discord, Email (IMAP/SMTP), IRC, Matrix,
and Mattermost — all run simultaneously in `gateway` mode via Ada tasks.
Multi-user support with operator/guest memory isolation.
→ [docs/channels.md](docs/channels.md)

### 🛠️ Tools (13 Built-in + MCP)
File I/O, shell, web fetch, Brave Search, git ops, cron scheduler, sub-agent
spawn, role delegation, browser screenshot, vector RAG, plugin registry — plus
unlimited tools via MCP. → [docs/tools.md](docs/tools.md)

### 🧠 Memory & State
SQLite with FTS5 full-text search + persistent facts store. Vector RAG memory
via sqlite-vec embeddings. Session auto-expiry. WAL mode for safe concurrent
multi-channel writes. Context compaction for long sessions.

### 🖼️ Multimodal Input
`[IMAGE:path]` and `[IMAGE:url]` markers for vision APIs (OpenAI, Anthropic,
Gemini). Auto MIME detection. Up to 4 images per message.

### 📊 Operations
Prometheus `/metrics` endpoint. `SIGHUP` hot config reload. Structured JSON
logging with request correlation. Live gateway REST API. Operator web console.
Systemd / launchd / Windows service packaging.
→ [docs/operations.md](docs/operations.md)

### 🎨 CLI Experience
Styled terminal output with ANSI colors and ASCII banner. Interactive chat with
`/help`, `/clear`, `/memory`, `/edit` commands. Gateway boot panel shows
all-at-a-glance system status. First-run welcome guides new users to
`vericlaw onboard`. Respects `--no-color` and `NO_COLOR` convention.

> [!TIP]
> `vericlaw doctor` runs a **connectivity test** for every configured provider
> and channel — each check prints ✓ or ✗ with round-trip latency in ms.

---

## Documentation

| Guide | Description |
|-------|-------------|
| **[Getting Started](docs/getting-started.md)** | Install → onboard → doctor → chat journey |
| **[Installation](docs/installation.md)** | All install methods — source, Docker, Homebrew, Scoop, RPi |
| **[Providers](docs/providers.md)** | LLM provider setup and multi-provider routing |
| **[Channels](docs/channels.md)** | Channel configuration and multi-user gateway |
| **[Tools](docs/tools.md)** | Tool reference — built-in tools + MCP extensibility |
| **[Operations](docs/operations.md)** | Monitoring, logging, deployment, service packaging |
| **[Testing & CI](docs/testing.md)** | Tests, build profiles, CI pipeline, gate commands |
| **[HTTP API](docs/api.md)** | Gateway REST API reference |
| **[Benchmarks](docs/benchmarks.md)** | Performance comparison methodology and results |
| **[Architecture](ARCHITECTURE.md)** | 3-layer system design |
| **[Security](SECURITY.md)** | Threat model, controls, operator checklist |
| **[Contributing](CONTRIBUTING.md)** | PR process, coding standards, SPARK requirements |
| **[Changelog](CHANGELOG.md)** | Release notes |

> 📚 Full documentation index: [docs/README.md](docs/README.md)

---

## Project Structure

```
vericlaw/
├── src/                          # Ada/SPARK source
│   ├── security-*.ads/adb       #   SPARK-verified security core
│   ├── agent/                   #   Reasoning loop, provider routing
│   ├── channels/                #   10 channel implementations
│   │   └── channels-mattermost.ads/adb
│   ├── config/                  #   Configuration & onboard wizard
│   │   └── config-provider_aliases.ads/adb
│   ├── providers/               #   5 LLM provider families
│   ├── memory/                  #   SQLite WAL + FTS5 + vector RAG
│   ├── http/                    #   libcurl + gateway server
│   ├── tools/                   #   13 built-in tools
│   └── terminal/                #   ANSI colors, banner, themed output
├── wa-bridge/                    # WhatsApp sidecar (Baileys)
├── slack-bridge/                 # Slack Socket Mode sidecar
├── discord-bridge/               # Discord Gateway sidecar
├── email-bridge/                 # IMAP/SMTP sidecar
├── mcp-bridge/                   # MCP client proxy
├── irc-bridge/                   # IRC sidecar
├── matrix-bridge/                # Matrix sidecar
├── tests/                        # SPARK policy + runtime unit tests
├── config/                       # Example configs for every channel
├── docs/                         # Full documentation suite
├── deploy/                       # systemd, launchd, Windows service
├── operator-console/             # Local web dashboard
├── docker-compose.yml            # Full stack
└── Makefile                      # All build, test, and release targets
```

> See [ARCHITECTURE.md](ARCHITECTURE.md) for the 3-layer security model and data flow.

---

## Benchmarks

Measured via Docker container on linux/amd64 (50 iterations):

| Metric | **VeriClaw** | ZeroClaw (Rust) | NullClaw (Zig) |
|---|---:|---:|---:|
| Binary size | **5.31 MB** | 8.80 MB | 0.66 MB |
| Container image | **37.1 MB** ✨ | 42.0 MB | 48.0 MB |
| Startup (QEMU)* | 139 ms | 10 ms | 8 ms |
| Dispatch p95 (QEMU)* | 192 ms | 13.4 ms | 14 ms |
| Throughput (QEMU)* | 7.2 ops/s | 80 ops/s | 78 ops/s |

> \*QEMU x86_64 emulation on ARM host — binary/container sizes are
> apples-to-apples. See [docs/benchmarks.md](docs/benchmarks.md).

**VeriClaw wins on container footprint** (37.1 MB) and binary size (5.3 vs
8.8 MB). See [docs/benchmarks.md](docs/benchmarks.md) for full methodology.

---

## CLI Commands

```bash
vericlaw onboard                        # interactive setup wizard
vericlaw doctor                         # connectivity checks (✓/✗ + latency)
vericlaw chat                           # interactive CLI (/help for commands)
vericlaw agent "..."                    # one-shot agent mode
vericlaw gateway                        # multi-channel daemon (boot panel)
vericlaw status [--json]                # runtime status summary
vericlaw version | help                 # version info / all commands
```

> Use `--no-color` or `NO_COLOR=1` to disable ANSI colors.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for coding standards, SPARK requirements,
and PR process. Run `make validate` to build + prove + test.

## License

[MIT](LICENSE)
