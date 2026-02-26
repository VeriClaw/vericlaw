#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report_path="${project_root}/tests/release_candidate_report.json"
generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
overall_status="pass"
bench_runs="${RC_BENCH_RUNS:-50}"
rc_image_name="${RC_IMAGE_NAME:-vericlaw}"
rc_image_tag="${RC_IMAGE_TAG:-rc-gate}"
rc_image_ref="${rc_image_name}:${rc_image_tag}"
competitive_benchmark_report_rel_path="tests/competitive_benchmark_report.json"
competitive_direct_report_rel_path="tests/competitive_direct_benchmark_report.json"
competitive_scorecard_report_rel_path="tests/competitive_scorecard_report.json"
competitive_regression_report_rel_path="tests/competitive_regression_gate_report.json"
vulnerability_license_report_rel_path="tests/vulnerability_license_gate_report.json"
supply_chain_verification_report_rel_path="tests/supply_chain_verification_report.json"
step_logs_dir="${project_root}/tests/release_candidate_step_logs"
step_logs_rel_path="${step_logs_dir#${project_root}/}"

mkdir -p "${step_logs_dir}"

tmp_results="$(mktemp)"
cleanup() {
  rm -f "${tmp_results}"
}
trap cleanup EXIT

run_step() {
  local step_id="$1"
  shift
  local step_status exit_code step_log_path step_log_rel_path
  step_log_path="${step_logs_dir}/${step_id}.log"
  step_log_rel_path="${step_log_path#${project_root}/}"
  if "$@" >"${step_log_path}" 2>&1; then
    step_status="pass"
    exit_code=0
  else
    exit_code=$?
    step_status="fail"
    overall_status="fail"
  fi
  printf '%s|%s|%s|%s\n' "${step_id}" "${step_status}" "${exit_code}" "${step_log_rel_path}" >>"${tmp_results}"
  if [[ "${step_status}" == "fail" ]]; then
    echo "release-candidate-gate: ${step_id}=fail (log: ${step_log_path})"
    tail -n 20 "${step_log_path}" | sed 's/^/  /'
  else
    echo "release-candidate-gate: ${step_id}=pass"
  fi
}

run_step "release-check" "${project_root}/scripts/release_check.sh"
run_step "competitive-bench" "${project_root}/scripts/run_competitive_benchmarks.sh" --runs "${bench_runs}" --profile edge-speed --output "${project_root}/${competitive_benchmark_report_rel_path}"
run_step "competitive-direct-harness" "${project_root}/scripts/run_direct_competitor_harness.sh" --quasar-report "${project_root}/${competitive_benchmark_report_rel_path}" --output "${project_root}/${competitive_direct_report_rel_path}"
run_step "competitive-baseline" "${project_root}/scripts/check_competitive_baseline.sh" --report "${project_root}/${competitive_benchmark_report_rel_path}" --direct-report "${project_root}/${competitive_direct_report_rel_path}" --scorecard-report "${project_root}/${competitive_scorecard_report_rel_path}" --regression-report "${project_root}/${competitive_regression_report_rel_path}"
run_step "docker-runtime-bundle" "${project_root}/scripts/check_docker_runtime_bundle.sh"
run_step "service-supervisor-packages" "${project_root}/scripts/check_service_supervisors.sh"
run_step "release-image-build" env IMAGE_NAME="${rc_image_name}" IMAGE_TAG="${rc_image_tag}" make -C "${project_root}" image-build-local
run_step "vulnerability-license-gate" env IMAGE_REF="${rc_image_ref}" make -C "${project_root}" vulnerability-license-gate
run_step "cross-platform-smoke" env SMOKE_FAIL_ON_NON_BLOCKING=true "${project_root}/scripts/run_cross_platform_smoke_suite.sh"
run_step "supply-chain-attestation" "${project_root}/scripts/generate_attestation_artifacts.sh"
run_step "supply-chain-verification" env REQUIRE_TRUST_METADATA="${RC_REQUIRE_TRUST_METADATA:-false}" REQUIRE_IMAGE_SIGNATURE="${RC_REQUIRE_IMAGE_SIGNATURE:-false}" "${project_root}/scripts/verify_supply_chain_artifacts.sh"

python3 - "${report_path}" "${generated_at}" "${overall_status}" "${tmp_results}" "${competitive_benchmark_report_rel_path}" "${competitive_direct_report_rel_path}" "${competitive_scorecard_report_rel_path}" "${competitive_regression_report_rel_path}" "${vulnerability_license_report_rel_path}" "${supply_chain_verification_report_rel_path}" "${step_logs_rel_path}" <<'PY'
import json
import pathlib
import sys

report_path = pathlib.Path(sys.argv[1])
generated_at = sys.argv[2]
overall_status = sys.argv[3]
results_path = pathlib.Path(sys.argv[4])
competitive_benchmark_report_rel_path = sys.argv[5]
competitive_direct_report_rel_path = sys.argv[6]
competitive_scorecard_report_rel_path = sys.argv[7]
competitive_regression_report_rel_path = sys.argv[8]
vulnerability_license_report_rel_path = sys.argv[9]
supply_chain_verification_report_rel_path = sys.argv[10]
step_logs_rel_path = sys.argv[11]

steps = []
for line in results_path.read_text(encoding="utf-8").splitlines():
    step, status, code, log_path = line.split("|", 3)
    steps.append({"step": step, "status": status, "exit_code": int(code), "log_path": log_path})

payload = {
    "generated_at": generated_at,
    "overall_status": overall_status,
    "artifacts": {
        "competitive_benchmark_report": competitive_benchmark_report_rel_path,
        "competitive_direct_harness_report": competitive_direct_report_rel_path,
        "competitive_scorecard_report": competitive_scorecard_report_rel_path,
        "competitive_regression_report": competitive_regression_report_rel_path,
        "vulnerability_license_gate_report": vulnerability_license_report_rel_path,
        "supply_chain_verification_report": supply_chain_verification_report_rel_path,
        "step_logs_dir": step_logs_rel_path,
    },
    "steps": steps,
}
report_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "release-candidate-gate: report=${report_path}"
if [[ "${overall_status}" != "pass" ]]; then
  exit 1
fi
