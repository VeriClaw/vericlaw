# Changelog

All notable changes are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]
### Added
- Browser/screenshot tool via Puppeteer bridge (port 3007): `browser_browse`, `browser_screenshot`
- Vector RAG memory via sqlite-vec + OpenAI embeddings: `memory_search` tool
- Structured JSON logging package (`Logging`) with thread-safe protected mutex
- RAII `Memory_Handle` via `Ada.Finalization.Limited_Controlled`
- Live gateway API: `/api/status`, `/api/channels`, `/api/metrics/summary`
- Operator console wired to live gateway with Connect UI
- Warnings-as-errors CI gate (`warnings-gate` job, currently `continue-on-error: true`)
- Supply chain CI job (SBOM + provenance generation and verification)
- `make docker-push` and `make docker-push-dry-run` targets

### Added (v1.0.0-rc1 hardening)
- Gateway chat API: `POST /api/chat` (non-streaming) and `POST /api/chat/stream` (SSE)
- Streaming SSE output for Gemini and OpenAI-compatible providers
- `vericlaw status` command (runtime status summary)
- `vericlaw config validate` command (config validation without starting agent)
- `Escape_JSON_String` utility in JSON parser for safe output serialization
- `make fuzz-suite` target for security regression fuzz suite
- Log level filtering via `VERICLAW_LOG_LEVEL` env var (debug/info/warning/error)
- Request ID correlation (`req_id`) in structured log output

### Added (v1.0.0-rc2 features)
- `--json` flag for machine-readable output on `agent` and `status` commands
- `--no-color` flag with auto-detection for pipes; respects `NO_COLOR` env var
- `vericlaw export --session <id> --format md|json` conversation export command
- Multimodal image input: `[IMAGE:path]` / `[IMAGE:url]` markers in user messages
- Base64 encoding for local images, MIME type detection (JPEG, PNG, GIF, WebP)
- OpenAI and Anthropic providers serialize multimodal content for vision APIs
- Plugin loader (`Plugins.Loader`): discovers `manifest.json` in plugins directory
- Plugin capability verification via SPARK-proved `Plugins.Capabilities` policy
- Graceful SIGTERM/SIGINT shutdown with clean memory and gateway teardown
- Security headers on all gateway responses: `X-Content-Type-Options`, `X-Frame-Options`, `Cache-Control`
- `.env.example` with all required environment variables documented
- `alire.toml` manifest for reproducible Ada dependency resolution
- REST API reference documentation (`docs/api.md`)
- Bridge test suites for all 8 Node.js sidecars (health, validation, error handling)
- CI: SPARK proof job, fuzz suite job, integration test job, bridge npm audit + test job
- Package lockfiles for all 8 bridge sidecars

### Security (v1.0.0-rc2)
- WhatsApp example config: changed `bind_host` from `0.0.0.0` to `127.0.0.1`
- docker-compose.yml: secret env vars now use `:?` (fail-fast) instead of `:-` (empty default)
- Gateway HTTP responses include security headers (nosniff, DENY, no-store)
- SECURITY.md updated with all hardening measures
- ARCHITECTURE.md updated with browser-bridge, /api/chat, config validation

### Security
- MCP bridge: bearer token auth, rate limiting (100 req/min), tool allowlist validation
- Browser bridge: removed `--single-process`, added `--disable-extensions`/`--disable-background-networking`, bound to 127.0.0.1, URL scheme validation (http/https only)
- Config loader: input validation for all URLs, strings, API keys (reject control chars, javascript: URIs)
- Channels: all 5 bridge-polling channels now use SPARK-proved `Channels.Security.Allowlist_Allows`
- SPARK proofs upgraded from flow analysis (level 1) to Silver (level 2) for runtime error proofs
- Fixed silent exception swallowing in main.adb — now uses structured logging

## [0.2.0] - 2026-02-27
### Added
- Slack channel via Socket Mode bridge
- Discord channel via Gateway bridge
- Email channel via IMAP/SMTP bridge
- IRC channel via irc-bridge
- Matrix channel via matrix-bridge
- Google Gemini provider (gemini-2.0-flash default)
- Groq, Ollama, OpenRouter via openai_compatible
- Streaming SSE token output for OpenAI + Anthropic in CLI mode
- MCP (Model Context Protocol) client via mcp-bridge sidecar
- Cron scheduler tools (cron_add, cron_list, cron_remove)
- Spawn/subagent tool for focused sub-conversations
- Git operations tool (9 actions, workspace-scoped)
- Parallel tool execution via Ada task pool
- Prometheus /metrics endpoint
- SIGHUP hot config reload
- Multi-user gateway: operator vs guest memory isolation
- Concurrent multi-channel gateway using Ada tasks
- SQLite WAL mode for concurrent channel access
- Session auto-expiry (configurable, default 30 days)
- Syslog audit forwarding via POSIX openlog/syslog
- SPARK Silver proofs (--level=2) on security core
- Post contract on gateway-auth Advance_Pairing_Status
- MIT LICENSE file
- ARCHITECTURE.md, SECURITY.md, CONTRIBUTING.md, CHANGELOG.md
- Benchmark script (scripts/bench-rss.sh) and docs/benchmarks.md
- Provider guides: docs/providers/groq.md, ollama.md, openrouter.md
- Channel setup guides: docs/setup/slack.md, discord.md, email.md, irc.md, matrix.md, mcp.md
- Secret scan (trufflehog) in CI pipeline; GCOV/LCOV coverage reporting
- `.pre-commit-config.yaml` with shellcheck, trufflehog, detect-secrets
- Constrained subtypes: RPS_Limit, Token_Count, Timeout_Ms, Port_Number, Depth_Limit, History_Limit
- Tool name allowlist with Pre contract on Agent.Tools.Dispatch (prompt injection defence)
- `coverage` build profile in vericlaw.gpr (--coverage, -fprofile-arcs)

### Fixed
- Silent exception swallowing in streaming SSE callbacks now increments Metrics counter
- node_modules for all bridge sidecars added to .gitignore
- All runtime/IO packages annotated with pragma SPARK_Mode(Off) for explicit boundary
- Magic number literals replaced with named constants in cron and Telegram packages
- Compiler flags: -gnatwa (all warnings), -gnatyy (style), -gnato (overflow), -fstack-protector-strong
## [0.1.0] - 2026-02-25
### Added
- Initial release: CLI chat, Telegram, Signal, WhatsApp channels
- OpenAI, Anthropic, Azure AI Foundry, OpenAI-compatible providers
- SQLite memory with FTS5 + facts store
- SPARK-verified security core (flow analysis level 1)
- Multi-provider failover
- Agent tools: file I/O, shell, web_fetch, Brave Search
- Interactive onboard wizard
- Prometheus /metrics (initial)
- docker-compose.yml with wa-bridge
- Multi-arch Docker images (amd64/arm64/arm/v7)
- Systemd/launchd/Windows service packaging
