# VeriClaw

> **Active development — `test` branch has all the latest features. `main` is an empty stub.**

[![CI](https://github.com/VeriClaw/vericlaw/actions/workflows/ada-ci.yml/badge.svg)](https://github.com/VeriClaw/vericlaw/actions/workflows/ada-ci.yml)

VeriClaw is a **security-first, edge-friendly AI assistant runtime** written in Ada/SPARK — the only agent in its class with **formally-verified security policies**. It competes with NullClaw (Zig), ZeroClaw (Rust), OpenClaw (TypeScript), IronClaw (Rust), TinyClaw (TS/Bun), PicoClaw (Go), and NanoBot (Python), while delivering provably correct auth, secrets, audit, and sandbox policy.

## Why VeriClaw?

| Feature | **VeriClaw** | ZeroClaw | NullClaw | OpenClaw |
|---|---|---|---|---|
| Language | Ada/SPARK | Rust | Zig | TypeScript |
| Formal verification | **✅ SPARK Silver** | ❌ | ❌ | ❌ |
| Binary size (full runtime) | **6.84 MB** | 8.8 MB | 0.66 MB | N/A |
| Startup (native x86_64 est.)† | **~1.6 ms** | 10 ms | 8 ms | ~3 s |
| Dispatch p95 (native est.)† | **~1.9 ms** | 13.4 ms | 14 ms | — |
| LLM providers | **5** (OpenAI, Anthropic, Azure, Gemini, compat) | 12+ | 22+ | 15+ |
| Channels | **9** (CLI, Telegram, Signal, WhatsApp, Slack, Discord, Email, IRC, Matrix) | 25+ | 17 | 40+ |
| Streaming output | **✅** | ✅ | ✅ | ✅ |
| MCP client | **✅** | ✅ | ❌ | ✅ |
| Cron scheduler | **✅** | ❌ | ❌ | ✅ |
| Parallel tool calls | **✅ Ada tasks** | ✅ Tokio | ❌ | ✅ |
| Provably correct security | **✅** | ❌ | ❌ | ❌ |

> † Benchmarks measured via QEMU x86_64 on Apple Silicon (50 runs, `edge-speed` build). Raw QEMU: startup 48.8 ms, dispatch p95 56.9 ms. Native estimates apply ~30× correction. To reproduce: `make ingest-nullclaw ingest-zeroclaw competitive-bench`. See [docs/benchmarks.md](docs/benchmarks.md).

## Features

**LLM providers**
- OpenAI (GPT-4o, GPT-4-turbo), Anthropic (Claude 3.5/3.7), Azure AI Foundry, Google Gemini (2.0 Flash), and any OpenAI-compatible endpoint — Ollama, Groq, OpenRouter, LiteLLM, LM Studio
- Multi-provider failover — automatic fallback to secondary provider on failure
- Streaming SSE token output in CLI mode (always-on, no flag needed)

**Channels (9 total)**
- CLI — interactive chat + one-shot agent mode
- Telegram, Signal, WhatsApp — fully operational
- Slack (Socket Mode), Discord (Gateway), Email (IMAP/SMTP), IRC, Matrix — via lightweight Node.js sidecars
- All channels run concurrently in `gateway` mode using Ada tasks
- Per-user memory isolation — operator gets full access, guests get sandboxed namespaces

**Tools (8 built-in + unlimited via MCP)**
- `file` — read/write/list files in `~/.vericlaw/workspace/` (workspace-scoped, path-traversal blocked)
- `shell` — execute commands via popen (disabled by default, allowlisted)
- `web_fetch` — fetch and parse web pages
- `brave_search` — Brave Search API
- `git_operations` — `status`, `log`, `diff`, `add`, `commit`, `push`, `pull`, `branch`, `checkout`
- `cron_add` / `cron_list` / `cron_remove` — schedule recurring AI tasks
- `spawn` — delegate a subtask to an independent sub-agent (depth-capped at 1)
- **MCP (Model Context Protocol)** — connect external tool servers via `mcp-bridge`; tools auto-discovered at startup

**Memory and state**
- SQLite with FTS5 full-text search + persistent facts store
- Session auto-expiry (configurable, default 30 days)
- WAL mode for safe concurrent multi-channel writes
- Parallel tool calls — multiple tools from one LLM response execute concurrently via Ada tasks

**Security (formally verified)**
- **SPARK Silver proofs** — absence of runtime errors proved in security core (auth, allowlist, rate limit)
- **SPARK Flow Analysis** — all security modules have data flow proof
- Fail-closed defaults — empty allowlist = deny all; no public bind by default
- Encrypted secrets — ChaCha20-Poly1305 at rest
- Tamper-evident audit log + syslog forwarding
- Workspace isolation + path traversal blocked at policy level

**Operations**
- Prometheus `/metrics` endpoint — per-channel, per-provider, per-tool counters
- `SIGHUP` hot config reload — update tokens/allowlists without restart
- `doctor` command — verify config, connectivity, and tool availability
- Systemd / launchd / Windows service packaging
- Multi-arch Docker images (amd64 / arm64 / arm/v7)

## Project Structure

```
vericlaw/
├── src/                              # All Ada/SPARK source code
│   ├── main.adb                      # Entry point: chat / agent / gateway / doctor / version
│   │
│   ├── # ── SPARK-verified security core (formally proved) ─────────────────
│   ├── security-policy.ads/adb       # Path, URL, egress policy decisions
│   ├── security-audit.ads/adb        # Tamper-evident audit log with redaction
│   ├── security-secrets.ads/adb      # Encrypted secret storage (ChaCha20-Poly1305)
│   ├── gateway-auth.ads/adb          # Pairing, token auth, lockout policy
│   ├── channels-security.ads/adb     # Channel allowlist + rate limit (SPARK Silver)
│   ├── channels-adapters-*.ads       # SPARK adapter specs (Telegram, Slack, Discord, Email, WhatsApp)
│   ├── audit-syslog.ads/adb          # Syslog forwarding (POSIX openlog/syslog C bindings)
│   │
│   ├── # ── Agent runtime (standard Ada, built on the security core) ───────
│   ├── agent/
│   │   ├── agent-context.ads/adb     # Conversation history, roles, eviction
│   │   ├── agent-loop_pkg.ads/adb    # Core reasoning loop; parallel tool dispatch
│   │   └── agent-tools.ads/adb       # Tool registry, schema builder, MCP integration
│   ├── channels/
│   │   ├── channels-cli.ads/adb      # Interactive CLI + one-shot + streaming output
│   │   ├── channels-telegram.ads/adb # Telegram Bot API long-polling
│   │   ├── channels-signal.ads/adb   # Signal via signal-cli REST bridge
│   │   ├── channels-whatsapp.ads/adb # WhatsApp via WA-Bridge REST API
│   │   ├── channels-slack.ads/adb    # Slack via Socket Mode bridge (port 3001)
│   │   ├── channels-discord.ads/adb  # Discord Gateway bridge (port 3002)
│   │   ├── channels-email.ads/adb    # Email IMAP/SMTP bridge (port 3003)
│   │   ├── channels-irc.ads/adb      # IRC via irc-bridge (port 3005)
│   │   └── channels-matrix.ads/adb   # Matrix via matrix-bridge (port 3006)
│   ├── config/
│   │   ├── config-schema.ads         # Typed config record (all providers, channels, tools, memory)
│   │   ├── config-loader.ads/adb     # Load ~/.vericlaw/config.json; onboard wizard
│   │   ├── config-reload.ads/adb     # SIGHUP handler — hot config reload
│   │   └── config-json_parser.ads/adb# Custom JSON parser with safe accessors
│   ├── http/
│   │   ├── http-client.ads/adb       # libcurl bindings: normal + streaming SSE
│   │   └── http-server.ads/adb       # HTTP gateway + /metrics endpoint
│   ├── memory/
│   │   └── memory-sqlite.ads/adb     # SQLite WAL: history + FTS5 + facts + cron jobs
│   ├── metrics.ads/adb               # Prometheus counter store + Render function
│   ├── providers/
│   │   ├── providers-interface_pkg.ads/adb  # Abstract provider + Chat / Chat_Streaming
│   │   ├── providers-openai.ads/adb         # OpenAI /v1/chat/completions (+ SSE)
│   │   ├── providers-anthropic.ads/adb      # Anthropic /v1/messages (+ SSE)
│   │   ├── providers-gemini.ads/adb         # Google Gemini v1beta generateContent
│   │   └── providers-openai_compatible.ads/adb  # Azure Foundry + Groq + Ollama + any compat
│   └── tools/
│       ├── tools-shell.ads/adb       # Shell execution via popen (disabled by default)
│       ├── tools-file_io.ads/adb     # File read/write/list (workspace-scoped)
│       ├── tools-brave_search.ads/adb# Brave Search REST API
│       ├── tools-git.ads/adb         # Git operations (9 actions, workspace-scoped)
│       ├── tools-cron.ads/adb        # Cron scheduler (add/list/remove + interval parser)
│       ├── tools-spawn.ads/adb       # Sub-agent delegation (depth-capped at 1)
│       └── tools-mcp.ads/adb         # MCP client: fetch tools + execute via bridge
│
├── # ── Node.js bridge sidecars ─────────────────────────────────────────────
├── wa-bridge/                        # WhatsApp via Baileys (port 3000)
├── slack-bridge/                     # Slack Socket Mode (port 3001)
├── discord-bridge/                   # Discord Gateway via discord.js (port 3002)
├── email-bridge/                     # IMAP poll + SMTP send via imap-simple (port 3003)
├── mcp-bridge/                       # MCP client proxy via @modelcontextprotocol/sdk (port 3004)
├── irc-bridge/                       # IRC via irc-framework (port 3005)
├── matrix-bridge/                    # Matrix via matrix-js-sdk (port 3006)
│
├── tests/                            # SPARK policy tests + runtime unit tests
│   ├── config_loader_test.adb/.gpr   # 18 config parsing tests
│   ├── agent_context_test.adb/.gpr   # 16 conversation context tests
│   ├── agent_tools_test.adb/.gpr     # 21 tool schema + dispatch tests
│   ├── memory_sqlite_test.adb/.gpr   # SQLite save/retrieve/FTS search
│   └── security_*/                   # SPARK decision-vector driven policy tests
│
├── scripts/
│   ├── bench-rss.sh                  # Idle RSS benchmark vs ZeroClaw/NullClaw
│   ├── bootstrap_toolchain.sh        # Install GNAT + Alire + libcurl + sqlite3
│   └── ...                           # (20+ CI, release, conformance scripts)
│
├── config/
│   ├── *.example.json                # Ready-to-copy configs for every channel
│   ├── examples/                     # Full example configs (groq.json, etc.)
│   └── security_slos.toml            # Performance SLO thresholds for CI gate
│
├── docs/
│   ├── benchmarks.md                 # Performance targets + comparison table
│   ├── providers/                    # groq.md, ollama.md, openrouter.md
│   └── setup/                        # whatsapp.md, slack.md, discord.md, email.md, irc.md, matrix.md, mcp.md
│
├── deploy/
│   ├── systemd/vericlaw.service      # Linux systemd unit
│   ├── launchd/com.vericlaw.plist    # macOS launchd plist
│   └── windows/install-vericlaw-service.ps1
│
├── operator-console/                 # Local web operator console (HTML/CSS/JS)
├── .github/workflows/ada-ci.yml      # GitHub Actions CI
├── vericlaw.gpr                      # GPRbuild project file
├── spark.adc                         # SPARK configuration (Silver level)
├── Makefile                          # All build, test, and release targets
├── docker-compose.yml                # Full stack (vericlaw + all bridges)
└── docker-compose.secure.yml         # Hardened production deployment
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
make edge-speed-build # speed-optimised binary (~6.84 MB)
make edge-size-build  # size-optimised binary (~400-600 KB)
```

### 3. Configure

Run the interactive setup wizard — the fastest way to create your config:

```bash
vericlaw onboard
```

This asks for your provider, API key, model, agent name, and channel, then writes `~/.vericlaw/config.json`. A minimal manual config:

```json
{
  "agent_name": "VeriClaw",
  "system_prompt": "You are VeriClaw, a helpful AI assistant.",
  "providers": [
    { "kind": "openai", "api_key": "sk-...", "model": "gpt-4o" },
    { "kind": "anthropic", "api_key": "sk-ant-...", "model": "claude-3-5-sonnet-20241022" }
  ],
  "channels": [
    { "kind": "cli", "enabled": true },
    { "kind": "telegram", "enabled": true, "token": "BOT_TOKEN", "allowlist": "123456789" }
  ],
  "tools": {
    "file": true,
    "shell": false,
    "web_fetch": false,
    "brave_search": false,
    "brave_api_key": "",
    "git": true
  },
  "memory": { "max_history": 50, "facts_enabled": true, "session_retention_days": 30 },
  "gateway": { "bind_host": "127.0.0.1", "bind_port": 8787 }
}
```

### 4. Use

```bash
vericlaw onboard                        # interactive setup wizard (first-time)
vericlaw channels login --channel whatsapp  # link WhatsApp (headless pairing code)
vericlaw chat                           # interactive CLI conversation (streaming output)
vericlaw agent "Summarise today's news" # one-shot, prints reply
vericlaw gateway                        # start all enabled channels concurrently
vericlaw doctor                         # check config, health, connectivity
vericlaw version                        # print version
vericlaw help                           # show all commands
```

## Providers

| Kind | `kind` in config | Notes |
|---|---|---|
| OpenAI | `openai` | `model`: gpt-4o, gpt-4-turbo, etc. |
| Anthropic | `anthropic` | `model`: claude-3-5-sonnet-20241022, claude-3-7-sonnet, etc. |
| Azure AI Foundry | `azure_foundry` | Set `base_url`, `deployment`, `api_version` |
| Google Gemini | `gemini` | `model`: gemini-2.0-flash (default), gemini-1.5-pro, etc. |
| OpenAI-compatible | `openai_compatible` | `base_url` covers Ollama, Groq, OpenRouter, LiteLLM, LM Studio |

**Multi-provider failover:** List providers in order; VeriClaw automatically falls back to the next on failure.

**Streaming:** Always-on in CLI mode — tokens are printed as they arrive for all OpenAI and Anthropic providers. Other providers fall back gracefully to non-streaming.

**Groq (fastest inference):**
```json
{ "kind": "openai_compatible", "base_url": "https://api.groq.com/openai/v1",
  "token": "gsk_...", "model": "llama-3.3-70b-versatile" }
```
See [docs/providers/groq.md](docs/providers/groq.md) for model list.

**Ollama (local, no API key):**
```json
{ "kind": "openai_compatible", "base_url": "http://localhost:11434",
  "api_key": "", "model": "llama3.2" }
```
See [docs/providers/ollama.md](docs/providers/ollama.md) for setup.

**OpenRouter (200+ models, one key):**
```json
{ "kind": "openai_compatible", "base_url": "https://openrouter.ai/api/v1",
  "token": "sk-or-...", "model": "anthropic/claude-3.5-sonnet" }
```

**Azure AI Foundry:**
```json
{ "kind": "azure_foundry", "api_key": "AZURE_KEY",
  "base_url": "https://YOUR-HUB.openai.azure.com",
  "deployment": "gpt-4o", "api_version": "2024-02-15-preview" }
```

## Channels

All channels run concurrently in `vericlaw gateway` mode using Ada tasks. Each gets its own memory handle (SQLite WAL mode).

### CLI
Works out of the box — no config needed. Run `vericlaw chat` or `vericlaw agent "..."`.

Streaming output is always-on — tokens print as they arrive.

### Telegram
1. Create a bot via [@BotFather](https://t.me/botfather) — get the bot token
2. Find your Telegram user ID via [@userinfobot](https://t.me/userinfobot)
3. Set `token` and `allowlist` (comma-separated IDs, or `"*"` for open — **not recommended**)
4. Run `vericlaw gateway`

### Signal
Requires [signal-cli](https://github.com/AsamK/signal-cli) running as a REST daemon:
```bash
java -jar signal-cli.jar -u +15551234567 daemon --http=127.0.0.1:8080
```
Set `bridge_url: "http://127.0.0.1:8080"` and `token: "+15551234567"` in config.

### WhatsApp
Requires the bundled WA-Bridge (Baileys-based). See [docs/setup/whatsapp.md](docs/setup/whatsapp.md) for headless pairing:
```bash
docker compose up wa-bridge
vericlaw channels login --channel whatsapp  # shows pairing code
```

### Slack
Requires a Slack app in Socket Mode. See [docs/setup/slack.md](docs/setup/slack.md):
```bash
export SLACK_BOT_TOKEN=xoxb-...
export SLACK_APP_TOKEN=xapp-...
docker compose up slack-bridge vericlaw
```

### Discord
Requires a Discord application with bot token. See [docs/setup/discord.md](docs/setup/discord.md):
```bash
export DISCORD_BOT_TOKEN=...
docker compose up discord-bridge vericlaw
```

### Email
Polls an IMAP inbox every 30 seconds; replies via SMTP. See [docs/setup/email.md](docs/setup/email.md):
```bash
# Gmail: enable IMAP + create an App Password (requires 2FA)
export EMAIL_USER=you@gmail.com  EMAIL_PASS=your-app-password
docker compose up email-bridge vericlaw
```

### IRC
Connect to any IRC server. See [docs/setup/irc.md](docs/setup/irc.md):
```bash
export IRC_HOST=irc.libera.chat  IRC_NICK=vericlaw  IRC_CHANNELS="#general"
docker compose up irc-bridge vericlaw
```

### Matrix
Connect to any Matrix homeserver. See [docs/setup/matrix.md](docs/setup/matrix.md):
```bash
export MATRIX_HOMESERVER=https://matrix.org  MATRIX_TOKEN=syt_...  MATRIX_USER_ID=@bot:matrix.org
docker compose up matrix-bridge vericlaw
```

### Multi-user gateway

When `allowlist` contains a specific user (not `"*"`), that user is the **operator** — full access, full system prompt.

Anyone else reaching the agent when `allowlist: "*"` is a **guest** — sandboxed to an isolated memory namespace (`guest-{channel}-{user_id}`) and a modified system prompt with an advisory note. Guests cannot access operator memory or facts.

## Tools

| Tool | Config key | Default | Description |
|---|---|---|---|
| File I/O | `file: true` | **on** | Read/write/list files in `~/.vericlaw/workspace/` |
| Shell | `shell: true` | off | Execute shell commands via popen |
| Web fetch | `web_fetch: true` | off | Fetch and parse web pages |
| Brave Search | `brave_search: true` + `brave_api_key` | off | Web search via Brave Search API |
| Git operations | `git: true` | **on** | `status`, `log`, `diff`, `add`, `commit`, `push`, `pull`, `branch`, `checkout` |
| Cron scheduler | always available | — | `cron_add`, `cron_list`, `cron_remove` — schedule recurring AI tasks |
| Spawn | always available | — | Delegate a subtask to an isolated sub-agent |
| MCP tools | `mcp_bridge_url` | off | Auto-discovered from any MCP server via mcp-bridge |

### Cron scheduler

Schedule recurring tasks that run automatically:
```
you: cron_add daily-summary every 24h — "Give me a briefing on what happened today"
bot: Scheduled 'daily-summary' to run every 24h. Next run: 2026-02-28T14:00:00Z
```

Intervals: `5m`, `1h`, `24h`, `7d`. Jobs are stored in SQLite and survive restarts. A background Ada task checks for due jobs every 60 seconds and runs them autonomously.

### MCP client

Connect any [Model Context Protocol](https://modelcontextprotocol.io) tool server:

```json
{
  "tools": { "mcp_bridge_url": "http://mcp-bridge:3004" }
}
```

In `docker-compose.yml`:
```yaml
mcp-bridge:
  build: ./mcp-bridge
  environment:
    MCP_SERVERS: '[{"name":"filesystem","command":"npx","args":["-y","@modelcontextprotocol/server-filesystem","/workspace"]}]'
  profiles: [mcp]
```

On startup, VeriClaw fetches the tool list from the bridge and exposes them to the LLM as `mcp__{server}__{tool}` — transparently alongside built-in tools. See [docs/setup/mcp.md](docs/setup/mcp.md).

### Spawn / subagent

The LLM can delegate focused subtasks to an isolated sub-agent:
```
you: Research the top 5 Rust async runtimes and compare them
bot: [calls spawn("Research top 5 Rust async runtimes: Tokio, async-std, ...")]
bot: Here's a comparison based on the research: ...
```

Sub-agents run with a clean conversation (system prompt + single prompt, no tools, depth cap = 1).

## Security

- **SPARK Silver proofs** — absence of runtime errors formally proved in all security core modules (auth, channel allowlist + rate limit, secrets). GNATprove `--level=2` with Z3/CVC4/AltErgo.
- **SPARK Flow Analysis** — all security modules have data flow proof (no uninitialised reads, no data leaks across security boundaries)
- **Fail-closed defaults** — empty allowlist = deny all; pairing required before first use; no public bind by default
- **Encrypted secrets** — API keys stored with ChaCha20-Poly1305 at rest
- **Tamper-evident audit log** — signed event trail with metadata redaction + syslog forwarding (`LOG_INFO` / `LOG_WARNING` per event severity)
- **Workspace isolation** — file tool restricted to `~/.vericlaw/workspace/`; `../` and NUL path traversal blocked at policy level (proved in SPARK)
- **Process sandboxing** — Landlock/Seccomp/Firejail auto-selected per platform

### Running GNATprove

```bash
make check           # flow analysis (fast, development)
gnatprove -P vericlaw.gpr --level=2 --report=fail   # full Silver proof
```

## Operations

### Prometheus metrics

VeriClaw exposes a standard `/metrics` endpoint (Prometheus text format) on the gateway bind address:

```bash
curl http://127.0.0.1:8787/metrics
```

Available counters:
- `vericlaw_requests_total{channel="telegram|slack|..."}` — messages processed
- `vericlaw_errors_total{channel="..."}` — processing errors
- `vericlaw_provider_calls_total{provider="openai|anthropic|..."}` — LLM calls
- `vericlaw_provider_errors_total{provider="..."}` — LLM failures (triggers failover)
- `vericlaw_tool_calls_total{tool="file|shell|git|..."}` — tool invocations
- `vericlaw_uptime_seconds` — process uptime gauge

### Hot config reload (SIGHUP)

Update tokens, allowlists, or system prompts without restarting:

```bash
# Edit config
nano ~/.vericlaw/config.json

# Signal running process
kill -HUP $(pidof vericlaw)
# → "Config reloaded." printed on next poll cycle for each channel
```

### Parallel tool execution

When an LLM response includes multiple tool calls, VeriClaw executes them concurrently via Ada tasks and collects results in order. Ordering-sensitive tools (`cron_*`, `spawn`) always run sequentially.

### Idle RSS benchmark

```bash
./scripts/bench-rss.sh ./vericlaw
```

See [docs/benchmarks.md](docs/benchmarks.md) for the full comparison table against ZeroClaw and NullClaw.

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

**All commands:**
- `vericlaw onboard` — interactive wizard (provider, API key, model, agent name, channel)
- `vericlaw chat` — interactive CLI with streaming token output
- `vericlaw agent "..."` — one-shot mode with streaming output
- `vericlaw gateway` — runs all enabled channels concurrently via Ada tasks
- `vericlaw doctor` — config check, connectivity, health status
- `vericlaw version` / `vericlaw help`

**All 5 providers:** OpenAI, Anthropic, Azure AI Foundry, Google Gemini, any OpenAI-compatible (Groq, Ollama, OpenRouter, LiteLLM)

**All 9 channels (concurrently in gateway mode):** CLI, Telegram, Signal, WhatsApp, Slack, Discord, Email, IRC, Matrix

**All 8 built-in tools + unlimited MCP tools:**
`file`, `shell`, `web_fetch`, `brave_search`, `git_operations`, `cron_add/list/remove`, `spawn`

**Infrastructure:**
- Streaming SSE output (OpenAI + Anthropic)
- Multi-provider failover
- Session expiry auto-prune (configurable)
- Prometheus `/metrics` endpoint
- `SIGHUP` hot config reload
- Multi-user gateway (operator vs guest memory isolation)
- Parallel tool execution (Ada task pool)
- Cron heartbeat background task
- Syslog audit forwarding
- SPARK Silver proofs on security core
- SQLite WAL mode for safe concurrent channel writes
- Multi-arch Docker images (amd64 / arm64 / arm/v7)
- Systemd / launchd / Windows service packaging

## Remaining To-Dos

Three items intentionally deferred for a future release:

- [ ] **Browser / screenshot tool** — headless Chromium control via Chrome DevTools Protocol (`browser_navigate`, `browser_screenshot`, `browser_click`)
- [ ] **Vector embeddings + RAG** — `sqlite-vec` extension for semantic similarity search; retrieval-augmented generation from local documents
- [ ] **Web operator console** — wire the `operator-console/` HTML/JS frontend to the live gateway for in-browser session management
