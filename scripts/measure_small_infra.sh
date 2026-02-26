#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

usage() {
  cat <<'EOF'
Usage: ./scripts/measure_small_infra.sh [--runs N] [--profile PROFILE] [--binder-mode MODE] [--json PATH]

Builds vericlaw with the requested BUILD_PROFILE and prints benchmark metrics.
Profiles: dev, small, edge-size, edge-speed.
Binder modes: portable, minimal.
EOF
}

runs=50
profile="${BUILD_PROFILE:-small}"
binder_mode="${BINDER_MODE:-}"
json_output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --runs" >&2
        exit 2
      fi
      runs="$2"
      shift 2
      ;;
    --profile)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --profile" >&2
        exit 2
      fi
      profile="$2"
      shift 2
      ;;
    --binder-mode)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --binder-mode" >&2
        exit 2
      fi
      binder_mode="$2"
      shift 2
      ;;
    --json)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --json" >&2
        exit 2
      fi
      json_output="$2"
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

if ! [[ "$runs" =~ ^[1-9][0-9]*$ ]]; then
  echo "--runs must be a positive integer" >&2
  exit 2
fi

case "${profile}" in
  dev|small|edge-size|edge-speed) ;;
  *)
    echo "--profile must be one of: dev, small, edge-size, edge-speed" >&2
    exit 2
    ;;
esac

if [[ -z "${binder_mode}" ]]; then
  case "${profile}" in
    edge-size)
      binder_mode="minimal"
      ;;
    *)
      binder_mode="portable"
      ;;
  esac
fi

case "${binder_mode}" in
  portable|minimal) ;;
  *)
    echo "--binder-mode must be one of: portable, minimal" >&2
    exit 2
    ;;
esac

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_file="${project_root}/vericlaw.gpr"
binary_path="${project_root}/vericlaw"

"${project_root}/scripts/check_toolchain.sh" --quiet >/dev/null
gprbuild -q -P "${project_file}" -XBUILD_PROFILE="${profile}" -XBINDER_MODE="${binder_mode}"

if [[ ! -x "${binary_path}" ]]; then
  echo "Expected executable not found: ${binary_path}" >&2
  exit 1
fi

binary_bytes="$(wc -c < "${binary_path}" | tr -d '[:space:]')"
metrics_json="$(mktemp)"
python3 - "${binary_path}" "${runs}" "${metrics_json}" "${profile}" "${binder_mode}" <<'PY'
import json
import math
import subprocess
import sys
import time

binary = sys.argv[1]
runs = int(sys.argv[2])
output = sys.argv[3]
profile = sys.argv[4]
binder_mode = sys.argv[5]

durations_ms = []
for _ in range(runs):
    started = time.perf_counter()
    subprocess.run([binary], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    durations_ms.append((time.perf_counter() - started) * 1000.0)

durations_sorted = sorted(durations_ms)
p95_index = max(0, math.ceil(0.95 * len(durations_sorted)) - 1)
total_ms = sum(durations_ms)

payload = {
    "startup_ms": durations_ms[0],
    "runtime_avg_ms": total_ms / len(durations_ms),
    "dispatch_latency_p95_ms": durations_sorted[p95_index],
    "throughput_ops_per_sec": (len(durations_ms) * 1000.0 / total_ms) if total_ms > 0 else 0.0,
    "profile": profile,
    "binder_mode": binder_mode,
    "runs": runs,
}

with open(output, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, sort_keys=True)
PY

read -r startup_ms runtime_avg_ms dispatch_latency_p95_ms throughput_ops_per_sec < <(
  python3 - "${metrics_json}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)

print(
    f"{data['startup_ms']:.3f} "
    f"{data['runtime_avg_ms']:.3f} "
    f"{data['dispatch_latency_p95_ms']:.3f} "
    f"{data['throughput_ops_per_sec']:.3f}"
)
PY
)

if [[ -n "${json_output}" ]]; then
  mkdir -p "$(dirname "${json_output}")"
  cp "${metrics_json}" "${json_output}"
fi
rm -f "${metrics_json}"

printf 'profile=%s\n' "${profile}"
printf 'binder_mode=%s\n' "${binder_mode}"
printf 'binary=main\n'
printf 'binary_bytes=%s\n' "${binary_bytes}"
printf 'startup_ms=%s\n' "${startup_ms}"
printf 'runtime_avg_ms=%s\n' "${runtime_avg_ms}"
printf 'dispatch_latency_p95_ms=%s\n' "${dispatch_latency_p95_ms}"
printf 'throughput_ops_per_sec=%s\n' "${throughput_ops_per_sec}"
printf 'runs=%s\n' "${runs}"
