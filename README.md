# Quasar Claw Lab

Quasar is a **security-first, edge-friendly AI assistant runtime** written in Ada/SPARK — the only agent in its class with **formally-verified security policies**. It competes with NullClaw, ZeroClaw, OpenClaw, IronClaw, TinyClaw, PicoClaw, and NanoBot while delivering provably correct auth, secrets, audit, and sandbox policy.

## Why Quasar?

| Feature | Quasar | ZeroClaw | NullClaw | OpenClaw |
|---|---|---|---|---|
| Language | Ada/SPARK | Rust | Zig | TypeScript |
| Formal verification | **✅ SPARK** | ❌ | ❌ | ❌ |
| Binary size | **168KB** | 8.8MB | 678KB | N/A |
| Startup | **1.59ms** | 10ms | 8ms | ~3s |
| Dispatch p95 | **1.2ms** | 13.4ms | 14ms | — |
| LLM providers | OpenAI, Anthropic, Azure Foundry, compat | 12+ | 22+ | 15+ |
| Channels | CLI, Telegram, Signal, WhatsApp | 25+ | 17 | 40+ |
| Provably correct security | **✅** | ❌ | ❌ | ❌ |

## Features

- **SPARK-verified security core** — auth, secrets, sandbox, audit policies proven correct
- **4 LLM providers** — OpenAI (GPT-4o), Anthropic (Claude 3.5), Azure AI Foundry, any OpenAI-compatible endpoint
- **4 channels** — CLI (interactive + one-shot), Telegram, Signal, WhatsApp
- **4 tools** — shell execution, file I/O, web fetch, Brave Search
- **SQLite memory** — conversation history with FTS5 search + persistent facts
- **Multi-provider failover** — automatic fallback to secondary provider
- **Fail-closed defaults** — denies all unless explicitly permitted
- **Edge-optimized** — runs on Raspberry Pi Zero W, $5 hardware

## Quick start

### 1. Install toolchain

```bash
# macOS
brew install gprbuild alire curl sqlite
alr with gnatcoll gnatcoll_sqlite aws

# Ubuntu/Debian
sudo apt-get install -y gnat gprbuild libcurl4-openssl-dev libsqlite3-dev
alr with gnatcoll gnatcoll_sqlite aws
```

### 2. Build

```bash
make build            # dev build
make edge-size-build  # optimized binary
```

### 3. Configure

```bash
quasar chat  # creates ~/.quasar/config.json if missing
```

Edit `~/.quasar/config.json`:

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
  "memory": {
    "max_history": 50,
    "facts_enabled": true
  },
  "gateway": {
    "bind_host": "127.0.0.1",
    "bind_port": 8787
  }
}
```

### 4. Use it

```bash
# Interactive chat
quasar chat

# One-shot
quasar agent "What is the capital of France?"

# Run gateway (Telegram + webhook receiver)
quasar gateway

# Health check
quasar doctor
```

## Providers

| Kind | Config `kind` | Notes |
|---|---|---|
| OpenAI | `openai` | `model`: gpt-4o, gpt-4-turbo, etc. |
| Anthropic | `anthropic` | `model`: claude-3-5-sonnet-20241022, etc. |
| Azure AI Foundry | `azure_foundry` | Set `base_url`, `deployment`, `api_version` |
| OpenAI-compatible | `openai_compatible` | Set `base_url`; covers Ollama, OpenRouter, LiteLLM |

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

### Telegram
1. Create a bot via [@BotFather](https://t.me/botfather) — get the bot token
2. Find your Telegram user ID (e.g. via [@userinfobot](https://t.me/userinfobot))
3. Set `token` and `allowlist` (comma-separated user IDs, or `"*"` for anyone)
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
Scan QR code on first run. Set `bridge_url: "http://localhost:3000"` in config.

## Tools

| Tool | Config key | Description |
|---|---|---|
| File I/O | `file: true` | Read/write files in `~/.quasar/workspace/` |
| Shell | `shell: true` | Execute shell commands (disabled by default) |
| Web fetch | `web_fetch: true` | Fetch web pages |
| Brave Search | `brave_search: true` + `brave_api_key` | Web search via Brave API |

## Security

- **SPARK-verified policies**: auth, secrets, channel allowlists, sandbox limits — all formally proved
- **Fail-closed defaults**: empty allowlist = deny all; pairing required; no public bind
- **Encrypted secrets**: ChaCha20-Poly1305 at rest
- **Tamper-evident audit log**: signed event trail with redaction
- **Workspace isolation**: file tool restricted to `~/.quasar/workspace/` (path traversal blocked)
- **Process sandboxing**: Landlock/Seccomp/Firejail auto-selected

## CLI reference

```
quasar chat              Interactive CLI conversation
quasar agent <msg>       One-shot: send message, print reply
quasar gateway           Run gateway + all enabled channels
quasar doctor            Show config and health status
quasar version           Print version
```

## Build profiles

```bash
make build           # dev (full assertions)
make small-build     # size-optimized (-Os + gc-sections)
make edge-size-build # smallest binary (minimal binder)
make edge-speed-build # speed-optimized (-O2)
```



## Current readiness status (latest artifacts)

- `tests/competitive_v2_release_readiness_gate_report.json` reports `overall_status: pass` with `10/10` steps passing.
- `tests/competitive_v2_final_competitive_report.json` reports `overall_status: pass` against strict quantitative peers **ZeroClaw** and **NullClaw**.
- `tests/cross_repo_conformance_report.json` reports `overall_status: pass` across conformance/security suites.
- `tests/vulnerability_license_gate_report.json` is produced by a blocking vulnerability + license policy gate.

### Competitive snapshot (strict peers: ZeroClaw + NullClaw)

| Metric | Quasar | ZeroClaw | NullClaw |
|---|---:|---:|---:|
| Startup (ms) | 1.59 | 10 | 8 |
| Idle RSS (MB) | 3.473 | 4.1 | 1 |
| Dispatch latency p95 (ms) | 1.216 | 13.4 | 14 |
| Throughput (ops/sec) | 921.331 | 80 | 78 |
| Binary size (MB) | 0.168 | 8.8 | 0.662 |
| Container size (MB) | 31.615 | 42 | 48 |

Reference: `tests/competitive_v2_final_competitive_report.md`.

## What works out of the box

- `make check` (build + SPARK flow checks + audit/service-hardening checks).
- `make secrets-test`, `make conformance-suite`, `make release-check`.
- `make vulnerability-license-gate` (blocking security/compliance gate with containerized fallback scanner support).
- `make docker-runtime-bundle-check`, `make service-supervisor-check`, `make audit-log-check`, `make gateway-doctor-check`.
- `make image-build-multiarch` (with optional signing/trust metadata).
- `make supply-chain-attest` and `make supply-chain-verify`.
- `make competitive-regression-gate` and `make competitive-v2-release-readiness-gate`.
- `make operator-console-serve` for local release health visibility.

## Quick start

1. Validate/bootstrap toolchain:
   - `make bootstrap-validate`
   - `make bootstrap` (if validation fails and you want automated setup)
2. Run core quality checks:
   - `make check`
   - `make secrets-test`
   - `make conformance-suite`
3. Run secure local deployment:
   - `make docker-runtime-bundle-check`
   - `docker compose -f docker-compose.secure.yml up --build`
4. Open local operator console:
   - `make operator-console-serve`

## Production deployment flow

1. Build release image:
   - local: `make image-build-local`
   - multi-arch: `make image-build-multiarch`
   - signed push example: `PUSH_IMAGE=true SIGN_IMAGE=true COSIGN_KEY=./cosign.key make image-build-multiarch`
2. Run blocking release gates:
   - `make release-candidate-gate`
   - `make competitive-v2-release-readiness-gate`
3. Verify trust/supply chain:
   - `make supply-chain-verify`
4. Verify runtime health/smoke:
   - `make cross-platform-smoke`
   - strict mode: `SMOKE_FAIL_ON_NON_BLOCKING=true make cross-platform-smoke`

## What is left to productionize Quasar for your environment

Repository implementation is effectively complete for the Competitive V2 scope (all `competitive-v2-*` tasks are done; only superseded legacy `rpi-v1-*` todos remain blocked).  
To start using Quasar as a real production service, you still need environment-specific rollout work:

- [ ] Choose target topology (single node vs HA, regions, runtime host sizing).
- [ ] Provision real provider/channel credentials and enforce your runtime allow/deny policies.
- [ ] Configure production secret/key management and key rotation procedures.
- [ ] Configure registry, signing keys, and CI/CD release promotion policy.
- [ ] Wire monitoring/alerting/SLOs and incident ownership for operator workflows.
- [ ] Run final gate set on your exact production profile and archive artifacts for audit/compliance.
- [ ] Publish release/tag + release notes, then onboard users to the operator runbook.

## Gate commands and report artifacts

- Competitive and performance:
  - `make competitive-bench`
  - `make competitive-bench-multiarch`
  - `make competitive-direct-harness`
  - `make competitive-baseline-check`
  - `make competitive-regression-gate`
- Security and compliance:
  - `make vulnerability-license-gate`
  - `make audit-log-check`
  - `make gateway-doctor-check`
- Deployment and supply chain:
  - `make cross-platform-smoke`
  - `make supply-chain-attest`
  - `make supply-chain-verify`
  - `make release-candidate-gate`
  - `make competitive-v2-release-readiness-gate`

Primary reports:

- `tests/competitive_v2_release_readiness_gate_report.json`
- `tests/competitive_v2_final_competitive_report.json`
- `tests/competitive_scorecard_report.json`
- `tests/competitive_regression_gate_report.json`
- `tests/cross_repo_conformance_report.json`
- `tests/cross_platform_smoke_report.json`
- `tests/vulnerability_license_gate_report.json`
- `tests/supply_chain_attestation_report.json`
- `tests/supply_chain_verification_report.json`

## Service packaging and runbooks

- Linux systemd: `deploy/systemd/quasar-claw.service`
- macOS launchd: `deploy/launchd/com.quasar.claw.plist`
- Windows installer: `deploy/windows/install-quasar-claw-service.ps1`
- Operator runbook: `docs/runbooks/operator-runbook.md`
