# VeriClaw Architecture

## Overview

VeriClaw is a formally-verified Ada/SPARK AI agent runtime. It is the only agent in its class with SPARK Silver proofs on the security core, providing mathematically guaranteed absence of runtime errors in auth, allowlist, rate limiting, secrets, and audit modules.

---

## Layer Model

VeriClaw is structured in three layers, each with a distinct trust level.

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 3 — Node.js Bridge Sidecars                              │
│  wa-bridge  slack-bridge  discord-bridge  email-bridge          │
│  mcp-bridge  irc-bridge  matrix-bridge                         │
└────────────────────────┬────────────────────────────────────────┘
                         │ HTTP REST (localhost)
┌────────────────────────▼────────────────────────────────────────┐
│  Layer 2 — Ada Runtime  (standard Ada, built on security core)  │
│  providers  channels  memory  agent  tools  config  http        │
└────────────────────────┬────────────────────────────────────────┘
                         │ Ada package calls
┌────────────────────────▼────────────────────────────────────────┐
│  Layer 1 — SPARK Security Core  (formally verified)             │
│  channels-security  gateway-auth  security-policy               │
│  security-secrets  security-audit  channels-adapters            │
└─────────────────────────────────────────────────────────────────┘
```

### Layer 1: SPARK Security Core (formally verified)

All policy decisions that affect security live here. Every subprogram has SPARK Flow Analysis proof and Silver-level (--level=2) absence-of-runtime-error proof.

| Package | Role |
|---|---|
| `channels-security` | Channel allowlist + per-session rate limiting |
| `gateway-auth` | Token authentication, pairing flow, lockout policy |
| `security-policy` | Path traversal, URL egress, workspace boundary |
| `security-secrets` / `security-secrets-crypto` | Encrypted secret storage (ChaCha20-Poly1305) |
| `security-audit` | Tamper-evident audit log with redaction |
| `channels-adapters-*` | SPARK adapter specs for Telegram, Slack, Discord, Email, WhatsApp |

### Layer 2: Ada Runtime

Standard Ada code that implements the agent logic. It calls into Layer 1 for all security decisions and never bypasses them.

| Subdirectory / Package | Role |
|---|---|
| `agent/` | Reasoning loop, conversation context, tool dispatch |
| `channels/` | CLI, Telegram, Signal, WhatsApp, Slack, Discord, Email, IRC, Matrix |
| `providers/` | OpenAI, Anthropic, Azure, Gemini, OpenAI-compatible |
| `memory/` | SQLite FTS5 memory, facts store, session expiry |
| `tools/` | file, shell, web_fetch, brave_search, git_operations, cron, spawn |
| `config/` | JSON config parsing, precedence resolution, hot reload |
| `http/` | libcurl TLS wrapper |
| `metrics` | Prometheus counters (per-channel, per-provider, per-tool) |

### Layer 3: Node.js Bridge Sidecars

Eight lightweight Node.js services handle protocol-specific connectivity. Each sidecar exposes a local HTTP REST API consumed by the Ada runtime.

| Sidecar | Protocol | Default Port |
|---|---|---|
| `wa-bridge` | WhatsApp (Baileys) | 3000 |
| `slack-bridge` | Slack Socket Mode | 3001 |
| `discord-bridge` | Discord Gateway | 3002 |
| `email-bridge` | IMAP/SMTP | 3003 |
| `mcp-bridge` | Model Context Protocol | 3004 |
| `irc-bridge` | IRC | 3005 |
| `matrix-bridge` | Matrix | 3006 |
| `browser-bridge` | Puppeteer (page fetch, screenshot) | 3007 |

---

## Data Flow

For a typical chat session:

```
User input
  → Channel (CLI / Telegram / Slack / ...)
  → channels-security (SPARK: allowlist check + rate limit)
  → gateway-auth (SPARK: token validation)
  → agent-loop (Ada: build context, call LLM)
  → Provider (LLM API over TLS via http-client)
  → agent-loop (Ada: parse tool calls)
  → Tool dispatch (parallel Ada task pool)
  → security-policy (SPARK: path / egress / workspace check per tool call)
  → security-audit (SPARK: append audit record)
  → Response assembled
  → Channel → User
```

---

## Module Responsibilities

| Module | Layer | Key Types / Packages | SPARK Coverage |
|---|---|---|---|
| `channels-security` | 1 | `Channel_State`, `Rate_Limit_State` | Silver (level 2) |
| `gateway-auth` | 1 | `Auth_Token`, `Pairing_Status` | Silver (level 2) |
| `security-policy` | 1 | `Path_Decision`, `Egress_Decision` | Silver (level 2) |
| `security-secrets-crypto` | 1 | `Encrypted_Blob` | Silver (level 2) |
| `security-audit` | 1 | `Audit_Entry`, `Redact_Policy` | Flow analysis |
| `channels-adapters-*` | 1 | Adapter spec types | Flow analysis |
| `agent-loop_pkg` | 2 | `Agent_Context`, `Tool_Call` | None (I/O) |
| `agent-tools` | 2 | `Tool_Registry`, `MCP_Tool` | None (I/O) |
| `channels-cli` | 2 | streaming SSE output | None (I/O) |
| `providers-openai` | 2 | HTTP JSON | None (I/O) |
| `runtime-memory` | 2 | SQLite bindings | None (FFI) |
| `http-client` | 2 | libcurl bindings | None (FFI) |

---

## Concurrency Model

- **Gateway mode** spawns one Ada task per active channel. Tasks communicate via protected objects. The gateway HTTP server also exposes:
  - `POST /api/chat` — non-streaming chat (localhost-only, JSON request/response)
  - `POST /api/chat/stream` — SSE streaming chat (localhost-only, server-sent events)
- **Parallel tool execution**: multiple tool calls from a single LLM response run concurrently via an Ada task pool in `agent-loop_pkg`.
- **SQLite WAL mode** allows concurrent reads from multiple channel tasks with a single writer at a time.
- All Ada tasks share the same security core via re-entrant SPARK packages (no shared mutable state in Layer 1).

---

## Security Boundary

```
╔══════════════════════════════════════════╗
║  SPARK-proved boundary (Layer 1)         ║
║                                          ║
║  Is this token valid?          → PROVED  ║
║  Is this path allowed?         → PROVED  ║
║  Is this channel rate-limited? → PROVED  ║
║  Is this secret encrypted?     → PROVED  ║
╚══════════════════════════════════════════╝
         ↕ only via typed Ada interfaces
╔══════════════════════════════════════════╗
║  Ada runtime (Layer 2)                   ║
║                                          ║
║  Which LLM to call?          → Ada logic ║
║  How to format the response? → Ada logic ║
║  Which sidecar port?         → Ada logic ║
╚══════════════════════════════════════════╝
```

Decisions above the boundary are formally proved. Decisions below rely on Ada's strong type system and compiler checks.

---

## External Dependencies

| Dependency | Used by | Purpose |
|---|---|---|
| `libcurl` | `http/` (Ada) | TLS HTTP client (SSL_VERIFYPEER=1, SSL_VERIFYHOST=2) |
| `libsqlite3` | `memory/` (Ada) | Conversation memory, facts, session state |
| `gnatcoll` | Ada runtime | String utilities, JSON, OS bindings |
| `aws` (Ada Web Server) | Ada runtime | HTTP server for `/metrics`, gateway webhooks, and `/api/chat` endpoints |
| Node.js + npm packages | 8 bridge sidecars | Protocol-specific connectivity |

---

## Configuration Precedence

```
VERICLAW_CONFIG env var (path to config file)
  > ~/.vericlaw/config.json
    > built-in defaults
```

All configuration is validated at startup. Unknown keys are rejected. Invalid values produce a clear error message and a non-zero exit code. The config loader also validates URLs, strings, and API keys against injection patterns (e.g., embedded newlines, shell metacharacters) before the runtime accepts them.

---

## CI/CD Pipeline

VeriClaw uses a defense-in-depth CI pipeline with 9 stages:

```
compile ──┬── spark-prove ──────────┬── cross-platform ── hardening-check
          ├── static-analysis       │
          ├── unit-tests ── integration
          ├── fuzz-test (scheduled)
          └── security-scan
```

### Pipeline Stages
1. **Compile** — Strict Ada 2022 with `-gnatwa -gnatwe` (warnings as errors)
2. **SPARK Prove** — Level 2 formal verification (level 4 weekly)
3. **Static Analysis** — GNATcheck rules enforcement
4. **Unit Tests** — GNATcov branch coverage with Codecov integration
5. **Integration Tests** — BBT behavioral specs + gateway integration
6. **Fuzz Testing** — AFL++ QEMU mode (weekly + on-demand)
7. **Security Scan** — Trivy + git-secrets + trufflehog
8. **Cross-Platform** — Linux x86_64/aarch64, macOS Intel/ARM, Windows
9. **Hardening Check** — checksec verification (RELRO, PIE, NX, canary)

### Release Process
Tag-based: `git tag v1.0.0 && git push --tags` triggers:
1. Cross-platform build matrix (5 targets)
2. SHA-256 checksum generation + GPG signing
3. GitHub Release with binaries + checksums
4. Package manager updates (Homebrew, Scoop, APT)

### Runtime Sandboxing
- **Linux**: seccomp BPF filter + AppArmor profile (`deploy/linux/`)
- **macOS**: sandbox-exec profile (`deploy/macos/vericlaw.sb`)
- **Windows**: Restricted token (planned)
