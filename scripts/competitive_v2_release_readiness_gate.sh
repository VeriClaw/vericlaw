#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report_path="${project_root}/tests/competitive_v2_release_readiness_gate_report.json"
generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
overall_status="pass"
bench_runs="${V2_READINESS_BENCH_RUNS:-50}"
readiness_image_name="${V2_READINESS_IMAGE_NAME:-quasar-claw-lab}"
readiness_image_tag="${V2_READINESS_IMAGE_TAG:-v2-readiness-gate}"
readiness_image_ref="${readiness_image_name}:${readiness_image_tag}"
competitive_benchmark_report_rel_path="tests/competitive_benchmark_report.json"
competitive_direct_report_rel_path="tests/competitive_direct_benchmark_report.json"
competitive_scorecard_report_rel_path="tests/competitive_scorecard_report.json"
competitive_regression_report_rel_path="tests/competitive_regression_gate_report.json"
competitive_final_report_rel_path="tests/competitive_v2_final_competitive_report.json"
conformance_report_rel_path="tests/cross_repo_conformance_report.json"
smoke_report_rel_path="tests/cross_platform_smoke_report.json"
vulnerability_license_report_rel_path="tests/vulnerability_license_gate_report.json"
supply_chain_attestation_report_rel_path="tests/supply_chain_attestation_report.json"
supply_chain_verification_report_rel_path="tests/supply_chain_verification_report.json"
step_logs_dir="${project_root}/tests/competitive_v2_release_readiness_step_logs"
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
    echo "competitive-v2-release-readiness-gate: ${step_id}=fail (log: ${step_log_path})"
    tail -n 20 "${step_log_path}" | sed 's/^/  /'
  else
    echo "competitive-v2-release-readiness-gate: ${step_id}=pass"
  fi
}

run_step "competitive-bench" "${project_root}/scripts/run_competitive_benchmarks.sh" --runs "${bench_runs}" --profile edge-speed --output "${project_root}/${competitive_benchmark_report_rel_path}"
run_step "competitive-direct-harness" "${project_root}/scripts/run_direct_competitor_harness.sh" --quasar-report "${project_root}/${competitive_benchmark_report_rel_path}" --output "${project_root}/${competitive_direct_report_rel_path}"
run_step "competitive-regression-gate" "${project_root}/scripts/check_competitive_baseline.sh" --report "${project_root}/${competitive_benchmark_report_rel_path}" --direct-report "${project_root}/${competitive_direct_report_rel_path}" --scorecard-report "${project_root}/${competitive_scorecard_report_rel_path}" --regression-report "${project_root}/${competitive_regression_report_rel_path}"
run_step "competitive-final-report" "${project_root}/scripts/generate_competitive_v2_final_report.sh" --regression-report "${project_root}/${competitive_regression_report_rel_path}" --scorecard-report "${project_root}/${competitive_scorecard_report_rel_path}" --direct-report "${project_root}/${competitive_direct_report_rel_path}" --output "${project_root}/${competitive_final_report_rel_path}"
run_step "conformance-suite" env CONFORMANCE_REPORT_PATH="${conformance_report_rel_path}" make -C "${project_root}" conformance-suite
run_step "release-image-build" env IMAGE_NAME="${readiness_image_name}" IMAGE_TAG="${readiness_image_tag}" make -C "${project_root}" image-build-local
run_step "vulnerability-license-gate" env IMAGE_REF="${readiness_image_ref}" make -C "${project_root}" vulnerability-license-gate
run_step "cross-platform-smoke" env SMOKE_FAIL_ON_NON_BLOCKING=true "${project_root}/scripts/run_cross_platform_smoke_suite.sh"
run_step "supply-chain-attestation" "${project_root}/scripts/generate_attestation_artifacts.sh"
run_step "supply-chain-verification" env REQUIRE_TRUST_METADATA="${V2_READINESS_REQUIRE_TRUST_METADATA:-false}" REQUIRE_IMAGE_SIGNATURE="${V2_READINESS_REQUIRE_IMAGE_SIGNATURE:-false}" "${project_root}/scripts/verify_supply_chain_artifacts.sh"

python3 - "${report_path}" "${generated_at}" "${overall_status}" "${tmp_results}" "${competitive_benchmark_report_rel_path}" "${competitive_direct_report_rel_path}" "${competitive_scorecard_report_rel_path}" "${competitive_regression_report_rel_path}" "${competitive_final_report_rel_path}" "${conformance_report_rel_path}" "${smoke_report_rel_path}" "${vulnerability_license_report_rel_path}" "${supply_chain_attestation_report_rel_path}" "${supply_chain_verification_report_rel_path}" "${step_logs_rel_path}" <<'PY'
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
competitive_final_report_rel_path = sys.argv[9]
conformance_report_rel_path = sys.argv[10]
smoke_report_rel_path = sys.argv[11]
vulnerability_license_report_rel_path = sys.argv[12]
supply_chain_attestation_report_rel_path = sys.argv[13]
supply_chain_verification_report_rel_path = sys.argv[14]
step_logs_rel_path = sys.argv[15]

steps = []
for line in results_path.read_text(encoding="utf-8").splitlines():
    step, status, code, log_path = line.split("|", 3)
    steps.append({"step": step, "status": status, "exit_code": int(code), "log_path": log_path})

payload = {
    "generated_at": generated_at,
    "overall_status": overall_status,
    "summary": {
        "total_steps": len(steps),
        "passed_steps": sum(1 for step in steps if step.get("status") == "pass"),
        "failed_steps": sum(1 for step in steps if step.get("status") == "fail"),
    },
    "artifacts": {
        "competitive_benchmark_report": competitive_benchmark_report_rel_path,
        "competitive_direct_harness_report": competitive_direct_report_rel_path,
        "competitive_scorecard_report": competitive_scorecard_report_rel_path,
        "competitive_regression_report": competitive_regression_report_rel_path,
        "competitive_final_report": competitive_final_report_rel_path,
        "conformance_report": conformance_report_rel_path,
        "cross_platform_smoke_report": smoke_report_rel_path,
        "vulnerability_license_gate_report": vulnerability_license_report_rel_path,
        "supply_chain_attestation_report": supply_chain_attestation_report_rel_path,
        "supply_chain_verification_report": supply_chain_verification_report_rel_path,
        "step_logs_dir": step_logs_rel_path,
    },
    "steps": steps,
}
report_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "competitive-v2-release-readiness-gate: report=${report_path}"
if [[ "${overall_status}" != "pass" ]]; then
  exit 1
fi
