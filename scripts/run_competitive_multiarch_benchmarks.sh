#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

usage() {
  cat <<'USAGE'
Usage: ./scripts/run_competitive_multiarch_benchmarks.sh [--runs N] [--profile PROFILE] [--binder-mode MODE] [--platforms CSV] [--output PATH] [--zeroclaw-json PATH] [--nullclaw-json PATH] [--openclaw-json PATH] [--baseline PATH]

Runs Quasar competitive benchmark + direct harness reports for each platform in CSV.
Default platforms: linux/arm64,linux/arm/v7.
Writes per-platform artifacts under tests/ plus a matrix summary report.
USAGE
}

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${project_root}/tests/competitive_multiarch_benchmark_report.json"
runs=50
profile="${BUILD_PROFILE:-edge-speed}"
binder_mode="${BINDER_MODE:-}"
platforms="${BENCHMARK_PLATFORMS:-linux/arm64,linux/arm/v7}"
zeroclaw_json="${ZEROCLAW_JSON:-}"
nullclaw_json="${NULLCLAW_JSON:-}"
openclaw_json="${OPENCLAW_JSON:-}"
baseline_path="${BASELINE_PATH:-}"
container_image="${ADA_CONTAINER_IMAGE:-debian:bookworm}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs)
      [[ $# -ge 2 ]] || { echo "Missing value for --runs" >&2; exit 2; }
      runs="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || { echo "Missing value for --profile" >&2; exit 2; }
      profile="$2"
      shift 2
      ;;
    --binder-mode)
      [[ $# -ge 2 ]] || { echo "Missing value for --binder-mode" >&2; exit 2; }
      binder_mode="$2"
      shift 2
      ;;
    --platforms)
      [[ $# -ge 2 ]] || { echo "Missing value for --platforms" >&2; exit 2; }
      platforms="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "Missing value for --output" >&2; exit 2; }
      output_path="$2"
      shift 2
      ;;
    --zeroclaw-json)
      [[ $# -ge 2 ]] || { echo "Missing value for --zeroclaw-json" >&2; exit 2; }
      zeroclaw_json="$2"
      shift 2
      ;;
    --nullclaw-json)
      [[ $# -ge 2 ]] || { echo "Missing value for --nullclaw-json" >&2; exit 2; }
      nullclaw_json="$2"
      shift 2
      ;;
    --openclaw-json)
      [[ $# -ge 2 ]] || { echo "Missing value for --openclaw-json" >&2; exit 2; }
      openclaw_json="$2"
      shift 2
      ;;
    --baseline)
      [[ $# -ge 2 ]] || { echo "Missing value for --baseline" >&2; exit 2; }
      baseline_path="$2"
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

if ! [[ "${runs}" =~ ^[1-9][0-9]*$ ]]; then
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

if [[ -n "${binder_mode}" ]]; then
  case "${binder_mode}" in
    portable|minimal) ;;
    *)
      echo "--binder-mode must be one of: portable, minimal" >&2
      exit 2
      ;;
  esac
fi

for optional_json in "${zeroclaw_json}" "${nullclaw_json}" "${openclaw_json}"; do
  if [[ -n "${optional_json}" && ! -f "${optional_json}" ]]; then
    echo "Missing JSON input: ${optional_json}" >&2
    exit 1
  fi
done
if [[ -n "${baseline_path}" && ! -f "${baseline_path}" ]]; then
  echo "Missing baseline config: ${baseline_path}" >&2
  exit 1
fi

normalize_arch() {
  case "$1" in
    x86_64|amd64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    armv7l|armv7|armhf) printf 'arm/v7\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

host_platform="$(printf '%s/%s\n' "$(uname -s | tr '[:upper:]' '[:lower:]')" "$(normalize_arch "$(uname -m | tr '[:upper:]' '[:lower:]')")")"

tmp_results="$(mktemp)"
cleanup() {
  rm -f "${tmp_results}"
}
trap cleanup EXIT

IFS=',' read -r -a platform_list <<<"${platforms}"
for raw_platform in "${platform_list[@]}"; do
  platform="${raw_platform//[[:space:]]/}"
  if [[ -z "${platform}" ]]; then
    continue
  fi
  if ! [[ "${platform}" =~ ^[a-z0-9._-]+/[a-z0-9._-]+(/[a-z0-9._-]+)?$ ]]; then
    echo "Invalid platform entry: ${platform}" >&2
    exit 2
  fi

  platform_id="${platform//\//_}"
  quasar_report="${project_root}/tests/competitive_benchmark_report_${platform_id}.json"
  direct_report="${project_root}/tests/competitive_direct_benchmark_report_${platform_id}.json"

  quasar_args=(--runs "${runs}" --profile "${profile}" --target-platform "${platform}" --output "${quasar_report}")
  if [[ -n "${binder_mode}" ]]; then
    quasar_args+=(--binder-mode "${binder_mode}")
  fi
  if [[ -n "${zeroclaw_json}" ]]; then
    quasar_args+=(--zeroclaw-json "${zeroclaw_json}")
  fi
  if [[ -n "${nullclaw_json}" ]]; then
    quasar_args+=(--nullclaw-json "${nullclaw_json}")
  fi

  COMPETITIVE_FORCE_CONTAINER=1 ADA_CONTAINER_PLATFORM="${platform}" ADA_CONTAINER_IMAGE="${container_image}" "${project_root}/scripts/run_competitive_benchmarks.sh" "${quasar_args[@]}" >/dev/null

  direct_args=(--quasar-report "${quasar_report}" --output "${direct_report}")
  if [[ -n "${zeroclaw_json}" ]]; then
    direct_args+=(--zeroclaw-json "${zeroclaw_json}")
  fi
  if [[ -n "${nullclaw_json}" ]]; then
    direct_args+=(--nullclaw-json "${nullclaw_json}")
  fi
  if [[ -n "${openclaw_json}" ]]; then
    direct_args+=(--openclaw-json "${openclaw_json}")
  fi
  if [[ -n "${baseline_path}" ]]; then
    direct_args+=(--baseline "${baseline_path}")
  fi

  "${project_root}/scripts/run_direct_competitor_harness.sh" "${direct_args[@]}" >/dev/null

  printf '%s|%s|%s\n' "${platform}" "${quasar_report#${project_root}/}" "${direct_report#${project_root}/}" >>"${tmp_results}"
  echo "competitive-bench-multiarch: ${platform}=pass"
done

if [[ ! -s "${tmp_results}" ]]; then
  echo "No benchmark platforms were provided." >&2
  exit 2
fi

mkdir -p "$(dirname "${output_path}")"
generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
python3 - "${output_path}" "${generated_at}" "${runs}" "${profile}" "${binder_mode}" "${host_platform}" "${tmp_results}" <<'PY'
import json
import pathlib
import sys

output_path = pathlib.Path(sys.argv[1])
generated_at = sys.argv[2]
runs = int(sys.argv[3])
profile = sys.argv[4]
binder_mode = sys.argv[5]
host_platform = sys.argv[6]
results_path = pathlib.Path(sys.argv[7])

targets = []
for line in results_path.read_text(encoding="utf-8").splitlines():
    platform, quasar_report, direct_report = line.split("|", 2)
    targets.append(
        {
            "platform": platform,
            "quasar_report": quasar_report,
            "direct_harness_report": direct_report,
        }
    )

payload = {
    "generated_at": generated_at,
    "benchmark_runs": runs,
    "build_profile": profile,
    "binder_mode": binder_mode or None,
    "host_platform": host_platform,
    "targets": targets,
}
output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "competitive-bench-multiarch: report=${output_path}"
