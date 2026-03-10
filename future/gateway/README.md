# future/gateway/

HTTP gateway mode components — the multi-tenant, multi-channel server architecture. Not included in v1.0-minimal, which runs as a single-user process.

## Contents

| Component | What it is | Returns at |
|-----------|-----------|------------|
| `http-server.*` | Ada HTTP server (AWS-based) exposing `/api/chat`, `/api/status`, `/api/channels`, `/api/plugins` | v1.3 |
| `gateway-provider-routing.*` | Multi-provider routing logic | v1.2 |
| `gateway-provider-runtime_routing.*` | Runtime provider selection and fallback | v1.2 |
| `gateway-provider-registry.*` | Provider registry for gateway mode | v1.3 |
| `gateway-provider-credentials.*` | Credential management for multi-provider gateway | v1.3 |
| `gateway.ads` | Top-level gateway package spec | v1.3 |
| `plugins-loader.*` | Plugin registry and loader | v1.3 |
| `plugins-capabilities.*` | Plugin capability declarations | v1.3 |
| `runtime-executor.*` | Task pool executor for parallel tool execution in gateway mode | v1.3 |

## What stays in src/ (related)

- `gateway-auth.*` — **stays in `src/` as a SPARK security package** — token authentication, pairing flow, lockout policy. Required for the security proof claims even in v1.0-minimal.
- `http-client.*` — stays in `src/http/` — the outbound HTTP client for LLM API calls.

## Gateway mode design (v1.3)

In gateway mode, VeriClaw runs as a persistent service with:
- One Ada task per active channel
- REST API on localhost for the operator console and external integrations
- SSE streaming for `/api/chat/stream`
- Prometheus metrics at `/api/metrics/summary`
