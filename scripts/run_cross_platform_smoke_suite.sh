#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report_path="${project_root}/tests/cross_platform_smoke_report.json"
generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
overall_status="pass"
probe_image="${SMOKE_PROBE_IMAGE:-${ADA_CONTAINER_IMAGE:-alire/gnat:community-latest}}"
fail_on_non_blocking="${SMOKE_FAIL_ON_NON_BLOCKING:-false}"

if [[ "${fail_on_non_blocking}" != "true" && "${fail_on_non_blocking}" != "false" ]]; then
  echo "SMOKE_FAIL_ON_NON_BLOCKING must be true or false." >&2
  exit 2
fi

tmp_results="$(mktemp)"
cleanup() {
  rm -f "${tmp_results}"
}
trap cleanup EXIT

sanitize_detail() {
  local detail="${1:-}"
  detail="${detail//$'\n'/ }"
  detail="${detail//|//}"
  printf '%s' "${detail}"
}

record_suite() {
  local suite_id="$1"
  local suite_status="$2"
  local exit_code="$3"
  local blocking="$4"
  local category="$5"
  local platform="$6"
  local detail
  detail="$(sanitize_detail "${7:-}")"
  printf '%s|%s|%s|%s|%s|%s|%s\n' "${suite_id}" "${suite_status}" "${exit_code}" "${blocking}" "${category}" "${platform}" "${detail}" >>"${tmp_results}"
  echo "cross-platform-smoke: ${suite_id}=${suite_status} (${blocking},${category},${platform})"
}

run_suite() {
  local suite_id="$1"
  local blocking="$2"
  local category="$3"
  local platform="$4"
  shift 4
  local exit_code
  if "$@" >/dev/null 2>&1; then
    record_suite "${suite_id}" "pass" 0 "${blocking}" "${category}" "${platform}" ""
    return
  fi

  exit_code=$?
  record_suite "${suite_id}" "fail" "${exit_code}" "${blocking}" "${category}" "${platform}" "Command exited with status ${exit_code}."
  if [[ "${blocking}" == "required" || "${fail_on_non_blocking}" == "true" ]]; then
    overall_status="fail"
  fi
}

run_required_suite() {
  local suite_id="$1"
  local category="$2"
  local platform="$3"
  shift 3
  run_suite "${suite_id}" required "${category}" "${platform}" "$@"
}

run_non_blocking_suite() {
  local suite_id="$1"
  local category="$2"
  local platform="$3"
  shift 3
  run_suite "${suite_id}" non_blocking "${category}" "${platform}" "$@"
}

skip_suite() {
  local suite_id="$1"
  local blocking="$2"
  local category="$3"
  local platform="$4"
  local exit_code="$5"
  local detail="$6"
  record_suite "${suite_id}" "skip" "${exit_code}" "${blocking}" "${category}" "${platform}" "${detail}"
}

fail_suite() {
  local suite_id="$1"
  local blocking="$2"
  local category="$3"
  local platform="$4"
  local exit_code="$5"
  local detail="$6"
  record_suite "${suite_id}" "fail" "${exit_code}" "${blocking}" "${category}" "${platform}" "${detail}"
  overall_status="fail"
}

docker_ready=0
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker_ready=1
fi

can_run_container_platform() {
  local platform="$1"
  if [[ "${docker_ready}" -ne 1 ]]; then
    return 1
  fi
  if [[ "${platform}" == "linux/amd64" ]]; then
    return 0
  fi
  docker run --rm --platform "${platform}" --entrypoint /bin/sh "${probe_image}" -lc 'exit 0' >/dev/null 2>&1
}

if can_run_container_platform "linux/amd64"; then
  run_required_suite "linux-amd64-container-check" "container" "linux/amd64" env ADA_CONTAINER_PLATFORM=linux/amd64 "${project_root}/scripts/run_container_ci.sh" check
else
  fail_suite "linux-amd64-container-check" "required" "container" "linux/amd64" 1 "Docker runtime unavailable for linux/amd64 container checks."
fi

if can_run_container_platform "linux/arm64"; then
  run_non_blocking_suite "linux-arm64-container-check" "container" "linux/arm64" env ADA_CONTAINER_PLATFORM=linux/arm64 "${project_root}/scripts/run_container_ci.sh" check
else
  skip_suite "linux-arm64-container-check" "non_blocking" "container" "linux/arm64" 0 "Container platform linux/arm64 is not feasible in this environment."
fi

if can_run_container_platform "linux/arm/v7"; then
  run_non_blocking_suite "linux-arm-v7-container-check" "container" "linux/arm/v7" env ADA_CONTAINER_PLATFORM=linux/arm/v7 "${project_root}/scripts/run_container_ci.sh" check
else
  skip_suite "linux-arm-v7-container-check" "non_blocking" "container" "linux/arm/v7" 0 "Container platform linux/arm/v7 is not feasible in this environment."
fi

if "${project_root}/scripts/check_toolchain.sh" --quiet >/dev/null 2>&1; then
  run_non_blocking_suite "native-host-check" "native" "host" make -C "${project_root}" check
else
  skip_suite "native-host-check" "non_blocking" "native" "host" 0 "Host Ada/SPARK toolchain unavailable; native smoke check skipped."
fi

run_required_suite "gateway-doctor-startup-guard" "security" "host" "${project_root}/scripts/check_gateway_doctor.sh"
run_required_suite "audit-event-log-security-controls" "security" "host" "${project_root}/scripts/check_audit_event_log.sh"
run_required_suite "operator-console-check" "service" "host" "${project_root}/scripts/check_operator_console.sh"
run_required_suite "docker-runtime-security-profile" "security" "host" "${project_root}/scripts/check_docker_runtime_bundle.sh"
run_required_suite "service-supervisor-packages" "service" "host" "${project_root}/scripts/check_service_supervisors.sh"

python3 - "${report_path}" "${generated_at}" "${overall_status}" "${tmp_results}" "${fail_on_non_blocking}" <<'PY'
import json
import pathlib
import sys

report_path = pathlib.Path(sys.argv[1])
generated_at = sys.argv[2]
overall_status = sys.argv[3]
results_path = pathlib.Path(sys.argv[4])
fail_on_non_blocking = sys.argv[5] == "true"

suites = []
for line in results_path.read_text(encoding="utf-8").splitlines():
    suite, status, code, blocking, category, platform, detail = line.split("|", 6)
    suites.append(
        {
            "suite": suite,
            "status": status,
            "exit_code": int(code),
            "blocking": blocking == "required",
            "blocking_mode": blocking,
            "category": category,
            "platform": platform,
            "detail": detail or None,
        }
    )

payload = {
    "generated_at": generated_at,
    "overall_status": overall_status,
    "status_semantics": {
        "pass": "Suite executed successfully.",
        "skip": "Suite was not executed due to feasibility constraints.",
        "fail": "Suite executed and failed, or required feasibility checks failed.",
    },
    "policy": {
        "fail_on_non_blocking": fail_on_non_blocking,
    },
    "summary": {
        "total_suites": len(suites),
        "passed_suites": sum(1 for suite in suites if suite.get("status") == "pass"),
        "skipped_suites": sum(1 for suite in suites if suite.get("status") == "skip"),
        "failed_suites": sum(1 for suite in suites if suite.get("status") == "fail"),
        "required_failed_suites": sum(
            1 for suite in suites if suite.get("status") == "fail" and suite.get("blocking_mode") == "required"
        ),
        "non_blocking_failed_suites": sum(
            1 for suite in suites if suite.get("status") == "fail" and suite.get("blocking_mode") != "required"
        ),
    },
    "suites": suites,
}
report_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "cross-platform-smoke: report=${report_path}"
if [[ "${overall_status}" != "pass" ]]; then
  exit 1
fi
