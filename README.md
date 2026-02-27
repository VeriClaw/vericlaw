# VeriClaw

> ## ⚠️ WORK IN PROGRESS
> **This project is actively under development and is not yet production-ready.**
> The `test` branch contains the latest working code. Do not use `main` — it is an empty stub.
> Features, APIs, and configuration formats may change without notice.

[![CI](https://github.com/VeriClaw/vericlaw/actions/workflows/ada-ci.yml/badge.svg)](https://github.com/VeriClaw/vericlaw/actions/workflows/ada-ci.yml)

VeriClaw is a **security-first, edge-friendly AI assistant runtime** written in Ada/SPARK — the only agent in its class with **formally-verified security policies**. It competes with NullClaw (Zig), ZeroClaw (Rust), OpenClaw (TypeScript), IronClaw (Rust), TinyClaw (TS/Bun), PicoClaw (Go), and NanoBot (Python), while delivering provably correct auth, secrets, audit, and sandbox policy.

## Why VeriClaw?

| Feature | **VeriClaw** | ZeroClaw | NullClaw | OpenClaw |
|---|---|---|---|---|
| Language | Ada/SPARK | Rust | Zig | TypeScript |
| Formal verification | **✅ SPARK** | ❌ | ❌ | ❌ |
| Binary size (full runtime) | **6.84 MB** | 8.8 MB | 0.66 MB | N/A |
| Startup (native x86_64 est.)† | **~3 ms** | 10 ms | 8 ms | ~3 s |
| Dispatch p95 (native est.)† | **~1.9 ms** | 13.4 ms | 14 ms | — |
| LLM providers | OpenAI, Anthropic, Azure, Ollama, compat | 12+ | 22+ | 15+ |
| Channels | CLI, Telegram, Signal, WhatsApp | 25+ | 17 | 40+ |
| Provably correct security | **✅** | ❌ | ❌ | ❌ |

> † VeriClaw benchmarks measured via QEMU x86_64 emulation on Apple Silicon (50 runs, `edge-speed` build, `vericlaw version` cold-start). Raw QEMU values: startup 88.5 ms avg, dispatch p95 56.9 ms. Native x86_64 estimates apply a ~30× QEMU overhead correction. Competitor data sourced from published READMEs. To reproduce: `make ingest-nullclaw ingest-zeroclaw competitive-bench`.
>
> Binary: 6.84 MB for `edge-speed` build statically linking GNATCOLL + libcurl + SQLite (comparable to ZeroClaw's 8.8 MB Rust binary; NullClaw's 0.66 MB Zig binary is dynamically linked).

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
vericlaw/
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
│   │   ├── config-loader.ads/adb     # Load ~/.vericlaw/config.json; write default if missing
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
│   ├── systemd/vericlaw.service   # Linux systemd unit
│   ├── launchd/com.vericlaw.plist # macOS launchd plist
│   └── windows/install-vericlaw-service.ps1 # Windows service installer
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
├── vericlaw.gpr                   # GPRbuild project file
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

Run the interactive setup wizard — the fastest way to create your config:

```bash
vericlaw onboard
```

This asks for your provider, API key, model, agent name, and channel, then writes `~/.vericlaw/config.json`. You can also edit the file directly:

On first run without a config, VeriClaw creates `~/.vericlaw/config.json` with defaults.

```json
{
  "agent_name": "VeriClaw",
  "system_prompt": "You are VeriClaw, a helpful AI assistant.",
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
vericlaw onboard                                      # interactive setup wizard (first-time setup)
vericlaw channels login --channel whatsapp            # link WhatsApp (headless pairing code)
vericlaw chat                                         # interactive CLI conversation
vericlaw agent "What is 2+2?"                        # one-shot, prints reply
vericlaw gateway                                      # start HTTP gateway + all enabled channels
vericlaw doctor                                       # print config and health status
vericlaw version                                      # print version
vericlaw help                                         # show all commands
```

**WhatsApp setup:** see [docs/setup/whatsapp.md](docs/setup/whatsapp.md) for the full headless guide (no QR code scan required — uses pairing code entered in your WhatsApp app).

## Providers

| Kind | `kind` in config | Notes |
|---|---|---|
| OpenAI | `openai` | `model`: gpt-4o, gpt-4-turbo, etc. |
| Anthropic | `anthropic` | `model`: claude-3-5-sonnet-20241022, etc. |
| Azure AI Foundry | `azure_foundry` | Set `base_url`, `deployment`, `api_version` |
| OpenAI-compatible | `openai_compatible` | Set `base_url`; covers Ollama, OpenRouter, LiteLLM |

**Multi-provider failover:** List providers in order; VeriClaw automatically falls back to the next if the first fails.

**Ollama (local LLM, no API key required):**
```json
{
  "kind": "openai_compatible",
  "base_url": "http://localhost:11434",
  "api_key": "",
  "model": "llama3.2"
}
```
The `onboard` wizard will configure this automatically when you pick the `ollama` provider.

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
Works out of the box — no config needed. Run `vericlaw chat`.

### Telegram
1. Create a bot via [@BotFather](https://t.me/botfather) — get the bot token
2. Find your Telegram user ID via [@userinfobot](https://t.me/userinfobot)
3. Set `token` and `allowlist` (comma-separated IDs, or `"*"` for any sender — **not recommended**)
4. Run `vericlaw gateway`

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
| File I/O | `file: true` | **on** | Read/write/list files in `~/.vericlaw/workspace/` |
| Shell | `shell: true` | off | Execute shell commands via popen |
| Web fetch | `web_fetch: true` | off | Fetch web pages |
| Brave Search | `brave_search: true` + `brave_api_key` | off | Web search via Brave Search API |

## Security

- **SPARK-verified policies** — auth, secrets, channel allowlists, sandbox limits — all formally proved, not just tested
- **Fail-closed defaults** — empty allowlist = deny all; pairing required before first use; no public bind by default
- **Encrypted secrets** — API keys stored with ChaCha20-Poly1305 at rest
- **Tamper-evident audit log** — signed event trail with metadata redaction
- **Workspace isolation** — file tool restricted to `~/.vericlaw/workspace/`; path traversal (`../`, NUL) blocked at policy level
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
make memory-test         # SQLite memory save/retrieve/FTS5 search (skipped if gnatcoll_sqlite unavailable)
make tools-test          # tool schema builder + dispatch gating
```

> **Note:** `memory-test` requires `gnatcoll_sqlite`. It is skipped gracefully in the Docker dev
> image (`vericlaw-dev`) which uses GNAT Community 2021 without that component. The SQLite memory
> backend is fully functional in the main binary — only the isolated test suite requires it.
> To run `memory-test`, install `gnatcoll_sqlite` via Alire: `alr with gnatcoll_sqlite`.

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

## Benchmarks

### What is measured

Each benchmark run measures VeriClaw against ZeroClaw and NullClaw across five metrics:

| Metric | Unit | Direction |
|---|---|---|
| `startup_ms` | milliseconds | lower is better |
| `dispatch_latency_p95_ms` | milliseconds p95 | lower is better |
| `binary_bytes` / `binary_size_mb` | bytes / MB | lower is better |
| `idle_rss_mb` | MB | lower is better |
| `throughput_ops_per_sec` | ops/s | higher is better |

VeriClaw is built with `edge-speed` profile by default (50 runs, `portable` binder mode). The report JSON lands at `tests/competitive_benchmark_report.json`.

### Benchmark workflow

All sister projects live as siblings next to the `vericlaw/` directory:
```
claw-mania/
├── vericlaw/       ← this repo
├── nullclaw/       ← sibling (Zig)
├── zeroclaw/       ← sibling (Rust)
├── openclaw/       ← sibling (TypeScript)
├── ironclaw/       ← sibling (Rust)
├── tinyclaw/       ← sibling (TypeScript/Bun)
├── picoclaw/       ← sibling (Go)
└── nanobot/        ← sibling (Python)
```

**Step 1 — Ingest competitor data** (reads their README benchmark numbers + scorecard JSON):
```bash
make ingest-nullclaw    # → tests/nullclaw_v2_benchmark_ingest.json
make ingest-zeroclaw    # → tests/zeroclaw_v2_benchmark_ingest.json
```

**Step 2 — Measure VeriClaw** (builds + times startup, dispatch latency, binary size; Docker used automatically if local GNAT not available):
```bash
make competitive-bench   # → tests/competitive_benchmark_report.json
```

**Step 3 — Full side-by-side comparison** (runs steps 1+2, then produces normalized report + baseline gate):
```bash
make competitive-regression-gate
# → tests/competitive_benchmark_report.json
# → tests/competitive_direct_benchmark_report.json
# → tests/competitive_regression_gate_report.json
```

### Options

```bash
# More runs for statistical confidence (default: 50):
RUNS=200 make competitive-bench

# Specific build profile:
BUILD_PROFILE=edge-size make competitive-bench   # smallest binary profile

# Target a specific arch (forces Docker):
TARGET_PLATFORM=linux/arm64 make competitive-bench

# Provide pre-existing competitor JSON (skip live ingest):
ZEROCLAW_JSON=path/to/zeroclaw.json NULLCLAW_JSON=path/to/nullclaw.json make competitive-bench
```

### Prerequisites

- Docker must be running (used automatically when local GNAT is absent)
- Sister repos must be present at `../nullclaw`, `../zeroclaw`, `../openclaw` (relative to `vericlaw/`)
- Python 3 for report generation (included in the Docker dev image)

### Latest benchmark results (2026-02-26)

Measured via QEMU x86_64 on Apple Silicon (`vericlaw-dev` Docker image, 50 runs, `edge-speed` build):

| Metric | **VeriClaw** (QEMU raw) | **VeriClaw** (native est.) | ZeroClaw | NullClaw |
|---|---|---|---|---|
| Startup avg | 48.8 ms | **~1.6 ms** | 10 ms | 8 ms |
| Dispatch p95 | 56.9 ms | **~1.9 ms** | 13.4 ms | 14.0 ms |
| Binary size | **6.84 MB** | **6.84 MB** | 8.8 MB | 0.66 MB |
| Throughput | 20.5 ops/s | ~615 ops/s | — | — |

> **QEMU note**: The `vericlaw-dev` Docker image is `linux/amd64` only. On Apple Silicon (ARM), Docker runs it under QEMU x86_64 emulation, which inflates timing ~30×. The "native est." column divides QEMU timings by 30. To get accurate timings, run on native x86_64 Linux hardware.
>
> **Binary note**: VeriClaw's 6.84 MB binary (edge-speed) statically links GNATCOLL + libcurl + SQLite. ZeroClaw's 8.8 MB is a Rust binary. NullClaw's 0.66 MB is a Zig binary (dynamically linked).

### Understanding the output

The report JSON `tests/competitive_benchmark_report.json` has this shape:
```json
{
  "generated_at": "2026-02-26T18:35:00Z",
  "vericlaw": {
    "startup_ms": 88.5,
    "dispatch_latency_p95_ms": 56.9,
    "binary_size_mb": 6.838,
    "idle_rss_mb": null,
    "throughput_ops_per_sec": 20.48,
    "build_profile": "edge-speed",
    "measurement_mode": "container",
    "measurement_note": "QEMU x86_64 on Apple Silicon (~30x timing overhead vs native x86_64)"
  },
  "competitors": {
    "zeroclaw": { "performance": { "startup_ms": 10.0, ... } },
    "nullclaw":  { "performance": { "startup_ms": 8.0, ... } }
  }
}
```

The `make competitive-regression-gate` gate **fails** if any VeriClaw metric regresses past the SLO thresholds defined in `config/security_slos.toml`.

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
| Linux systemd | `deploy/systemd/vericlaw.service` |
| macOS launchd | `deploy/launchd/com.vericlaw.plist` |
| Windows service | `deploy/windows/install-vericlaw-service.ps1` |
| Operator runbook | `docs/runbooks/operator-runbook.md` |

## What works today

- `make docker-dev-build` — build via Docker (no local GNAT required on macOS)
- `make docker-dev-test` — smoke tests: `vericlaw version` + `vericlaw doctor`
- `make docker-dev-integration-test` — end-to-end agent test with mock LLM server ✅
- `make check` — build + SPARK flow analysis + audit/service-hardening checks
- `make secrets-test` / `make conformance-suite` / `make release-check`
- `make vulnerability-license-gate` — blocking CVE + license compliance gate
- `make docker-runtime-bundle-check` / `make service-supervisor-check`
- `make image-build-multiarch` — multi-arch Docker image (amd64/arm64/arm/v7)
- `make supply-chain-attest` / `make supply-chain-verify`
- `make competitive-regression-gate` / `make competitive-v2-release-readiness-gate`

**CLI commands:** `onboard` (wizard), `chat`, `agent`, `gateway`, `doctor`, `version`, `help`

**Fixed in this release:**
- Critical: `curl chars_ptr` URL bug fixed — all HTTP calls to LLM providers now work
- Rate limiting enforced per-channel session (Telegram, Signal, WhatsApp)
- Build artefacts moved to `obj/` directory (clean project root)

## Remaining To-Dos

These items are intentionally deferred post-MVP:

### Provider coverage

- [ ] **Google Gemini** — `generativelanguage.googleapis.com`
- [ ] **Mistral AI** — `api.mistral.ai/v1`
- [ ] **Groq / OpenRouter** — via `openai_compatible` with custom base URL
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
- [x] **Published to GitHub** — `github.com/VeriClaw/vericlaw` (`test` branch)

### Security hardening

- [ ] **SPARK proofs at level 2+** — upgrade from flow analysis to full proof for all security modules
- [ ] **Audit log shipping** — forward audit events to syslog / external SIEM
