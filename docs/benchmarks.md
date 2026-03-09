# VeriClaw Competitive Benchmarks

VeriClaw's benchmark flow is now built around a competitive-v2 pipeline: generate a raw
VeriClaw benchmark report, normalize competitor snapshots into a common schema, enforce a
local regression baseline, and then assemble a final comparative report.

## Benchmark Inputs

The benchmark pipeline relies on these checked-in inputs:

| Path | Purpose |
| --- | --- |
| `config/anywhere_v2_competitive_baseline.toml` | Baseline SLOs and scorecard expectations for the current benchmark gate |
| `config/competitive_scorecards/zeroclaw_v2_scorecard.json` | Conservative ZeroClaw fallback scorecard |
| `config/competitive_scorecards/nullclaw_v2_scorecard.json` | Conservative NullClaw fallback scorecard |
| `config/competitive_scorecards/openclaw_v2_scorecard.json` | OpenClaw scorecard-only reference snapshot |

If sibling repos are available locally, the ingest scripts refresh ZeroClaw and NullClaw from
their current READMEs and workflows:

- `../zeroclaw`
- `../nullclaw`

OpenClaw is currently tracked as a scorecard-only peer because we do not yet have a direct local
benchmark harness for it.

## Generated Artifacts

| Path | Produced by | Notes |
| --- | --- | --- |
| `tests/competitive_benchmark_report.json` | `make competitive-bench` | Raw VeriClaw measurements |
| `tests/zeroclaw_v2_benchmark_ingest.json` | `make ingest-zeroclaw` | Refreshed ZeroClaw comparator snapshot |
| `tests/nullclaw_v2_benchmark_ingest.json` | `make ingest-nullclaw` | Refreshed NullClaw comparator snapshot |
| `tests/competitive_direct_benchmark_report.json` | `./scripts/run_direct_competitor_harness.sh` | Normalized side-by-side report |
| `tests/competitive_scorecard_report.json` | `./scripts/check_competitive_baseline.sh` | Feature/deployment/security scorecard output |
| `tests/competitive_regression_gate_report.json` | `./scripts/check_competitive_baseline.sh` | Regression/SLO gate result |
| `tests/competitive_v2_final_competitive_report.json` | `make competitive-final-report` | Final aggregate benchmark artifact |
| `tests/competitive_v2_release_readiness_gate_report.json` | `make competitive-v2-release-readiness-gate` | Full readiness sweep |

## Prerequisites

For a full raw VeriClaw rerun you need one of:

- a host with the blessed Ada/SPARK toolchain available, or
- the container benchmark backend described in `scripts/run_competitive_benchmarks.sh`.

The comparator ingest steps do not require building sibling projects. They refresh from the local
repository snapshots and fall back to the checked-in scorecards when direct execution is not
available.

## Authoritative Rerun Flow

### 1. Refresh competitor snapshots

```bash
make ingest-zeroclaw
make ingest-nullclaw
```

### 2. Generate or refresh the raw VeriClaw benchmark

```bash
make competitive-bench
```

If you already have a valid raw report and only need to rebuild the comparison layer, reuse it:

```bash
./scripts/run_direct_competitor_harness.sh \
  --vericlaw-report tests/competitive_benchmark_report.json
```

### 3. Run the local regression gate

```bash
./scripts/check_competitive_baseline.sh \
  --report tests/competitive_benchmark_report.json \
  --direct-report tests/competitive_direct_benchmark_report.json
```

### 4. Produce the final competitive report

```bash
make competitive-final-report
```

### 5. Optional extended coverage

```bash
make competitive-bench-multiarch
make competitive-v2-release-readiness-gate
```

## Current Baseline Policy

The checked-in `anywhere_v2` baseline is intentionally conservative:

- it enforces **VeriClaw SLOs first**,
- it treats ZeroClaw, NullClaw, and OpenClaw as **scorecard-only references** for now,
- it avoids strict peer-ratio pass/fail gates until we have a stable host-native apples-to-apples rerun lane,
- it currently gates on `startup_ms`, `dispatch_latency_p95_ms`, `throughput_ops_per_sec`, and `binary_size_mb`.

`idle_rss_mb` is intentionally omitted from the current gate because the latest local raw report
was collected in container/QEMU mode on macOS ARM, where idle RSS telemetry was not available in a
reliable cross-platform way.

The regression gate only enforces the subset of core metrics that appear in
`edge_performance_metrics`. This keeps the benchmark gate aligned with the active measurement mode
instead of hard-failing on unsupported telemetry.

## Current Local Reference Snapshot

The latest checked-in raw VeriClaw report (`tests/competitive_benchmark_report.json`) currently
shows:

- `startup_ms`: `88.509`
- `dispatch_latency_p95_ms`: `56.911`
- `throughput_ops_per_sec`: `20.482`
- `binary_size_mb`: `6.838`
- `measurement_mode`: `container`
- `host_platform`: `darwin/arm64`
- `target_platform`: `linux/amd64`
- `idle_rss_mb`: unsupported in that report

That snapshot is useful for regression tracking, but it is **not** the final apples-to-apples claim
we should publish externally. Re-run on a native Linux x86_64 benchmark lane before using the
numbers for public marketing comparisons.

## Interpretation Guidance

- Compare like-for-like measurement modes whenever possible.
- Treat README-derived competitor snapshots as maintained reference scorecards, not direct lab runs.
- Re-run ingest + direct harness whenever sibling repos materially change.
- Re-run the full raw VeriClaw benchmark before release candidates and benchmark-facing README updates.
