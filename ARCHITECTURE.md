# VeriClaw Architecture — v0.3.0

## Overview

VeriClaw is a formally-verified Ada/SPARK AI agent runtime. The security core carries SPARK Silver-level proofs, giving mathematically guaranteed absence of runtime errors in the allowlist, rate limiting, secrets, and audit packages. Everything else is standard Ada: type-safe, but not formally proved.

---

## Layer Model

```
┌───────────────────────────────────────────────────────────────────────┐
│  Layer 3 — Rust Companion Binary                                      │
│  vericlaw-signal   (Signal protocol via presage, JSON IPC)            │
└─────────────────────────────┬─────────────────────────────────────────┘
                              │ JSON over stdin/stdout
┌─────────────────────────────▼─────────────────────────────────────────┐
│  Layer 2 — Ada Runtime  (type-safe, not formally verified)            │
│  agent/   channels/   signal/   providers/   tools/   memory/         │
│  config/  terminal/   http/     logging      build_info               │
└─────────────────────────────┬─────────────────────────────────────────┘
                              │ Ada package calls
┌─────────────────────────────▼─────────────────────────────────────────┐
│  Layer 1 — SPARK Security Core  (GNATprove Silver level)              │
│  security-policy   security-secrets   security-audit                  │
│  channels-security   gateway-auth                                     │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Layer 1: SPARK Security Core

All packages live at `src/` root level and are compiled with GNATprove at Silver level (`--level=2`). Every security decision that can be proved, is proved.

| Package | Responsibility |
|---------|---------------|
| `security-policy` | Allowlist decisions. Deny-by-default total functions. |
| `security-secrets` | Secret handle lifecycle — zeroed after use, encrypted at rest. |
| `security-audit` | Every security decision logged. Audit trail cannot be silently dropped. |
| `channels-security` | Per-session rate limiting. No integer overflow. Monotonic state transitions. |
| `gateway-auth` | Token validation and pairing codes (v1.1: gateway mode). |

---

## Layer 2: Ada Runtime

Standard Ada. Calls into Layer 1 for all security decisions and never bypasses them.

### Agent subsystem (`src/agent/`)

| Package | Responsibility |
|---------|---------------|
| `agent-loop_pkg` | Main select loop; orchestrates tool calls. |
| `agent-context` | Conversation context window management. |
| `agent-blackboard` | Shared mutable state between agent and tools. |
| `agent-tools` | Tool dispatch table. |
| `agent-orchestrator` | Multi-step planning. |

### Channels (`src/channels/`)

| Package | Responsibility |
|---------|---------------|
| `channels-cli` | Interactive terminal input/output. |
| `channels-signal` | Signal IM via `vericlaw-signal` subprocess IPC. |
| `channels-bridge_polling` | Common polling logic shared by channel implementations. |
| `channels-message_dedup` | Deduplication for Signal at-least-once delivery. |
| `channels-rate_limit` | Per-user rate limiting (wraps `channels-security`). |

### Signal bridge manager (`src/signal/`)

| Package | Responsibility |
|---------|---------------|
| `signal-manager` | Spawns `vericlaw-signal` binary; JSON-over-stdin/stdout IPC; health monitoring; crash restart (max 3). |

### Providers (`src/providers/`)

| Package | Responsibility |
|---------|---------------|
| `providers-anthropic` | Anthropic Claude native client (streaming SSE). |
| `providers-openai_compatible` | Generic OpenAI-compatible client (Azure, Gemini, Ollama, etc.). |
| `providers-interface_pkg` | Common interface type shared by all providers. |

### Tools (`src/tools/`)

| Package | Responsibility |
|---------|---------------|
| `tools-file_io` | Sandboxed file read/write within `~/workspace/`. |
| `tools-shell` | Allowlisted command execution (shell allowlist in `security-policy`). |
| `tools-cron` | Scheduled task management. |

### Memory (`src/memory/`)

| Package | Responsibility |
|---------|---------------|
| `memory-sqlite` | Persistent conversation history via SQLite. |

### Support packages

| Package | Responsibility |
|---------|---------------|
| `src/config/` | Config load, validation, schema. |
| `src/terminal/` | Terminal rendering (colours, progress, QR codes). |
| `src/http/http-client` | HTTP/HTTPS client for provider API calls. |
| `logging.ads/adb` | Structured logging to file. |
| `build_info.ads` | Version constants. |

---

## Layer 3: Rust Companion Binary

`vericlaw-signal/` is a separate compiled binary (`vericlaw-signal`) that handles the Signal protocol via the [presage](https://github.com/whisperfish/presage) library. VeriClaw spawns it as a child process and communicates via JSON over stdin/stdout.

### IPC Protocol

```
Incoming:     {"type":"incoming","from":"+44...","body":"...","image":null,"audio":null}
Outgoing:     {"type":"send","to":"+44...","body":"..."}
Health:       {"type":"ping"} / {"type":"pong"}
Provisioning: {"type":"provision_qr","data":"sgnl://...","text":"▄▄▄..."}
```

---

## Data Flow

```
                                            ┌──────────────────────────────┐
                                            │   SPARK Security Core (L1)   │
                                            │  security-policy             │
                                            │  security-secrets            │
                                            │  security-audit              │
                                            │  channels-security           │
                                            │  gateway-auth                │
                                            └──────────┬───────────────────┘
                                                       │ (all security decisions)
                                                       │
  User (Signal)                                        │
      │                                                │
      ▼                                                │
  vericlaw-signal (Rust) ──stdin/stdout──► signal-manager.adb (Ada)
                                                       │
  User (Terminal) ──────────────────────► channels-cli (Ada)
                                                       │
                                          ┌────────────▼────────────┐
                                          │     agent-loop_pkg      │
                                          │   (agent-context reads/ │
                                          │    writes memory-sqlite)│
                                          └──┬──────────────────────┘
                                             │
                          ┌──────────────────┴──────────────────┐
                          │                                      │
                          ▼                                      ▼
              providers-anthropic               tools-file_io / tools-shell
              providers-openai_compatible        tools-cron
              (streaming SSE / REST)
```

All security decisions — allowlist checks, rate limiting, secret access, audit
logging — flow through the SPARK security core (Layer 1) regardless of which
path the request took to reach the agent.

---

## What's Not in v0.3.0

Telegram, Discord, Slack, WhatsApp, Email, IRC, Matrix, and Mattermost channels are not included, nor are the OpenAI direct and Gemini provider clients, or tools such as git, brave search, browser, spawn/delegate, and MCP. The operator console, gateway mode, and observability stack (OTLP tracing, Prometheus metrics) are also deferred. All of these are preserved in `future/` with documented return milestones for v1.1 and beyond.

---

## Configuration

```json
{
  "agent": { "name": "...", "system_prompt": "..." },
  "provider": {
    "kind": "anthropic",
    "api_key_env": "ANTHROPIC_API_KEY",
    "model": "claude-sonnet-4-20250514"
  },
  "channels": ["cli", "signal"],
  "tools": {
    "enabled": ["file_io", "shell", "cron"],
    "shell": { "allowlist": ["..."] }
  },
  "memory": { "backend": "sqlite", "path": "~/.vericlaw/memory.db" },
  "security": { "audit_log": "~/.vericlaw/audit.log" }
}
```

Configuration is validated at startup. Unknown keys are rejected. Invalid values produce a clear error with a non-zero exit code.

**Precedence:**
```
VERICLAW_CONFIG env var  >  ~/.vericlaw/config.json  >  built-in defaults
```

---

## Build

Ada is compiled with `gprbuild -P vericlaw.gpr`. Rust is compiled with `cargo build --release` inside `vericlaw-signal/`. Both binaries are distributed together.
