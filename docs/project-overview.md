# VeriClaw Project Overview

## What VeriClaw Is

VeriClaw is a security-first AI agent runtime written in Ada/SPARK. It runs a personal AI assistant from the command line or over Signal, backed by a formally verified security core.

Its central differentiator is the SPARK proof layer: the auth, allowlist, secrets, and audit packages are formally verified at SPARK Silver level — meaning the absence of buffer overruns, integer overflow, null dereferences, and invalid state transitions in those packages is mathematically proved, not merely tested.

---

## v0.3.0 Scope

v0.3.0 is the first production-eligible release. It is intentionally narrow:

- **2 channels**: CLI (built-in) and Signal (build-verified scaffold; full integration in v1.1)
- **3 providers**: Anthropic (Claude), Azure AI Foundry, and any OpenAI-compatible endpoint (Ollama, Groq, OpenRouter, LiteLLM, Azure OpenAI, etc.)
- **3 tools**: file I/O, shell execution (disabled by default; requires explicit allowlist), and cron scheduler
- **Zero external runtime dependencies**: single static binary; no Node.js, no JVM, no Docker required to run

Everything else — additional channels, gateway mode, operator console, MCP integration, vector memory, Prometheus metrics — is in [`future/`](../future/) with a planned return milestone.

---

## Architecture

VeriClaw uses a two-layer architecture.

### Layer 1 — SPARK security core

Security-critical decisions are formally verified at SPARK Silver level (`--level=2`, GNATprove). These four packages are proved clean:

| Package | What is proved |
|---------|----------------|
| `security-policy` | Allowlist decisions; deny-by-default; path traversal blocked |
| `security-secrets` | Secrets zeroed after use; encrypted-at-rest invariant holds |
| `security-audit` | Every security decision is logged; no silent drops |
| `channels-security` | Rate limiting; no integer overflow; monotonic state transitions |

Run `make prove` to verify the proofs yourself.

### Layer 2 — Ada runtime

The Ada runtime handles agent orchestration, provider calls, tool dispatch, SQLite memory, config loading, and the Signal process lifecycle manager.

| Component | Package |
|-----------|---------|
| Agent loop | `src/agent/` |
| Config | `src/config/` |
| Providers | `src/providers/` (Anthropic, Azure, OpenAI-compatible) |
| Channels | `src/channels/` (CLI, Signal) |
| Signal manager | `src/signal/` (spawns `vericlaw-signal` as child process) |
| Tools | `src/tools/` (file_io, shell, cron) |
| Memory | `src/memory/` (SQLite + FTS5) |
| HTTP client | `src/http/http-client` |

---

## Supported Providers

| Provider | Config `kind` | Notes |
|----------|--------------|-------|
| Anthropic (Claude) | `anthropic` | Streaming SSE supported |
| Azure AI Foundry | `azure_foundry` | Deployment-based endpoint |
| OpenAI-compatible | `openai_compatible` | Ollama, Groq, OpenRouter, LiteLLM, LM Studio, etc. |

The v0.3.0 config uses a single `provider` block. Provider routing and failover are in [`future/providers/`](../future/providers/).

---

## CLI Commands

```
vericlaw onboard          First-time setup wizard
vericlaw chat             Interactive chat (CLI; Signal if configured and linked)
vericlaw chat --local     Interactive chat without Signal
vericlaw doctor           Health check — provider, Signal, memory, SPARK proofs
vericlaw status           Current provider, Signal link status, memory stats
vericlaw config validate  Validate config.json without starting the runtime
vericlaw version          Version and build info
```

---

## Security Posture

- **Fail-closed defaults**: empty allowlist = deny all; shell tool disabled by default
- **Secrets at rest**: ChaCha20-Poly1305 authenticated encryption
- **Tamper-evident audit log**: every security decision is logged; drops are detected
- **TLS**: `SSL_VERIFYPEER=1` + `SSL_VERIFYHOST=2`; TLS 1.2+ enforced
- **Workspace isolation**: file operations restricted to `~/.vericlaw/workspace/`

See [SECURITY.md](../SECURITY.md) and [docs/security-proofs.md](security-proofs.md) for the full threat model and proof details.

---

## What's in `future/`

The [`future/`](../future/) directory contains all functionality outside v0.3.0 scope, preserved for planned return:

| Directory | Return milestone | Contents |
|-----------|-----------------|----------|
| `future/channels/` | v1.1 | Telegram, WhatsApp, Discord, Slack, Email, IRC, Matrix, Mattermost |
| `future/bridges/` | v1.1 | Node.js bridge sidecars for external protocols |
| `future/providers/` | v1.1 | Named OpenAI, Gemini, failover routing |
| `future/tools/` | v1.1 | Git, Brave Search, browser, spawn, MCP |
| `future/gateway/` | v1.3 | HTTP API, multi-user gateway, operator console |
| `future/memory/` | v1.1 | Vector RAG, sqlite-vec |
| `future/observability/` | v1.2 | Prometheus, OTLP tracing |
| `future/deploy/` | v1.2 | Full Docker Compose, launchd, Windows service |
| `future/packaging/` | v1.2 | Homebrew, Scoop, APT, Winget |

See [`future/README.md`](../future/README.md) for the full roadmap.

