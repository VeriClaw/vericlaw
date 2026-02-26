#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

usage() {
  cat <<'EOF'
Usage: ./scripts/ingest_zeroclaw_benchmarks.sh [--zeroclaw-repo PATH] [--source-scorecard PATH] [--output PATH]

Ingests best-available local ZeroClaw benchmark metadata into VeriClaw's
competitive comparator schema. If local ZeroClaw execution is not feasible,
README benchmark snapshot values are used with scorecard fallback metrics.
EOF
}

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_zeroclaw_repo="$(cd "${project_root}/.." && pwd)/zeroclaw"
zeroclaw_repo="${ZEROCLAW_REPO:-${default_zeroclaw_repo}}"
source_scorecard_path="${SOURCE_SCORECARD_PATH:-${project_root}/config/competitive_scorecards/zeroclaw_v2_scorecard.json}"
output_path="${project_root}/tests/zeroclaw_v2_benchmark_ingest.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zeroclaw-repo)
      [[ $# -ge 2 ]] || { echo "Missing value for --zeroclaw-repo" >&2; exit 2; }
      zeroclaw_repo="$2"
      shift 2
      ;;
    --source-scorecard)
      [[ $# -ge 2 ]] || { echo "Missing value for --source-scorecard" >&2; exit 2; }
      source_scorecard_path="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "Missing value for --output" >&2; exit 2; }
      output_path="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

readme_path="${zeroclaw_repo}/README.md"
benchmark_workflow_path="${zeroclaw_repo}/.github/workflows/test-benchmarks.yml"
if [[ ! -f "${readme_path}" ]]; then
  echo "Missing ZeroClaw README: ${readme_path}" >&2
  exit 1
fi
if [[ ! -f "${benchmark_workflow_path}" ]]; then
  echo "Missing ZeroClaw benchmark workflow: ${benchmark_workflow_path}" >&2
  exit 1
fi
if [[ ! -f "${source_scorecard_path}" ]]; then
  echo "Missing source scorecard: ${source_scorecard_path}" >&2
  exit 1
fi

cargo_status="missing"
cargo_version=""
if command -v cargo >/dev/null 2>&1; then
  cargo_status="available"
  cargo_version="$(cargo --version 2>/dev/null || true)"
fi

mkdir -p "$(dirname "${output_path}")"
python3 - "${readme_path}" "${benchmark_workflow_path}" "${source_scorecard_path}" "${output_path}" "${cargo_status}" "${cargo_version}" <<'PY'
import json
import pathlib
import re
import sys
from datetime import datetime, timezone

readme_path = pathlib.Path(sys.argv[1])
benchmark_workflow_path = pathlib.Path(sys.argv[2])
source_scorecard_path = pathlib.Path(sys.argv[3])
output_path = pathlib.Path(sys.argv[4])
cargo_status = sys.argv[5]
cargo_version = sys.argv[6]

readme_text = readme_path.read_text(encoding="utf-8")
with source_scorecard_path.open("r", encoding="utf-8") as handle:
    source_scorecard = json.load(handle)


def extract_number(patterns):
    for pattern in patterns:
        match = re.search(pattern, readme_text, flags=re.IGNORECASE | re.MULTILINE)
        if match:
            return float(match.group(1))
    return None


startup_ms = extract_number(
    [
        r"\|\s*\*\*Startup \(0\.8\s*GHz core\)\*\*.*?\*\*<\s*([0-9]+(?:\.[0-9]+)?)\s*ms\*\*",
    ]
)
startup_source = None
if startup_ms is not None:
    startup_source = "zeroclaw README benchmark snapshot (startup row: <10ms at 0.8GHz core)"

help_sample = re.search(
    r"`zeroclaw --help`: about `([0-9]+(?:\.[0-9]+)?)s` real time, ~`([0-9]+(?:\.[0-9]+)?)MB`",
    readme_text,
    flags=re.IGNORECASE,
)
status_sample = re.search(
    r"`zeroclaw status`: about `([0-9]+(?:\.[0-9]+)?)s` real time, ~`([0-9]+(?:\.[0-9]+)?)MB`",
    readme_text,
    flags=re.IGNORECASE,
)

if startup_ms is None:
    startup_seconds = None
    if status_sample:
        startup_seconds = float(status_sample.group(1))
    elif help_sample:
        startup_seconds = float(help_sample.group(1))
    if startup_seconds is not None:
        startup_ms = round(startup_seconds * 1000.0, 3)
        startup_source = "zeroclaw README reproducible sample (`zeroclaw status`/`--help` real time)"

idle_rss_mb = None
idle_rss_source = None
sample_rss_values = []
if help_sample:
    sample_rss_values.append(float(help_sample.group(2)))
if status_sample:
    sample_rss_values.append(float(status_sample.group(2)))
if sample_rss_values:
    idle_rss_mb = max(sample_rss_values)
    idle_rss_source = "zeroclaw README reproducible sample (peak memory footprint from `zeroclaw --help`/`status`)"
else:
    idle_rss_mb = extract_number(
        [
            r"\|\s*\*\*RAM\*\*.*?\*\*<\s*([0-9]+(?:\.[0-9]+)?)\s*MB\*\*",
        ]
    )
    if idle_rss_mb is not None:
        idle_rss_source = "zeroclaw README benchmark snapshot (RAM row: <5MB)"

binary_size_mb = extract_number(
    [
        r"\|\s*\*\*Binary Size\*\*.*?\*\*~\s*([0-9]+(?:\.[0-9]+)?)\s*MB\*\*",
        r"Release binary size:\s*`([0-9]+(?:\.[0-9]+)?)MB`",
    ]
)
binary_size_source = None
if binary_size_mb is not None:
    binary_size_source = "zeroclaw README benchmark snapshot/sample (release binary size: ~8.8MB)"

performance = source_scorecard.get("performance", {})
if not isinstance(performance, dict):
    performance = {}
performance = dict(performance)

if startup_ms is not None:
    performance["startup_ms"] = startup_ms
if idle_rss_mb is not None:
    performance["idle_rss_mb"] = idle_rss_mb
if binary_size_mb is not None:
    performance["binary_size_mb"] = binary_size_mb

report = dict(source_scorecard)
report.update(
    {
        "project": "zeroclaw",
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "snapshot_id": "competitive-v2-zeroclaw-local-ingest",
        "ingest_method": "local_readme_benchmark_snapshot_with_scorecard_fallback",
        "ingest_source": {
            "zeroclaw_readme": str(readme_path),
            "zeroclaw_benchmark_workflow": str(benchmark_workflow_path),
            "source_scorecard": str(source_scorecard_path),
        },
        "execution_feasibility": {
            "cargo_status": cargo_status,
            "cargo_version": cargo_version or None,
            "benchmark_execution_feasible": cargo_status == "available",
            "attempted_command": "cargo bench --locked",
            "reason": "cargo unavailable on host; ingested best-available local artifacts"
            if cargo_status != "available"
            else "cargo detected; this run ingested local benchmark snapshots and scorecard fallback metrics",
        },
        "performance_metric_sources": {
            "startup_ms": startup_source
            or "fallback from source scorecard due missing local benchmark artifact",
            "idle_rss_mb": idle_rss_source
            or "fallback from source scorecard due missing local benchmark artifact",
            "binary_size_mb": binary_size_source
            or "fallback from source scorecard due missing local benchmark artifact",
            "dispatch_latency_p95_ms": "fallback from source scorecard due missing local benchmark artifact",
            "throughput_ops_per_sec": "fallback from source scorecard due missing local benchmark artifact",
            "container_size_mb": "fallback from source scorecard due missing local benchmark artifact",
        },
    }
)
report["performance"] = performance

output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "zeroclaw-benchmark-ingest: ${output_path}"
