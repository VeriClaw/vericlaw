#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

usage() {
  cat <<'EOF'
Usage: ./scripts/ingest_nullclaw_benchmarks.sh [--nullclaw-repo PATH] [--source-scorecard PATH] [--output PATH]

Ingests best-available local NullClaw benchmark metadata into VeriClaw's
competitive comparator schema. If local NullClaw execution is not feasible,
README benchmark snapshot values are used with scorecard fallback metrics.
EOF
}

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_nullclaw_repo="$(cd "${project_root}/.." && pwd)/nullclaw"
nullclaw_repo="${NULLCLAW_REPO:-${default_nullclaw_repo}}"
source_scorecard_path="${SOURCE_SCORECARD_PATH:-${project_root}/config/competitive_scorecards/nullclaw_v2_scorecard.json}"
output_path="${project_root}/tests/nullclaw_v2_benchmark_ingest.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nullclaw-repo)
      [[ $# -ge 2 ]] || { echo "Missing value for --nullclaw-repo" >&2; exit 2; }
      nullclaw_repo="$2"
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

readme_path="${nullclaw_repo}/README.md"
ci_workflow_path="${nullclaw_repo}/.github/workflows/ci.yml"
if [[ ! -f "${readme_path}" ]]; then
  echo "Missing NullClaw README: ${readme_path}" >&2
  exit 1
fi
if [[ ! -f "${ci_workflow_path}" ]]; then
  echo "Missing NullClaw CI workflow: ${ci_workflow_path}" >&2
  exit 1
fi
if [[ ! -f "${source_scorecard_path}" ]]; then
  echo "Missing source scorecard: ${source_scorecard_path}" >&2
  exit 1
fi

zig_status="missing"
zig_version=""
if command -v zig >/dev/null 2>&1; then
  zig_status="available"
  zig_version="$(zig version 2>/dev/null || true)"
fi

mkdir -p "$(dirname "${output_path}")"
python3 - "${readme_path}" "${ci_workflow_path}" "${source_scorecard_path}" "${output_path}" "${zig_status}" "${zig_version}" <<'PY'
import json
import pathlib
import re
import sys
from datetime import datetime, timezone

readme_path = pathlib.Path(sys.argv[1])
ci_workflow_path = pathlib.Path(sys.argv[2])
source_scorecard_path = pathlib.Path(sys.argv[3])
output_path = pathlib.Path(sys.argv[4])
zig_status = sys.argv[5]
zig_version = sys.argv[6]

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
        r"\|\s*\*\*Startup \(0\.8 GHz\)\*\*.*?\*\*<\s*([0-9]+(?:\.[0-9]+)?)\s*ms\*\*",
        r"Boots in <\s*([0-9]+(?:\.[0-9]+)?)\s*ms",
    ]
)
idle_rss_mb = extract_number(
    [
        r"\|\s*\*\*RAM\*\*.*?\*\*~\s*([0-9]+(?:\.[0-9]+)?)\s*MB\*\*",
        r"~\s*([0-9]+(?:\.[0-9]+)?)\s*MB\s+RAM",
    ]
)
binary_size_kb = extract_number(
    [
        r"\|\s*\*\*Binary Size\*\*.*?\*\*([0-9]+(?:\.[0-9]+)?)\s*KB\*\*",
        r"\*\*([0-9]+(?:\.[0-9]+)?)\s*KB binary",
    ]
)
binary_size_mb = round(binary_size_kb / 1024, 3) if binary_size_kb is not None else None

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
        "project": "nullclaw",
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "snapshot_id": "competitive-v2-nullclaw-local-ingest",
        "ingest_method": "local_readme_benchmark_snapshot_with_scorecard_fallback",
        "ingest_source": {
            "nullclaw_readme": str(readme_path),
            "nullclaw_ci_workflow": str(ci_workflow_path),
            "source_scorecard": str(source_scorecard_path),
        },
        "execution_feasibility": {
            "zig_status": zig_status,
            "zig_version": zig_version or None,
            "benchmark_execution_feasible": zig_status == "available" and zig_version == "0.15.2",
            "reason": "zig 0.15.2 unavailable on host; ingested best-available local artifacts"
            if not (zig_status == "available" and zig_version == "0.15.2")
            else "zig 0.15.2 detected; local benchmark execution may be possible",
        },
        "performance_metric_sources": {
            "startup_ms": "nullclaw README benchmark snapshot (startup row: <8 ms at 0.8 GHz)",
            "idle_rss_mb": "nullclaw README benchmark snapshot (RAM row: ~1 MB)",
            "binary_size_mb": "nullclaw README benchmark snapshot (binary row: 678 KB)",
            "dispatch_latency_p95_ms": "fallback from source scorecard due missing local benchmark artifact",
            "throughput_ops_per_sec": "fallback from source scorecard due missing local benchmark artifact",
            "container_size_mb": "fallback from source scorecard due missing local benchmark artifact",
        },
    }
)
report["performance"] = performance

output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "nullclaw-benchmark-ingest: ${output_path}"
