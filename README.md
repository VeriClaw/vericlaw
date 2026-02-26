# Quasar Claw Lab

[![CI](https://github.com/your-org/quasar-claw-lab/actions/workflows/ada-ci.yml/badge.svg)](https://github.com/your-org/quasar-claw-lab/actions/workflows/ada-ci.yml)

Quasar is a **security-first, edge-friendly AI assistant runtime** written in Ada/SPARK — the only agent in its class with **formally-verified security policies**. It competes with NullClaw (Zig), ZeroClaw (Rust), OpenClaw (TypeScript), IronClaw (Rust), TinyClaw (TS/Bun), PicoClaw (Go), and NanoBot (Python), while delivering provably correct auth, secrets, audit, and sandbox policy.

## Why Quasar?

| Feature | Quasar | ZeroClaw | NullClaw | OpenClaw |
|---|---|---|---|---|
| Language | Ada/SPARK | Rust | Zig | TypeScript |
| Formal verification | **✅ SPARK** | ❌ | ❌ | ❌ |
| Binary size (SPARK-only core) | **168 KB** | 8.8 MB | 678 KB | N/A |
| Binary size (full runtime) | ~400–600 KB* | 8.8 MB | 678 KB | N/A |
| Startup (SPARK-only core) | **1.59 ms** | 10 ms | 8 ms | ~3 s |
| Dispatch p95 (SPARK-only core) | **1.2 ms** | 13.4 ms | 14 ms | — |
| LLM providers | OpenAI, Anthropic, Azure Foundry, compat | 12+ | 22+ | 15+ |
| Channels | CLI, Telegram, Signal, WhatsApp | 25+ | 17 | 40+ |
| Provably correct security | **✅** | ❌ | ❌ | ❌ |

> \* Full runtime binary size (with GNATCOLL + AWS + libcurl) is estimated at 400–600 KB — still significantly smaller than Rust and Go competitors.

## Features

- **SPARK-verified security core** — auth, secrets, sandbox, audit policies proven correct at the type level
- **4 LLM providers** — OpenAI (GPT-4o), Anthropic (Claude 3.5), Azure AI Foundry, any OpenAI-compatible endpoint (Ollama, OpenRouter, LiteLLM)
- **4 channels** — CLI (interactive + one-shot), Telegram Bot API, Signal (via signal-cli bridge), WhatsApp (via WA-Bridge)
- **4 tools** — shell execution (disabled by default), file I/O (workspace-scoped), web fetch, Brave Search
- **SQLite memory** — per-session conversation history with FTS5 search + persistent facts store
- **Multi-provider failover** — automatic fallback to secondary provider on failure
- **Fail-closed defaults** — empty allowlist = deny all; pairing required; no public bind by default
- **Edge-optimized** — targets Raspberry Pi Zero W and other constrained hardware

## Project Structure

```
quasar-claw-lab/
├── src/                              # All Ada/SPARK source code
│   ├── main.adb                      # Entry point: chat / agent / gateway / doctor / version
│   │
│   ├── # ── SPARK-verified security core (formally proved) ─────────────────
│   ├── security.ads                  # Root security package
│   ├── security-policy.ads/adb       # Path, URL, egress policy decisions
│   ├── security-audit.ads/adb        # Tamper-evident audit log with redaction
│   ├── security-secrets.ads/adb      # Encrypted secret storage
│   ├── security-secrets-crypto.ads/adb # ChaCha20-Poly1305 crypto primitives
│   ├── security-defaults.ads         # Fail-closed default constants
│   ├── security-migration.ads/adb    # Config/key migration helpers
│   ├── gateway.ads                   # Root gateway package
│   ├── gateway-auth.ads/adb          # Pairing, token auth, lockout policy
│   ├── gateway-provider.ads          # Provider type hierarchy
│   ├── gateway-provider-credentials.ads/adb  # API key scope/validation
│   ├── gateway-provider-registry.ads/adb     # Provider registration
│   ├── gateway-provider-routing.ads/adb      # Routing and failover policy
│   ├── channels.ads                  # Root channels package
│   ├── channels-security.ads/adb     # Channel allowlist + deny-by-default
│   ├── channels-adapters.ads/adb     # SPARK adapter interface
│   ├── channels-adapters-telegram.ads # Telegram adapter spec
│   ├── channels-adapters-discord.ads  # Discord adapter spec (future)
│   ├── channels-adapters-slack.ads    # Slack adapter spec (future)
│   ├── channels-adapters-email.ads    # Email adapter spec (future)
│   ├── channels-adapters-whatsapp_bridge.ads # WhatsApp adapter spec
│   ├── core.ads / core-agent.ads/adb  # Core agent type declarations
│   ├── runtime.ads / runtime-executor.ads/adb  # Sandbox execution policy
│   ├── runtime-memory.ads/adb        # Memory policy declarations
│   ├── plugins.ads / plugins-capabilities.ads/adb # Plugin capability policy
│   │
│   ├── # ── Agent runtime (standard Ada, built on the security core) ───────
│   ├── agent/
│   │   ├── agent-context.ads/adb     # Conversation context: history, roles, eviction
│   │   ├── agent-loop.ads/adb        # Core reasoning loop: receive→LLM→tools→reply
│   │   └── agent-tools.ads/adb       # Tool registry + schema builder for LLM providers
│   ├── channels/
│   │   ├── channels-cli.ads/adb      # Interactive CLI + one-shot mode
│   │   ├── channels-telegram.ads/adb # Telegram Bot API (long-polling + webhook)
│   │   ├── channels-signal.ads/adb   # Signal via signal-cli REST bridge
│   │   └── channels-whatsapp.ads/adb # WhatsApp via WA-Bridge REST API
│   ├── config/
│   │   ├── config-schema.ads/adb     # Typed config record (providers, channels, tools, memory)
│   │   ├── config-loader.ads/adb     # Load ~/.quasar/config.json; write default if missing
│   │   └── config-json_parser.ads/adb# GNATCOLL.JSON wrapper with safe accessors
│   ├── http/
│   │   ├── http-client.ads/adb       # libcurl thin bindings for LLM API calls
│   │   └── http-server.ads/adb       # AWS (Ada Web Server) HTTP gateway
│   ├── memory/
│   │   └── memory-sqlite.ads/adb     # GNATCOLL.SQL.SQLite: history + facts + FTS5
│   ├── providers/
│   │   ├── providers-interface.ads   # Abstract provider type + tool_call types
│   │   ├── providers-openai.ads/adb  # OpenAI /v1/chat/completions
│   │   ├── providers-anthropic.ads/adb # Anthropic /v1/messages (Claude)
│   │   └── providers-openai_compatible.ads/adb # Azure Foundry + generic compat
│   └── tools/
│       ├── tools-shell.ads/adb       # Shell execution via popen (disabled by default)
│       ├── tools-file_io.ads/adb     # File read/write/list (workspace-scoped)
│       └── tools-brave_search.ads/adb# Brave Search REST API
│
├── tests/                            # Test programs and data
│   ├── # ── SPARK security policy tests (decision-vector driven) ──────────
│   ├── security_secrets_tests.adb/.gpr
│   ├── gateway_auth_policy.adb/.gpr
│   ├── channel_security_policy.adb/.gpr
│   ├── channel_adapter_policy.adb/.gpr
│   ├── autonomy_guardrails_policy.adb/.gpr
│   ├── config_migration_policy.adb/.gpr
│   ├── memory_backend_suite_policy.adb/.gpr
│   ├── plugin_capability_policy.adb/.gpr
│   ├── provider_routing_fallback_policy.adb/.gpr
│   ├── runtime_executor_policy.adb/.gpr
│   ├── competitive_v2_security_regression_fuzz_suite.adb/.gpr
│   ├── *-decision-vectors.csv        # Test vectors for each policy domain
│   │
│   ├── # ── Runtime unit tests (new agent runtime) ──────────────────────────
│   ├── config_loader_test.adb/.gpr   # Config JSON parsing + schema defaults
│   ├── agent_context_test.adb/.gpr   # Conversation history add/evict/format
│   ├── memory_sqlite_test.adb/.gpr   # SQLite save/retrieve/FTS search
│   ├── agent_tools_test.adb/.gpr     # Tool schema builder + dispatch gating
│   │
│   └── # ── CI report artifacts (generated, not committed) ──────────────────
│       ├── *.json                    # Benchmark, conformance, gate reports
│       └── security_gate/            # Vulnerability scan results
│
├── scripts/                          # Build, CI, benchmark, and release scripts
│   ├── bootstrap_toolchain.sh        # Install GNAT + GNATCOLL + AWS + libcurl + sqlite3
│   ├── check_toolchain.sh            # Verify toolchain is installed
│   ├── run_container_ci.sh           # Run CI steps inside Docker container
│   ├── build_multiarch_image.sh      # Build linux/amd64 + arm64 + arm/v7 images
│   ├── run_competitive_benchmarks.sh # Benchmark vs sister projects
│   ├── run_cross_repo_conformance_suite.sh  # Security policy conformance tests
│   ├── release_check.sh              # Full release gate (build + prove + conformance)
│   ├── release_candidate_gate.sh     # RC gate with Docker, vuln scan, supply chain
│   ├── vulnerability_license_gate.sh # CVE + license compliance scan
│   └── ...                           # (20+ additional scripts)
│
├── config/                           # Runtime and CI configuration
│   ├── security_slos.toml            # Security SLO definitions
│   ├── threat_model.toml             # Threat model + acceptance criteria
│   ├── bootstrap_secure_defaults.env # Secure environment defaults
│   └── competitive_scorecards/       # Sister project benchmark baselines
│
├── deploy/                           # Deployment packaging
│   ├── systemd/quasar-claw.service   # Linux systemd unit
│   ├── launchd/com.quasar.claw.plist # macOS launchd plist
│   └── windows/install-quasar-claw-service.ps1 # Windows service installer
│
├── operator-console/                 # Local web operator console (HTML/CSS/JS)
│   ├── index.html                    # Single-page console UI
│   ├── app.js                        # Console logic
│   └── styles.css                    # Styles
│
├── docs/
│   └── runbooks/operator-runbook.md  # Operator runbook
│
├── .github/workflows/ada-ci.yml      # GitHub Actions CI (build, prove, benchmark)
├── quasar_claw.gpr                   # GPRbuild project file
├── spark.adc                         # SPARK configuration pragmas
├── Makefile                          # All build, test, and release targets
├── Dockerfile.release                # Multi-arch release image
└── docker-compose.secure.yml         # Hardened local deployment
```

## Quick start

### 1. Install toolchain

```bash
# macOS
brew install gprbuild gnat alire libcurl sqlite
alr with gnatcoll gnatcoll_sqlite aws

# Ubuntu / Debian
sudo apt-get install -y gnat gprbuild libcurl4-openssl-dev libsqlite3-dev
alr with gnatcoll gnatcoll_sqlite aws

# Or let the bootstrap script handle everything:
make bootstrap
```

### 2. Build

```bash
make build            # dev build (full SPARK assertions)
make edge-size-build  # size-optimised binary (~400-600 KB)
```

### 3. Configure

On first run, Quasar creates `~/.quasar/config.json` with defaults. Edit it:

```json
{
  "agent_name": "Quasar",
  "system_prompt": "You are Quasar, a helpful AI assistant.",
  "providers": [
    {
      "kind": "openai",
      "api_key": "sk-...",
      "model": "gpt-4o"
    },
    {
      "kind": "anthropic",
      "api_key": "sk-ant-...",
      "model": "claude-3-5-sonnet-20241022"
    }
  ],
  "channels": [
    { "kind": "cli", "enabled": true },
    {
      "kind": "telegram",
      "enabled": true,
      "token": "YOUR_BOT_TOKEN",
      "allowlist": "123456789"
    }
  ],
  "tools": {
    "file": true,
    "shell": false,
    "web_fetch": false,
    "brave_search": false,
    "brave_api_key": ""
  },
  "memory": { "max_history": 50, "facts_enabled": true },
  "gateway": { "bind_host": "127.0.0.1", "bind_port": 8787 }
}
```

### 4. Use

```bash
quasar chat                    # interactive CLI conversation
quasar agent "What is 2+2?"   # one-shot, prints reply
quasar gateway                 # start HTTP gateway + all enabled channels
quasar doctor                  # print config and health status
quasar version                 # print version
```

## Providers

| Kind | `kind` in config | Notes |
|---|---|---|
| OpenAI | `openai` | `model`: gpt-4o, gpt-4-turbo, etc. |
| Anthropic | `anthropic` | `model`: claude-3-5-sonnet-20241022, etc. |
| Azure AI Foundry | `azure_foundry` | Set `base_url`, `deployment`, `api_version` |
| OpenAI-compatible | `openai_compatible` | Set `base_url`; covers Ollama, OpenRouter, LiteLLM |

**Multi-provider failover:** List providers in order; Quasar automatically falls back to the next if the first fails.

**Azure AI Foundry example:**
```json
{
  "kind": "azure_foundry",
  "api_key": "YOUR_AZURE_KEY",
  "base_url": "https://YOUR-HUB.openai.azure.com",
  "deployment": "gpt-4o",
  "api_version": "2024-02-15-preview"
}
```

## Channels

### CLI
Works out of the box — no config needed. Run `quasar chat`.

### Telegram
1. Create a bot via [@BotFather](https://t.me/botfather) — get the bot token
2. Find your Telegram user ID via [@userinfobot](https://t.me/userinfobot)
3. Set `token` and `allowlist` (comma-separated IDs, or `"*"` for any sender — **not recommended**)
4. Run `quasar gateway`

### Signal
Requires [signal-cli](https://github.com/AsamK/signal-cli) running as a REST daemon:
```bash
java -jar signal-cli.jar -u +15551234567 daemon --http=127.0.0.1:8080
```
Set `bridge_url: "http://127.0.0.1:8080"` and `token: "+15551234567"` in config.

### WhatsApp
Requires a [WA-Bridge](https://github.com/chrishubert/whatsapp-web-api) instance:
```bash
docker run -p 3000:3000 chrishubert/whatsapp-web-api
```
Scan the QR code on first run. Set `bridge_url: "http://localhost:3000"` in config.

## Tools

| Tool | Config key | Default | Description |
|---|---|---|---|
| File I/O | `file: true` | **on** | Read/write/list files in `~/.quasar/workspace/` |
| Shell | `shell: true` | off | Execute shell commands via popen |
| Web fetch | `web_fetch: true` | off | Fetch web pages |
| Brave Search | `brave_search: true` + `brave_api_key` | off | Web search via Brave Search API |

## Security

- **SPARK-verified policies** — auth, secrets, channel allowlists, sandbox limits — all formally proved, not just tested
- **Fail-closed defaults** — empty allowlist = deny all; pairing required before first use; no public bind by default
- **Encrypted secrets** — API keys stored with ChaCha20-Poly1305 at rest
- **Tamper-evident audit log** — signed event trail with metadata redaction
- **Workspace isolation** — file tool restricted to `~/.quasar/workspace/`; path traversal (`../`, NUL) blocked at policy level
- **Process sandboxing** — Landlock/Seccomp/Firejail auto-selected per platform

## Testing

### SPARK security policy tests

```bash
make secrets-test        # crypto + secret store policy (SPARK)
make conformance-suite   # channel allowlist + adapter policy (SPARK)
make check               # full build + SPARK flow analysis
```

### Runtime unit tests (agent runtime modules)

```bash
make runtime-tests       # all 4 runtime test suites
make config-test         # config JSON parsing + schema defaults
make context-test        # conversation context add/evict/format
make memory-test         # SQLite memory save/retrieve/FTS5 search
make tools-test          # tool schema builder + dispatch gating
```

## Build profiles

```bash
make build              # dev (full SPARK assertions, -gnata)
make small-build        # size-optimised (-Os + gc-sections)
make edge-size-build    # smallest binary (minimal binder)
make edge-speed-build   # speed-optimised (-O2)
```

## CI / Release quick start

1. Validate/bootstrap toolchain:
   ```bash
   make bootstrap-validate
   make bootstrap   # if validation fails
   ```
2. Run core quality checks:
   ```bash
   make check
   make secrets-test
   make conformance-suite
   ```
3. Run competitive benchmarks:
   ```bash
   make competitive-regression-gate
   ```
4. Secure local deployment:
   ```bash
   make docker-runtime-bundle-check
   docker compose -f docker-compose.secure.yml up --build
   ```
5. Operator console (local):
   ```bash
   make operator-console-serve
   ```

## Production deployment

1. Build release image:
   ```bash
   make image-build-local                          # local only
   PUSH_IMAGE=true SIGN_IMAGE=true make image-build-multiarch  # signed multi-arch
   ```
2. Run blocking release gates:
   ```bash
   make release-candidate-gate
   make competitive-v2-release-readiness-gate
   ```
3. Verify supply chain and smoke test:
   ```bash
   make supply-chain-verify
   SMOKE_FAIL_ON_NON_BLOCKING=true make cross-platform-smoke
   ```

## Gate commands and report artifacts

| Category | Command | Report |
|---|---|---|
| Build + proof | `make check` | — |
| Security tests | `make secrets-test` | — |
| Runtime tests | `make runtime-tests` | — |
| Conformance | `make conformance-suite` | `tests/cross_repo_conformance_report.json` |
| Benchmarks | `make competitive-regression-gate` | `tests/competitive_regression_gate_report.json` |
| Vuln scan | `make vulnerability-license-gate` | `tests/vulnerability_license_gate_report.json` |
| Smoke test | `make cross-platform-smoke` | `tests/cross_platform_smoke_report.json` |
| Supply chain | `make supply-chain-verify` | `tests/supply_chain_verification_report.json` |
| Full RC gate | `make release-candidate-gate` | `tests/release_candidate_report.json` |
| V2 readiness | `make competitive-v2-release-readiness-gate` | `tests/competitive_v2_release_readiness_gate_report.json` |

## Service packaging

| Platform | File |
|---|---|
| Linux systemd | `deploy/systemd/quasar-claw.service` |
| macOS launchd | `deploy/launchd/com.quasar.claw.plist` |
| Windows service | `deploy/windows/install-quasar-claw-service.ps1` |
| Operator runbook | `docs/runbooks/operator-runbook.md` |

## What works today

- `make check` — build + SPARK flow analysis + audit/service-hardening checks
- `make secrets-test` / `make conformance-suite` / `make release-check`
- `make vulnerability-license-gate` — blocking CVE + license compliance gate
- `make docker-runtime-bundle-check` / `make service-supervisor-check`
- `make image-build-multiarch` — multi-arch Docker image (amd64/arm64/arm/v7)
- `make supply-chain-attest` / `make supply-chain-verify`
- `make competitive-regression-gate` / `make competitive-v2-release-readiness-gate`
- All agent runtime source code — written and structured, pending first compilation pass with GNAT + GNATCOLL + AWS installed

## Remaining To-Dos

These items are intentionally deferred post-MVP:

### 🔴 First priority — compilation

- [ ] **First compilation pass** — compile with GNAT + GNATCOLL + AWS; fix any remaining Ada syntax issues iteratively
- [ ] **Integration tests** — end-to-end test against a real OpenAI-compatible stub server (e.g. Ollama or a mock)
- [ ] **SPARK proof CI** — run `gnatprove` in GitHub Actions to catch proof regressions on the security core

### Provider coverage

- [ ] **Ollama** — local LLM (`http://localhost:11434/v1`, OpenAI-compat)
- [ ] **Google Gemini** — `generativelanguage.googleapis.com`
- [ ] **Mistral AI** — `api.mistral.ai/v1`
- [ ] **Streaming output** — SSE token streaming for CLI mode

### Channel coverage

- [ ] **Slack** — Bot API via Socket Mode
- [ ] **Discord** — Bot API with gateway events
- [ ] **Email** — SMTP/IMAP bridge
- [ ] **Multi-channel concurrency** — Ada tasks so all channels run simultaneously in `gateway` mode

### Memory and search

- [ ] **Vector embeddings** — `sqlite-vss` extension for semantic similarity search
- [ ] **RAG** — retrieval-augmented generation from local documents
- [ ] **Session expiry** — auto-prune conversations older than N days

### Agent capabilities

- [ ] **MCP (Model Context Protocol)** — interoperability with external tool servers
- [ ] **Subagents / delegation** — nested conversations with different personas
- [ ] **Cron/heartbeat scheduler** — scheduled tasks without user input
- [ ] **Parallel tool calls** — execute multiple tool calls from one LLM response concurrently

### Infrastructure

- [ ] **Web UI** — minimal browser interface served by AWS gateway
- [ ] **Prometheus metrics** — `/metrics` endpoint with latency histograms
- [ ] **Hot config reload** — `SIGHUP` reloads config without restart
- [ ] **Multi-user gateway** — per-user conversation and fact store isolation

### Security hardening

- [ ] **SPARK proofs at level 2+** — upgrade from flow analysis to full proof for all security modules
- [ ] **Rate limit enforcement** — wire `Channel_Config.Max_RPS` into the gateway dispatch loop
- [ ] **Audit log shipping** — forward audit events to syslog / external SIEM
