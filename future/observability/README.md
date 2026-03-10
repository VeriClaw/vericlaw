# future/observability/

Distributed tracing and metrics — not included in v1.0-minimal.

## Contents

| Directory | What it is | Returns at |
|-----------|-----------|------------|
| `tracing/` | OTLP distributed tracing spans (`observability-tracing.*`) | v1.3 |
| `metrics/` | Prometheus counters per-channel, per-provider, per-tool (`metrics.ads/adb`, `metrics-cost.ads/adb`) | v1.3 |

## Note

In v1.0-minimal, VeriClaw logs to stdout/stderr and the audit log. Structured observability returns in v1.3 when gateway mode and multi-tenant deployments make it necessary.
