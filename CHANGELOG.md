# Changelog

All notable changes are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [0.1.0-rc4] — 2026-02-27

### Added
- ARMv7 (32-bit ARM) cross-compilation for Raspberry Pi 2/3/4 (32-bit OS)
- Automated Homebrew tap update on release (pushes to `vericlaw/homebrew-vericlaw`)
- Automated Scoop bucket update on release (pushes to `vericlaw/scoop-vericlaw`)
- nfpm `.deb` and `.rpm` package generation in release pipeline (amd64, arm64, armhf)
- Scoop manifest auto-checksum fetching via `hash.url` + regex
- Raspberry Pi installation guide with model compatibility matrix
- Distribution matrix table showing all OS/arch/method combinations

### Changed
- Homebrew formula: added `bottle :unneeded` (pre-built binaries, no compilation)
- Homebrew formula: added caveats for 32-bit ARM users directing to install.sh
- Build matrix: 6 targets (was 5) — added `linux-armv7` with `arm-linux-gnueabihf`
- Dockerfile.ci: added ARMv7 cross-compiler toolchain
- install.sh: detects `armv7l`/`armhf` architectures
- vericlaw.gpr: added `arm-linux-gnueabihf` to Target_Kind

## [0.2.0] - 2026-03-09

### Added
- Deterministic context compaction for long sessions: `Compact_Oldest_Turn` / `Compaction_Needed` in `Agent.Context`; `memory.compact_at_pct` config key (0 = off, 80 = compact at 80 % full)
- Runtime provider routing module `Gateway.Provider.Runtime_Routing`: `Next_Attempt` / `Mark_Failed` stateful failover loop with primary/failover/long-tail tracking
- Operator console local browser chat panel: sends to `POST /api/chat/stream`, renders full reply on completion
- Operator console transport status pill ("Buffered SSE chat") — honest label noting current AWS gateway buffers the full reply before flushing; UI is ready for chunked SSE once the gateway is updated
- Config input validation: `Validate_String_Field` and `Validate_URL_Field` helpers in `Config.Loader` reject control characters and unsafe URI schemes
- `STYLE_CHECKS` build toggle in `vericlaw.gpr` — `alr build -- -XSTYLE_CHECKS=off` to skip strict style checks during benchmarks
- `--skip-build` flag for `scripts/measure_small_infra.sh`
- Competitive benchmark reports: scorecard, regression gate, direct comparison, and final summary artifacts
- Comprehensive documentation suite: `docs/installation.md`, `docs/providers.md`, `docs/channels.md`, `docs/tools.md`, `docs/operations.md`, `docs/testing.md`, `docs/README.md` navigation hub
- Terminal styling package (`Terminal.Style`): ANSI colors, ASCII art banner, themed output — pure Ada, zero external dependencies
- Colored CLI output: styled prompts, health check symbols (✓/✗), branded headings, semantic colors (success/error/warn)
- `/help` slash command in interactive chat showing all available commands (`/clear`, `/memory`, `/edit N`, `exit`)
- Gateway boot status panel: shows model, memory, active channels, and bind URL on startup
- Onboard wizard confirmations: step-by-step ✓ markers and "Next steps" guidance (doctor → chat → gateway)
- First-run welcome banner with automatic `vericlaw onboard` suggestion when no config exists
- `.env.example` file documenting all Docker Compose environment variables

### Changed
- `memory.compact_at_pct` defaults to `0` (disabled); set to `80` for long-running sessions to keep context within bounds without losing assistant turns
- Operator console description updated to reflect live chat capability
- README.md overhauled: slimmed from 1,081 to ~450 lines; detailed reference content moved to `docs/`
- Binary size reduced to 5.31 MB (from 6.84 MB) via parenthesis aggregate syntax and compiler switch tuning
- Container image size: 37.1 MB (smallest among competitors)
- Help text reorganized into categories (Getting Started / Runtime / Utilities / Flags) with styled output
- Error messages now show red ✗ prefix with actionable recovery suggestions
- SPARK assertion failure message replaced with user-friendly explanation

### Fixed
- Ada compile errors: added `use type Agent.Context.Role` for operator visibility in `http-server.adb`
- 26 indentation/style violations across `http-server.adb`, `config-loader.adb`, `agent-tools.adb`, `gateway-provider-routing.adb`
- Ada 2022 bracket aggregate syntax `[...]` converted to parenthesis `(...)` for GNAT Community 2021 compatibility (20+ files)
- JSON parser API: replaced non-existent `Get_Array_String` with `Value_To_Array`/`Array_Item` pattern in `plugins-loader.adb`
- Memory SQLite body default expression conformance with spec
- Redundant range check warning in `gateway-provider-runtime_routing.adb`
- Added `-gnatwJ` to suppress GNAT 14 obsolescent aggregate warnings (cross-compiler compatibility)

### Security
- All security modules maintain SPARK Silver proof status after syntax changes

## [0.1.0] - 2026-03-01

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
- Gateway chat API: `POST /api/chat` (non-streaming) and `POST /api/chat/stream` (SSE)
- Streaming SSE output for Gemini and OpenAI-compatible providers
- `vericlaw status` command (runtime status summary)
- `vericlaw config validate` command (config validation without starting agent)
- `Escape_JSON_String` utility in JSON parser for safe output serialization
- `make fuzz-suite` target for security regression fuzz suite
- Log level filtering via `VERICLAW_LOG_LEVEL` env var (debug/info/warning/error)
- Request ID correlation (`req_id`) in structured log output
- LLM cost tracking per provider with token budget enforcement (`Metrics.Cost`)
- OpenTelemetry OTLP tracing: optional HTTP/JSON exporter, zero overhead when off
- Multi-agent orchestration: role-based delegation (Researcher/Coder/Reviewer/General)
- Agent blackboard for inter-agent data sharing (`Agent.Blackboard`)
- SPARK-verified delegation depth bounds (`Plugins.Capabilities.Delegation_Allowed`)
- Conversation branching: `/edit N`, `/branch`, `/branch switch <id>` REPL commands
- Database schema versioning with sequential migration framework
- Gateway per-IP rate limiting (120 req/min, configurable)
- Gateway Docker healthcheck in docker-compose.yml
- Configurable `gateway.max_connections` (was hardcoded at 64)
- `make coverage` target for gcov reporting
- `make gateway-integration-test` target (10 assertions, security headers, rate limiting)
- `vericlaw doctor` now performs real health checks (DB, bridges, workspace)
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
- ARMv7 (32-bit ARM) cross-compilation for Raspberry Pi 2/3/4 (32-bit OS)
- Automated Homebrew tap, Scoop bucket, and Docker GHCR image publish on stable release
- nfpm `.deb` and `.rpm` packages for amd64, arm64, armhf

### Fixed
- SQL parameterisation: memory retention DELETE now uses `Bind_Int` (was string concat)
- Log swallowed exceptions: plugins-loader, SSE providers, memory-vector now log errors
- HTTP timeout: distinct `CURLE_OPERATION_TIMEDOUT` error message for smart retry
- Worker task leak: exception handler aborts orphaned tasks during result collection
- launchd plist: `KeepAlive=true`, user-writable log paths in `~/Library/Logs/`

### Security
- MCP bridge: bearer token auth, rate limiting (100 req/min), tool allowlist validation
- Browser bridge: removed `--single-process`, added `--disable-extensions`/`--disable-background-networking`, bound to 127.0.0.1, URL scheme validation (http/https only)
- Config loader: input validation for all URLs, strings, API keys (reject control chars, javascript: URIs)
- Channels: all 5 bridge-polling channels now use SPARK-proved `Channels.Security.Allowlist_Allows`
- SPARK proofs upgraded from flow analysis (level 1) to Silver (level 2) for runtime error proofs
- Fixed silent exception swallowing in main.adb — now uses structured logging
- WhatsApp example config: changed `bind_host` from `0.0.0.0` to `127.0.0.1`
- docker-compose.yml: secret env vars now use `:?` (fail-fast) instead of `:-` (empty default)
- Gateway HTTP responses include security headers (nosniff, DENY, no-store)

## [0.1.1] - 2026-02-27
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
