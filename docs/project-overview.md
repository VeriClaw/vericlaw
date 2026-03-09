# VeriClaw Project Overview

## Snapshot

- **Project**: VeriClaw
- **Current release line**: `v0.2.0`
- **Local source build version**: `0.2.0-dev` until CI stamps release metadata
- **Status**: late-stage development, not yet production-ready
- **Core differentiator**: security-first AI agent runtime written in Ada/SPARK with a formally verified security core

VeriClaw is being built as a serious competitor to projects such as OpenClaw, ZeroClaw, NullClaw, IronClaw, TinyClaw, PicoClaw, and NanoBot. Its strategic advantage is not raw integration count alone; it is the combination of native performance, multi-channel agent runtime features, and a provable security boundary around the most sensitive parts of the system.

## What VeriClaw Is

VeriClaw is an edge-friendly AI assistant runtime for running agents across local CLI sessions, chat channels, and sidecar-connected protocols. It combines:

- a **SPARK-verified security core** for auth, allowlists, secrets, audit, and policy,
- a **native Ada runtime** for agent execution, tool dispatch, memory, providers, and HTTP APIs,
- and **Node.js sidecars** for bridge protocols and browser-powered integrations.

In practice, VeriClaw is both:

- a **single-user local agent** you can use from the CLI, and
- a **gateway runtime** that can serve multiple channels concurrently with isolated memory and operational controls.

## Architecture

VeriClaw uses a three-layer architecture.

### Layer 1 - SPARK security core

Security-critical decisions live here and are formally verified at SPARK Silver level or flow-analysis level depending on the package.

- `channels-security`
- `gateway-auth`
- `security-policy`
- `security-secrets`
- `security-audit`
- `channels-adapters-*`

### Layer 2 - Ada runtime

The Ada runtime handles agent orchestration, provider calls, tool execution, memory, HTTP serving, observability, and channel coordination.

- `agent/`
- `channels/`
- `providers/`
- `memory/`
- `tools/`
- `config/`
- `http/`
- `observability/`
- `metrics`

### Layer 3 - Node.js sidecars

Bridge services handle external protocols and browser automation over localhost HTTP APIs.

- `wa-bridge`
- `slack-bridge`
- `discord-bridge`
- `email-bridge`
- `mcp-bridge`
- `irc-bridge`
- `matrix-bridge`
- `browser-bridge`
- `operator-console`

## Current Capabilities

### Runtime and agent behavior

- Native Ada/SPARK runtime with fast startup and low dispatch overhead
- Multi-step agent loop with bounded tool/delegation behavior
- Parallel tool execution via Ada tasks
- Ordered provider routing with **primary -> failover -> long-tail fallback**
- CLI one-shot and interactive chat workflows
- Graceful shutdown on `SIGTERM` and `SIGINT`
- Machine-readable output modes via `--json` and `--no-color`

### Channels

VeriClaw currently supports **9 channels**:

| Channel | Status | Notes |
| --- | --- | --- |
| CLI | Ready | Interactive and one-shot usage |
| Telegram | Ready | Native runtime integration |
| Signal | Ready | Via signal-cli REST bridge |
| WhatsApp | Ready | Via `wa-bridge` |
| Slack | Ready | Via `slack-bridge` |
| Discord | Ready | Via `discord-bridge` |
| Email | Ready | Via `email-bridge` |
| IRC | Ready | Via `irc-bridge` |
| Matrix | Ready | Via `matrix-bridge` |

Additional channel features:

- concurrent gateway mode across enabled channels,
- operator vs guest memory isolation,
- per-channel allowlist and rate-limit enforcement,
- hardened bridge polling and sidecar readiness behavior.

### Providers

VeriClaw currently supports **5 provider families**:

- OpenAI
- Anthropic
- Azure AI Foundry
- Google Gemini
- OpenAI-compatible endpoints such as Ollama, Groq, OpenRouter, LiteLLM, and LM Studio

Provider behavior includes:

- runtime fallback across multiple configured providers,
- CLI streaming for supported providers,
- provider-level timeout and token controls,
- cost and request instrumentation.

### Tools and extensibility

VeriClaw supports built-in tools plus MCP-discovered tools.

#### Built-in tool surface

- File I/O
- Shell execution
- Web fetch
- Brave Search
- Git operations
- Cron scheduler
- Spawn
- Delegate
- Browser browse
- Browser screenshot
- Memory search
- Plugin registry

#### Extensibility

- MCP client integration through `mcp-bridge`
- auto-discovery of external MCP tools at startup
- local plugin manifest discovery
- read-only `plugin_registry` tool for inspecting plugin state
- signed-trusted-key requirement for surfaced local plugin manifests

Important note: local plugin execution is still **discovery-only** today. VeriClaw surfaces trusted manifests but does not yet run arbitrary local plugin code at load time.

### Memory and context

- SQLite-backed persistent memory
- FTS5 full-text search
- facts store
- vector RAG memory via `sqlite-vec`
- configurable session retention
- WAL mode for concurrent access
- configurable in-memory history window
- deterministic context compaction using `memory.compact_at_pct`

Recent memory/runtime improvements include:

- consistent `max_history` validation,
- bounded in-memory history behavior,
- deterministic oldest-turn compaction for long sessions,
- aligned history semantics across config, runtime, and memory export/load.

### HTTP API and operator experience

When running in gateway mode, VeriClaw exposes a localhost API including:

- `GET /api/status`
- `GET /api/channels`
- `GET /api/plugins`
- `GET /api/metrics/summary`
- `POST /api/chat`
- `POST /api/chat/stream`

The operator experience now includes:

- a real browser chat UI in `operator-console/`,
- persisted local session and transcript handling,
- gateway status and metric views,
- plugin inventory visibility,
- transport-mode signaling through `X-VeriClaw-Stream-Mode`.

Important note: the browser/gateway path currently exposes **buffered SSE**, not true chunked token streaming end-to-end.

### Security

This is VeriClaw's strongest differentiator.

- SPARK Silver proofs on core security packages
- flow analysis on the broader security boundary
- fail-closed defaults
- encrypted secrets at rest using ChaCha20-Poly1305
- tamper-evident audit logging
- security headers on HTTP responses
- workspace isolation and path traversal blocking
- explicit logging of previously swallowed failures in key runtime paths
- safer config validation for URLs and string fields

### Observability and operations

- Prometheus metrics
- tracing and OTLP export support
- structured logging
- `doctor` command
- `status` command
- config reload support
- export commands for conversation history
- service packaging for systemd, launchd, and Windows service workflows
- Dockerfiles and compose-based deployment scaffolding
- validation and proof entrypoints via `make validate`, `make prove-host`, and container fallback flows

## Current Positioning

VeriClaw is strongest where **trust, correctness, and runtime discipline** matter most.

### Where VeriClaw is ahead

- formally verified security boundary
- native runtime characteristics
- strong local/gateway hybrid model
- clear security posture and fail-closed defaults
- serious multi-channel architecture without relying on a TypeScript-only core

### Where competitors are still ahead

- broader integration count in some ecosystems
- more polished end-user UX in browser-first products
- more mature public package/distribution availability
- richer extension ecosystems with active third-party plugin execution

## Recent Changelog Highlights

### v0.2.0 - 2026-03-09

- added deterministic context compaction for long sessions
- added runtime provider routing with primary/failover/long-tail behavior
- upgraded the operator console into a real local browser chat client
- made the buffered SSE limitation explicit in the UI and HTTP contract
- tightened config input validation for unsafe strings and URLs
- refreshed versioning and release-facing documentation

### v0.1.1 - 2026-02-27

- expanded channel support with Slack, Discord, Email, IRC, and Matrix
- added Gemini and broader OpenAI-compatible provider support
- added MCP client support, cron tools, spawn/subagent behavior, and parallel tool execution
- added Prometheus metrics, hot reload, multi-user gateway isolation, and SQLite WAL concurrency
- shipped SPARK Silver proofs on the security core and core architecture/security documentation

### v0.1.0 - 2026-03-01

- introduced browser tools, vector memory, structured logging, and live gateway APIs
- added `status`, `config validate`, export commands, and multimodal image input
- improved operational hardening, CI coverage, and packaging support

For line-by-line historical detail, see the root `CHANGELOG.md`.

## Outstanding Tasks

All tracked modernization sprint tasks are currently complete. There are **no open implementation todos in the current tracked sprint**.

The remaining work is now a strategic backlog rather than unfinished execution from the latest modernization pass.

### Highest-priority outstanding work

1. **Ship true chunked streaming end-to-end**
   - The operator console and API contract are ready, but the gateway path still reports `buffered-sse`.
   - Competitors with polished browser UX generally feel more responsive here.

2. **Move plugin support from discovery-only to safe execution**
   - Today the plugin story is honest and secure, but limited.
   - VeriClaw needs a real sandboxed execution model, lifecycle management, and clearer developer ergonomics.

3. **Expand ecosystem breadth**
   - Competitors such as OpenClaw still lead on total integrations.
   - Additional providers, channels, and first-party bridges would improve parity.

4. **Finish public distribution channels**
   - GHCR publish is not yet active.
   - Winget is not yet publicly registered.
   - `get.vericlaw.dev` is not yet live.
   - Homebrew, Scoop, and APT metadata exist but public availability remains to be fully verified.

5. **Broaden production-readiness validation**
   - Full host-side Ada/SPARK build/proof validation should be exercised routinely in environments with the full toolchain.
   - More end-to-end system tests would reduce deployment risk.

6. **Continue operator and onboarding polish**
   - Better runbooks, setup flows, and browser UX would help close the polish gap with browser-first competitors.

7. **Grow competitive differentiation beyond security**
   - VeriClaw already wins on trust.
   - To win overall, it should also lead on usability, integration depth, and production operations.

## Summary

VeriClaw is already a credible, differentiated agent platform: a native multi-channel AI runtime with a formally verified security core, solid operational foundations, and a growing product surface. Its next phase is less about fixing fundamentals and more about finishing the last-mile product work that competitors are strongest at: streaming polish, extension execution, distribution maturity, and broader ecosystem reach.

---

## Capability Inventory (v0.2.0)

This is the authoritative list of implemented, tested capabilities as of the current release.

**CLI commands:** `onboard`, `chat`, `agent "..."`, `gateway`, `config validate`, `doctor`, `status [--json]`, `export --session <id> --format md|json`, `channels login --channel whatsapp`, `version`, `help`

**LLM providers (5):** OpenAI, Anthropic, Azure AI Foundry, Google Gemini, any OpenAI-compatible (Groq, Ollama, OpenRouter, LiteLLM)

**Channels (9, concurrently in gateway mode):** CLI, Telegram, Signal, WhatsApp, Slack, Discord, Email, IRC, Matrix

**Built-in tools (13) + unlimited via MCP:** `file`, `shell`, `web_fetch`, `brave_search`, `git_operations`, `cron_add/list/remove`, `spawn`, `delegate`, `browser_browse`, `browser_screenshot`, `memory_search`, `plugin_registry`

**Runtime and infrastructure:**
- Streaming SSE token output (OpenAI + Anthropic providers)
- Runtime provider routing: stateful primary/failover/long-tail loop
- Multi-provider failover with automatic fallback
- Session expiry auto-prune (configurable, default 30 days)
- Prometheus `/metrics` endpoint — per-channel, per-provider, per-tool counters
- `SIGHUP` hot config reload — update tokens/allowlists without restart
- Multi-user gateway (operator vs guest memory isolation)
- Parallel tool execution (Ada task pool; ordering-sensitive tools run sequentially)
- Cron heartbeat background task
- Syslog audit forwarding (POSIX `openlog`/`syslog`)
- Structured JSON logging (`VERICLAW_LOG_LEVEL` filter, `req_id` correlation)
- Live gateway REST API (`/api/status`, `/api/channels`, `/api/metrics/summary`, `POST /api/chat`, `POST /api/chat/stream`)
- Operator web console with security defaults, channel view, metric totals, and browser chat panel
- Vector RAG memory via `sqlite-vec` + OpenAI `text-embedding-3-small` (or Ollama `nomic-embed-text`)
- Browser/screenshot tool via Puppeteer headless Chromium
- SPARK Silver proofs on security core (GNATprove `--level=2`)
- SQLite WAL mode for safe concurrent multi-channel writes
- Context compaction for long sessions (`memory.compact_at_pct`)
- Config input validation for control characters and unsafe URI schemes
- Multimodal image input via `[IMAGE:path]` / `[IMAGE:url]` markers
- Multi-agent orchestration: role-based delegation with SPARK-proved depth limit
- Conversation branching: `/edit N`, `/branch`, `/branch switch <id>` REPL commands
- Database schema versioning with sequential migration framework
- Plugin loader with SPARK-verified capability policy
- OpenTelemetry OTLP tracing (optional, zero overhead when off)
- LLM cost tracking per provider with token budget enforcement
- Multi-arch Docker publish scaffolding (GHCR, activation pending)
- Systemd / launchd / Windows service packaging
