# future/

This directory preserves components that are not part of the v1.0-minimal release.

Nothing here is deleted. Every component is preserved with a README explaining what it does and which milestone brings it back into `src/`.

## Return schedule

| Directory | What it contains | Returns at |
|-----------|-----------------|------------|
| `bridges/` | Node.js protocol bridge sidecars (WhatsApp, Slack, Discord, Email, IRC, Matrix, MCP, Browser) | v1.1–v1.3 (per channel) |
| `channels/` | Ada channel adapters: Telegram, Discord, Slack, WhatsApp, Email, IRC, Matrix, Mattermost | v1.1+ |
| `providers/` | Named provider adapters (OpenAI, Gemini) and failover routing | v1.1–v1.2 |
| `tools/` | git (dedicated), brave_search, browser, spawn/delegate sub-agents, MCP | v1.1–v1.3 |
| `memory/` | Vector memory (sqlite-vec), context compaction | v1.1 |
| `gateway/` | HTTP gateway server, gateway-mode Ada packages, plugins, runtime executor | v1.3 |
| `observability/` | Distributed tracing (OTLP), Prometheus metrics | v1.3 |
| `sandbox/` | Process sandboxing module | v1.2 |
| `operator-console/` | React-based web UI for gateway mode | v1.3 |
| `deploy/` | macOS launchd, Windows service, full Docker Compose | v1.1–v1.3 |
| `packaging/` | Homebrew formula, Scoop manifest, Winget manifest, APT/nfpm | v1.2 |
| `ci/` | AFL++ fuzzing, CodeQL, Trivy, supply-chain verification, benchmark gates | v1.1–v1.2 |

## Milestone definitions

- **v1.0-minimal** — CLI + Signal + Anthropic/OpenAI-compatible + 5 tools + SPARK proofs + install.sh + Pi/macOS deployment
- **v1.1** — Telegram, email integration, calendar, voice reply (TTS), dedicated git tool, vector memory, context compaction, macOS launchd service
- **v1.2** — Brave search, sandbox module, fuzzing in CI, dedicated named provider adapters
- **v1.3** — HTTP gateway mode, operator console, Docker Compose multi-service, metrics/observability, browser bridge
- **v2.0** — Multi-channel gateway, sub-agents, MCP support, package manager distribution

## How to bring something back

1. Move the relevant directory back into `src/` (or the appropriate location)
2. Add it to `vericlaw.gpr` source dirs
3. Write or verify tests in `tests/`
4. Add documentation in `docs/`
5. If it's a security-critical component, add SPARK proofs before merging
6. Update `ARCHITECTURE.md` and `CHANGELOG.md`
