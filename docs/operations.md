# Operations Guide

[← Back to README](../README.md)

This guide covers day-to-day operations for running and monitoring VeriClaw in
development and production environments.

---

## Prometheus Metrics

VeriClaw exposes a standard `/metrics` endpoint (Prometheus text format) on the
gateway bind address:

```bash
curl http://127.0.0.1:8787/metrics
```

Available counters:

| Counter | Description |
|---|---|
| `vericlaw_requests_total{channel="telegram\|slack\|..."}` | Messages processed |
| `vericlaw_errors_total{channel="..."}` | Processing errors |
| `vericlaw_provider_calls_total{provider="openai\|anthropic\|..."}` | LLM calls |
| `vericlaw_provider_errors_total{provider="..."}` | LLM failures (triggers failover) |
| `vericlaw_tool_calls_total{tool="file\|shell\|git\|..."}` | Tool invocations |
| `vericlaw_uptime_seconds` | Process uptime gauge |

---

## Hot Config Reload (SIGHUP)

Update tokens, allowlists, or system prompts without restarting:

```bash
# Edit config
nano ~/.vericlaw/config.json

# Signal running process
kill -HUP $(pidof vericlaw)
# → "Config reloaded." printed on next poll cycle for each channel
```

---

## Structured Logging

All VeriClaw runtime components write JSON-line logs to **stderr** with
configurable log levels and request ID correlation:

```
{"ts":"2026-02-27T14:51:23Z","level":"info","msg":"Polling started","req_id":"abc123","ctx":{"channel":"telegram"}}
{"ts":"2026-02-27T14:51:24Z","level":"warning","msg":"Config reload failed","ctx":{}}
```

### Setting the log level

Set the minimum log level via the `VERICLAW_LOG_LEVEL` environment variable:

```bash
VERICLAW_LOG_LEVEL=debug vericlaw gateway   # show all logs including debug
VERICLAW_LOG_LEVEL=warning vericlaw gateway  # only warnings and errors
```

### Piping to log aggregators

```bash
vericlaw gateway 2>&1 | grep -v '^{' > access.log       # stdout only
vericlaw gateway 2> >(jq .)                              # pretty-print logs
vericlaw gateway 2>&1 | promtail --stdin --job vericlaw  # → Loki
```

---

## Live Gateway API

When `vericlaw gateway` is running, a local-only REST API is available on the
bind address (default `127.0.0.1:8787`).

> **Security:** All API endpoints are restricted to `127.0.0.1` — requests from
> any other source address receive `403 Forbidden`.

### GET /api/status

```bash
curl http://127.0.0.1:8787/api/status
# {"status":"running","version":"<build version>","uptime_s":120,"channels_active":3}
```

The `version` field mirrors `Build_Info.Version` embedded in the binary you are
running.

### GET /api/channels

```bash
curl http://127.0.0.1:8787/api/channels
# {"channels":[{"kind":"telegram","enabled":true,"max_rps":5},{"kind":"slack","enabled":true,"max_rps":5},...]}
```

### GET /api/plugins

```bash
curl http://127.0.0.1:8787/api/plugins
# {"extensibility_model":"mcp_first","local_plugins":[...]}
```

### GET /api/metrics/summary

```bash
curl http://127.0.0.1:8787/api/metrics/summary
# {"provider_requests_total":42,"provider_errors_total":0,"tool_calls_total":17}
```

### POST /api/chat

Non-streaming chat completion:

```bash
curl -X POST http://127.0.0.1:8787/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"Hello","session_id":"my-session"}'
# {"content":"Hi! How can I help?"}
```

### POST /api/chat/stream

SSE chat completion:

```bash
curl -i -X POST http://127.0.0.1:8787/api/chat/stream \
  -H 'Content-Type: application/json' \
  -d '{"message":"Hello","session_id":"my-session"}'
# X-VeriClaw-Stream-Mode: buffered-sse
# data: {"content":"Hi! How can I help?"}
# data: [DONE]
```

The stream endpoint currently emits buffered SSE responses and advertises the
transport explicitly via `X-VeriClaw-Stream-Mode: buffered-sse` so browser
clients can distinguish today's behavior from future chunked streaming.

See [docs/api.md](api.md) for the full API reference.

---

## Operator Console

A local web dashboard and chat client for checking gateway health, plugins, and
running conversations against the localhost API:

```bash
# Open directly in browser (no server needed)
open operator-console/index.html

# Or connect to a running gateway
# Enter "http://127.0.0.1:8787" in the Gateway URL field and click Connect
```

The console persists the gateway URL, session ID, and transcript in
`localStorage`. It detects `X-VeriClaw-Stream-Mode`, shows connection/error
state pills, restores the last local session, and surfaces status, channel,
metric, and plugin inventory data.

---

## Parallel Tool Execution

When an LLM response includes multiple tool calls, VeriClaw executes them
concurrently via Ada tasks and collects results in order. Ordering-sensitive
tools (`cron_*`, `spawn`) always run sequentially.

---

## Service Packaging

### Linux (systemd)

Install and enable:

```bash
sudo cp deploy/systemd/vericlaw.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vericlaw
```

Unit file: `deploy/systemd/vericlaw.service`

### macOS (launchd)

```bash
cp deploy/launchd/com.vericlaw.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.vericlaw.plist
```

Plist file: `deploy/launchd/com.vericlaw.plist`

### Windows

Run the installer in an elevated PowerShell prompt:

```powershell
.\deploy\windows\install-vericlaw-service.ps1
```

See `docs/runbooks/operator-runbook.md` for the full operator runbook.

---

## Production Deployment

### Build Release Image

```bash
# Local-only build
make image-build-local

# Signed multi-arch build and push
PUSH_IMAGE=true SIGN_IMAGE=true make image-build-multiarch
```

### Release Gates

Run blocking release gates before promoting a build:

```bash
make release-candidate-gate
make competitive-v2-release-readiness-gate
```

### Supply Chain Verification

```bash
make supply-chain-verify
SMOKE_FAIL_ON_NON_BLOCKING=true make cross-platform-smoke
```

---

## Docker Compose

VeriClaw ships two Compose files at the repository root:

| File | Purpose |
|---|---|
| `docker-compose.yml` | Full stack — VeriClaw + all channel bridges |
| `docker-compose.secure.yml` | Hardened production deployment |

### Development (full stack)

```bash
docker compose up            # start everything
docker compose up vericlaw   # gateway only
```

### Production (hardened)

```bash
make docker-runtime-bundle-check
docker compose -f docker-compose.secure.yml up --build
```

### Environment Variables

VeriClaw ships a `.env.example` file with all Docker Compose environment variables.
Use it as a starting template:

```bash
cp .env.example .env
# Edit .env to fill in your API keys, channel tokens, and bridge credentials
docker compose up
```

The file includes commented defaults for:
- Channel tokens (Discord, Slack, Telegram)
- Email bridge credentials (IMAP/SMTP)
- IRC and Matrix configuration
- Mattermost bridge credentials (`MATTERMOST_URL`, `MATTERMOST_TOKEN`, `MATTERMOST_TEAM`, `MATTERMOST_CHANNEL`)
- MCP bridge URL
- Logging level

> [!TIP]
> Required variables use `?` syntax in `docker-compose.yml` — Docker will error
> with a clear message if they're missing.
