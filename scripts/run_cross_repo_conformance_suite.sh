#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_report_path="${project_root}/tests/cross_repo_conformance_report.json"
report_path="${CONFORMANCE_REPORT_PATH:-${default_report_path}}"
if [[ "${report_path}" != /* ]]; then
  report_path="${project_root}/${report_path}"
fi

declare -a ada_suites=(
  "channel-security|tests/channel_security_policy.gpr|tests/channel_security_policy"
  "provider-routing|tests/provider_routing_fallback_policy.gpr|tests/provider_routing_fallback_policy"
  "plugin-capability|tests/plugin_capability_policy.gpr|tests/plugin_capability_policy"
  "memory-retention|tests/memory_backend_suite_policy.gpr|tests/memory_backend_suite_policy"
  "runtime-guards|tests/runtime_executor_policy.gpr|tests/runtime_executor_policy"
  "competitive-v2-security-regression-fuzz|tests/competitive_v2_security_regression_fuzz_suite.gpr|tests/competitive_v2_security_regression_fuzz_suite"
  "autonomy|tests/autonomy_guardrails_policy.gpr|tests/autonomy_guardrails_policy"
  "crypto-runtime|tests/security_secrets_tests.gpr|tests/security_secrets_tests"
  "config-migration|tests/config_migration_policy.gpr|tests/config_migration_policy"
  "pairing-lockout|tests/gateway_auth_policy.gpr|tests/gateway_auth_policy"
  "allowlist-wiring|tests/channel_adapter_policy.gpr|tests/channel_adapter_policy"
)

declare -a command_suites=(
  "audit-log-persistence|scripts/check_audit_event_log.sh|"
  "gateway-doctor-startup-guard|scripts/check_gateway_doctor.sh|"
  "bootstrap-validation|scripts/bootstrap_toolchain.sh|--validate"
)

if [[ "${CONFORMANCE_FORCE_LOCAL:-0}" != "1" ]]; then
  if "${project_root}/scripts/check_toolchain.sh" --quiet >/dev/null 2>&1; then
    toolchain_mode="host"
  else
    echo "conformance-suite: using container toolchain"
    exec "${project_root}/scripts/run_container_ci.sh" conformance-suite
  fi
else
  toolchain_mode="container"
fi

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
overall_status="pass"
declare -a suite_json_entries=()

for suite in "${ada_suites[@]}"; do
  IFS='|' read -r suite_id project_file binary_file <<<"${suite}"
  suite_status="pass"
  suite_exit_code=0

  if gprbuild -P "${project_root}/${project_file}" >/dev/null 2>&1; then
    if "${project_root}/${binary_file}" >/dev/null 2>&1; then
      :
    else
      suite_status="fail"
      suite_exit_code=$?
    fi
  else
    suite_status="fail"
    suite_exit_code=$?
  fi

  if [[ "${suite_status}" == "fail" ]]; then
    overall_status="fail"
  fi

  echo "conformance-suite: ${suite_id}=${suite_status}"
  suite_json_entries+=("    {\"suite\":\"${suite_id}\",\"status\":\"${suite_status}\",\"exit_code\":${suite_exit_code}}")
done

for suite in "${command_suites[@]}"; do
  IFS='|' read -r suite_id script_file script_arg <<<"${suite}"
  suite_status="pass"
  suite_exit_code=0

  if [[ -n "${script_arg}" ]]; then
    if "${project_root}/${script_file}" "${script_arg}" >/dev/null 2>&1; then
      :
    else
      suite_status="fail"
      suite_exit_code=$?
    fi
  else
    if "${project_root}/${script_file}" >/dev/null 2>&1; then
      :
    else
      suite_status="fail"
      suite_exit_code=$?
    fi
  fi

  if [[ "${suite_status}" == "fail" ]]; then
    overall_status="fail"
  fi

  echo "conformance-suite: ${suite_id}=${suite_status}"
  suite_json_entries+=("    {\"suite\":\"${suite_id}\",\"status\":\"${suite_status}\",\"exit_code\":${suite_exit_code}}")
done

{
  printf '{\n'
  printf '  "generated_at": "%s",\n' "${generated_at}"
  printf '  "toolchain_mode": "%s",\n' "${toolchain_mode}"
  printf '  "overall_status": "%s",\n' "${overall_status}"
  printf '  "suites": [\n'
  for i in "${!suite_json_entries[@]}"; do
    if [[ "${i}" -gt 0 ]]; then
      printf ',\n'
    fi
    printf '%s' "${suite_json_entries[${i}]}"
  done
  printf '\n  ]\n'
  printf '}\n'
} >"${report_path}"

echo "conformance-suite: report=${report_path}"
if [[ "${overall_status}" != "pass" ]]; then
  exit 1
fi
