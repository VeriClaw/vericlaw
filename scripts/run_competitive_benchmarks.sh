#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

usage() {
  cat <<'EOF'
Usage: ./scripts/run_competitive_benchmarks.sh [--runs N] [--profile PROFILE] [--binder-mode MODE] [--target-platform PLATFORM] [--output PATH] [--zeroclaw-json PATH] [--nullclaw-json PATH]

Runs local Quasar measurements and writes a competitive benchmark JSON report.
Optional competitor JSON paths can also be provided via ZEROCLAW_JSON / NULLCLAW_JSON.
EOF
}

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${project_root}/tests/competitive_benchmark_report.json"
zeroclaw_json="${ZEROCLAW_JSON:-}"
nullclaw_json="${NULLCLAW_JSON:-}"
runs=50
profile="${BUILD_PROFILE:-edge-speed}"
binder_mode="${BINDER_MODE:-}"
target_platform="${TARGET_PLATFORM:-${ADA_CONTAINER_PLATFORM:-}}"
force_container="${COMPETITIVE_FORCE_CONTAINER:-0}"

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
    --output)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --output" >&2
        exit 2
      fi
      output_path="$2"
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
    --target-platform)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --target-platform" >&2
        exit 2
      fi
      target_platform="$2"
      shift 2
      ;;
    --zeroclaw-json)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --zeroclaw-json" >&2
        exit 2
      fi
      zeroclaw_json="$2"
      shift 2
      ;;
    --nullclaw-json)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --nullclaw-json" >&2
        exit 2
      fi
      nullclaw_json="$2"
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

if [[ -n "${target_platform}" ]] && ! [[ "${target_platform}" =~ ^[a-z0-9._-]+/[a-z0-9._-]+(/[a-z0-9._-]+)?$ ]]; then
  echo "--target-platform must look like os/arch or os/arch/variant" >&2
  exit 2
fi

if [[ "${force_container}" != "0" && "${force_container}" != "1" ]]; then
  echo "COMPETITIVE_FORCE_CONTAINER must be 0 or 1" >&2
  exit 2
fi

normalize_arch() {
  case "$1" in
    x86_64|amd64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    armv7l|armv7|armhf) printf 'arm/v7\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

detect_host_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(normalize_arch "$(uname -m | tr '[:upper:]' '[:lower:]')")"
  printf '%s/%s\n' "${os}" "${arch}"
}

host_platform="$(detect_host_platform)"
host_arch="${host_platform#*/}"
container_platform="${target_platform:-${ADA_CONTAINER_PLATFORM:-linux/${host_arch}}}"

if [[ -n "${target_platform}" ]]; then
  force_container=1
fi

if [[ -n "${zeroclaw_json}" && ! -f "${zeroclaw_json}" ]]; then
  echo "Missing competitor JSON: ${zeroclaw_json}" >&2
  exit 1
fi

if [[ -n "${nullclaw_json}" && ! -f "${nullclaw_json}" ]]; then
  echo "Missing competitor JSON: ${nullclaw_json}" >&2
  exit 1
fi

collect_host_metrics() {
  local measure_output rss_kb rss_trace rss_supported rss_collector pid max_rss current_rss
  measure_output="$("${project_root}/scripts/measure_small_infra.sh" --runs "${runs}" --profile "${profile}" --binder-mode "${binder_mode}")"
  rss_kb=""
  rss_supported=0
  rss_collector="unsupported_host_rss_telemetry"

  if [[ -x /usr/bin/time ]]; then
    rss_trace="$(
      {
        /usr/bin/time -l "${project_root}/main" >/dev/null
      } 2>&1 || true
    )"
    rss_kb="$(awk '/maximum resident set size/ {print $1; exit}' <<<"${rss_trace}")"
    if [[ "${rss_kb}" =~ ^[1-9][0-9]*$ ]]; then
      rss_supported=1
      rss_collector="host_bsd_time_maxrss_kb"
    else
      rss_trace="$(
        {
          /usr/bin/time -f "%M" "${project_root}/main" >/dev/null
        } 2>&1 || true
      )"
      rss_kb="$(tail -n1 <<<"${rss_trace}" | tr -d '[:space:]')"
      if [[ "${rss_kb}" =~ ^[1-9][0-9]*$ ]]; then
        rss_supported=1
        rss_collector="host_gnu_time_maxrss_kb"
      else
        rss_kb=""
      fi
    fi
  fi

  if [[ "${rss_supported}" == "0" && -r /proc/self/status ]]; then
    max_rss=0
    "${project_root}/main" >/dev/null &
    pid=$!
    while :; do
      current_rss="$(awk '/^VmRSS:/ {print $2; exit}' "/proc/${pid}/status" 2>/dev/null || true)"
      if [[ "${current_rss}" =~ ^[0-9]+$ ]] && (( current_rss > max_rss )); then
        max_rss="${current_rss}"
      fi
      if ! kill -0 "${pid}" >/dev/null 2>&1; then
        break
      fi
      sleep 0.001
    done
    wait "${pid}"
    if (( max_rss > 0 )); then
      rss_kb="${max_rss}"
      rss_supported=1
      rss_collector="host_proc_vmrss_peak_kb"
    fi
  fi

  printf '%s\n' "${measure_output}"
  printf 'idle_rss_kb=%s\n' "${rss_kb}"
  printf 'idle_rss_supported=%s\n' "${rss_supported}"
  printf 'idle_rss_collector=%s\n' "${rss_collector}"
  printf 'measurement_mode=host\n'
  printf 'target_platform=%s\n' "${host_platform}"
}

run_container_measurement() {
  local image install_toolchain
  image="$1"
  install_toolchain="$2"
  docker run --rm --platform "${container_platform}" -e RUNS="${runs}" -e INSTALL_TOOLCHAIN="${install_toolchain}" -v "${project_root}:/workspace" -w /workspace "${image}" \
    bash -lc '
      set -euo pipefail
      if [ -d /opt/gnat/bin ]; then
        export PATH=/opt/gnat/bin:$PATH
      fi
      if [ "${INSTALL_TOOLCHAIN}" = "1" ] || ! command -v gprbuild >/dev/null 2>&1; then
        apt-get update >/dev/null
        apt-get install --yes --no-install-recommends gnat gprbuild binutils python3 time >/dev/null
        rm -rf /var/lib/apt/lists/*
      fi
      if ! command -v gnatprove >/dev/null 2>&1; then
        shim_dir="$(mktemp -d)"
        cat >"${shim_dir}/gnatprove" <<'"'"'EOF'"'"'
#!/usr/bin/env sh
if [ "${1:-}" = "--version" ]; then
  echo "gnatprove shim (benchmark container)"
fi
exit 0
EOF
        chmod +x "${shim_dir}/gnatprove"
        export PATH="${shim_dir}:$PATH"
      fi
      gprclean -P vericlaw.gpr >/dev/null 2>&1 || true
      measure_output="$(./scripts/measure_small_infra.sh --runs "${RUNS}" --profile "'"${profile}"'" --binder-mode "'"${binder_mode}"'")"
      rss_kb=""
      rss_supported=0
      rss_collector="unsupported_container_rss_telemetry"
      if [ -x /usr/bin/time ]; then
        rss_trace="$({ /usr/bin/time -f "%M" ./main >/dev/null; } 2>&1 || true)"
        rss_kb="$(printf "%s\n" "${rss_trace}" | tail -n1 | tr -d "[:space:]")"
        if [[ "${rss_kb}" =~ ^[1-9][0-9]*$ ]]; then
          rss_supported=1
          rss_collector="container_gnu_time_maxrss_kb"
        else
          rss_trace="$({ /usr/bin/time -l ./main >/dev/null; } 2>&1 || true)"
          rss_kb="$(printf "%s\n" "${rss_trace}" | awk "/maximum resident set size/ {print \$1; exit}")"
          if [[ "${rss_kb}" =~ ^[1-9][0-9]*$ ]]; then
            rss_supported=1
            rss_collector="container_bsd_time_maxrss_kb"
          else
            rss_kb=""
          fi
        fi
      fi
      if [[ "${rss_supported}" == "0" && -r /proc/self/status ]]; then
        max_rss=0
        ./main >/dev/null &
        pid=$!
        while :; do
          current_rss="$(awk "/^VmRSS:/ {print \$2; exit}" "/proc/${pid}/status" 2>/dev/null || true)"
          if [[ "${current_rss}" =~ ^[0-9]+$ ]] && (( current_rss > max_rss )); then
            max_rss="${current_rss}"
          fi
          if ! kill -0 "${pid}" >/dev/null 2>&1; then
            break
          fi
          sleep 0.001
        done
        wait "${pid}"
        if (( max_rss > 0 )); then
          rss_kb="${max_rss}"
          rss_supported=1
          rss_collector="container_proc_vmrss_peak_kb"
        fi
      fi
      printf "%s\n" "${measure_output}"
      printf "idle_rss_kb=%s\n" "${rss_kb}"
      printf "idle_rss_supported=%s\n" "${rss_supported}"
      printf "idle_rss_collector=%s\n" "${rss_collector}"
      printf "measurement_mode=container\n"
      printf "target_platform=%s\n" "'"${container_platform}"'"
    '
}

collect_container_metrics() {
  local image fallback_image
  image="${ADA_CONTAINER_IMAGE:-alire/gnat:community-latest}"
  fallback_image="${ADA_CONTAINER_FALLBACK_IMAGE:-debian:bookworm}"
  if run_container_measurement "${image}" "0"; then
    return 0
  fi
  if [[ -n "${fallback_image}" && "${fallback_image}" != "${image}" ]]; then
    run_container_measurement "${fallback_image}" "1"
  else
    return 1
  fi
}

collect_container_size_bytes() {
  local image_ref build_if_missing size_bytes
  image_ref="${COMPETITIVE_IMAGE_REF:-vericlaw:benchmark}"
  build_if_missing="${COMPETITIVE_BUILD_IMAGE_IF_MISSING:-1}"

  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    return 0
  fi

  if ! docker image inspect "${image_ref}" >/dev/null 2>&1; then
    if [[ "${build_if_missing}" != "1" ]]; then
      return 0
    fi
    docker build --quiet --file "${project_root}/Dockerfile.release" --tag "${image_ref}" "${project_root}" >/dev/null
  fi

  size_bytes="$(docker image inspect "${image_ref}" --format '{{.Size}}' 2>/dev/null || true)"
  if [[ "${size_bytes}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "${size_bytes}"
  fi
}

if [[ "${force_container}" == "1" ]]; then
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    metrics_output="$(collect_container_metrics)"
  else
    echo "Unable to run Quasar benchmarks: container mode requested but Docker is unavailable." >&2
    exit 1
  fi
elif "${project_root}/scripts/check_toolchain.sh" --quiet >/dev/null 2>&1; then
  metrics_output="$(collect_host_metrics)"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  metrics_output="$(collect_container_metrics)"
else
  echo "Unable to run Quasar benchmarks: host Ada toolchain missing and Docker unavailable." >&2
  exit 1
fi

startup_ms=""
runtime_avg_ms=""
dispatch_latency_p95_ms=""
throughput_ops_per_sec=""
binary_bytes=""
rss_kb=""
rss_supported=""
rss_collector=""
measurement_mode=""
resolved_binder_mode=""
reported_runs=""
reported_target_platform=""
while IFS='=' read -r metric_key metric_value; do
  case "${metric_key}" in
    startup_ms) startup_ms="${metric_value}" ;;
    runtime_avg_ms) runtime_avg_ms="${metric_value}" ;;
    dispatch_latency_p95_ms) dispatch_latency_p95_ms="${metric_value}" ;;
    throughput_ops_per_sec) throughput_ops_per_sec="${metric_value}" ;;
    binary_bytes) binary_bytes="${metric_value}" ;;
    idle_rss_kb) rss_kb="${metric_value}" ;;
    idle_rss_supported) rss_supported="${metric_value}" ;;
    idle_rss_collector) rss_collector="${metric_value}" ;;
    measurement_mode) measurement_mode="${metric_value}" ;;
    binder_mode) resolved_binder_mode="${metric_value}" ;;
    runs) reported_runs="${metric_value}" ;;
    target_platform) reported_target_platform="${metric_value}" ;;
  esac
done <<< "${metrics_output}"
container_size_bytes="$(collect_container_size_bytes || true)"

if [[ -z "${startup_ms}" || -z "${runtime_avg_ms}" || -z "${dispatch_latency_p95_ms}" || -z "${throughput_ops_per_sec}" || -z "${binary_bytes}" || -z "${rss_supported}" || -z "${rss_collector}" || -z "${measurement_mode}" || -z "${resolved_binder_mode}" || -z "${reported_runs}" ]]; then
  echo "Failed to parse benchmark metrics." >&2
  exit 1
fi

decimal_pattern='^[0-9]+([.][0-9]+)?$'
if ! [[ "${startup_ms}" =~ ${decimal_pattern} && "${runtime_avg_ms}" =~ ${decimal_pattern} && "${dispatch_latency_p95_ms}" =~ ${decimal_pattern} && "${throughput_ops_per_sec}" =~ ${decimal_pattern} ]]; then
  echo "Unable to parse decimal benchmark metrics from benchmark run." >&2
  exit 1
fi
if ! [[ "${binary_bytes}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Unable to parse binary size metric from benchmark run." >&2
  exit 1
fi
if ! [[ "${measurement_mode}" =~ ^(host|container)$ ]]; then
  echo "Unable to parse measurement mode from benchmark run." >&2
  exit 1
fi
if ! [[ "${resolved_binder_mode}" =~ ^(portable|minimal)$ ]]; then
  echo "Unable to parse binder mode from benchmark run." >&2
  exit 1
fi
if ! [[ "${rss_supported}" =~ ^[01]$ ]]; then
  echo "Unable to parse memory metric support status from benchmark run." >&2
  exit 1
fi
if ! [[ "${reported_runs}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Unable to parse run count from benchmark run." >&2
  exit 1
fi
if ! awk -v value="${throughput_ops_per_sec}" 'BEGIN { exit (value > 0 ? 0 : 1) }'; then
  echo "Parsed throughput_ops_per_sec must be positive." >&2
  exit 1
fi
if [[ "${rss_supported}" == "1" ]]; then
  if ! [[ "${rss_kb}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Unable to parse supported memory metric from benchmark run." >&2
    exit 1
  fi
  idle_rss_mb="$(awk -v kb="${rss_kb}" 'BEGIN { printf "%.3f", kb / 1024 }')"
else
  if [[ -n "${rss_kb}" && ! "${rss_kb}" =~ ^[0-9]+$ ]]; then
    echo "Unable to parse unsupported memory metric payload from benchmark run." >&2
    exit 1
  fi
  idle_rss_mb=""
fi
if [[ -z "${reported_target_platform}" ]]; then
  reported_target_platform="${host_platform}"
fi
platform_mismatch="false"
if [[ "${reported_target_platform}" != "${host_platform}" ]]; then
  platform_mismatch="true"
fi
binary_size_mb="$(awk -v bytes="${binary_bytes}" 'BEGIN { printf "%.3f", bytes / (1024 * 1024) }')"
container_size_mb=""
if [[ -n "${container_size_bytes}" ]]; then
  container_size_mb="$(awk -v bytes="${container_size_bytes}" 'BEGIN { printf "%.3f", bytes / (1024 * 1024) }')"
fi

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
release_metadata_path="${project_root}/tests/release_metadata.json"

mkdir -p "$(dirname "${output_path}")"

python3 - "${output_path}" "${generated_at}" "${startup_ms}" "${idle_rss_mb}" "${rss_supported}" "${rss_collector}" "${runtime_avg_ms}" "${dispatch_latency_p95_ms}" "${throughput_ops_per_sec}" "${binary_bytes}" "${binary_size_mb}" "${container_size_mb}" "${measurement_mode}" "${profile}" "${resolved_binder_mode}" "${reported_runs}" "${reported_target_platform}" "${host_platform}" "${platform_mismatch}" "${zeroclaw_json}" "${nullclaw_json}" "${release_metadata_path}" <<'PY'
import json
import pathlib
import sys

(
    output_path,
    generated_at,
    startup_ms,
    idle_rss_mb,
    idle_rss_supported,
    idle_rss_collector,
    runtime_avg_ms,
    dispatch_latency_p95_ms,
    throughput_ops_per_sec,
    binary_bytes,
    binary_size_mb,
    container_size_mb,
    measurement_mode,
    profile,
    binder_mode,
    benchmark_runs,
    target_platform,
    host_platform,
    platform_mismatch,
    zeroclaw_path,
    nullclaw_path,
    release_metadata_path,
) = sys.argv[1:]

idle_rss_supported_flag = idle_rss_supported == "1"


def load_optional_json(path):
    if not path:
        return None
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


report = {
    "generated_at": generated_at,
    "quasar": {
        "startup_ms": float(startup_ms),
        "idle_rss_mb": float(idle_rss_mb) if idle_rss_supported_flag and idle_rss_mb else None,
        "dispatch_latency_avg_ms": float(runtime_avg_ms),
        "dispatch_latency_p95_ms": float(dispatch_latency_p95_ms),
        "throughput_ops_per_sec": float(throughput_ops_per_sec),
        "binary_bytes": int(binary_bytes),
        "binary_size_mb": float(binary_size_mb),
        "container_size_mb": float(container_size_mb) if container_size_mb else None,
        "measurement_mode": measurement_mode,
        "metric_availability": {
            "idle_rss_mb": {
                "supported": idle_rss_supported_flag,
                "collector": idle_rss_collector,
            }
        },
        "build_profile": profile,
        "binder_mode": binder_mode,
        "benchmark_runs": int(benchmark_runs),
        "target_platform": target_platform,
        "host_platform": host_platform,
        "platform_mismatch": platform_mismatch == "true",
    },
    "competitors": {
        "zeroclaw": load_optional_json(zeroclaw_path),
        "nullclaw": load_optional_json(nullclaw_path),
    },
}

release_path = pathlib.Path(release_metadata_path)
if release_path.is_file():
    with release_path.open("r", encoding="utf-8") as handle:
        metadata = json.load(handle)
    report["quasar"]["release_metadata"] = {
        "path": "tests/release_metadata.json",
        "generated_at": metadata.get("generated_at"),
        "toolchain_mode": metadata.get("toolchain_mode"),
    }

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(report, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

echo "competitive-bench report: ${output_path}"
