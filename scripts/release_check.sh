#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checksum_manifest_path="${project_root}/tests/release_checksum_manifest.sha256"
release_metadata_path="${project_root}/tests/release_metadata.json"
conformance_report_rel_path="tests/cross_repo_conformance_report.json"
borrow_wave_conformance_report_rel_path="tests/borrow_wave_conformance_report.json"
conformance_report_path="${project_root}/${conformance_report_rel_path}"
borrow_wave_conformance_report_path="${project_root}/${borrow_wave_conformance_report_rel_path}"

cleanup_generated() {
  rm -rf "${project_root}/gnatprove" "${project_root}/obj" "${project_root}/lib"

  find "${project_root}" -maxdepth 1 -type f \
    \( -name '*.ali' -o -name '*.o' -o -name '*.bexch' -o -name '*.stderr' -o -name '*.stdout' -o -name 'b__*.adb' -o -name 'b__*.ads' -o -name 'main' \) \
    -delete

  find "${project_root}/tests" -maxdepth 1 -type f \
    \( -name '*.ali' -o -name '*.o' -o -name '*.bexch' -o -name '*.stderr' -o -name '*.stdout' -o -name 'b__*.adb' -o -name 'b__*.ads' -o -name 'security_secrets_tests' \) \
    -delete
}

trap cleanup_generated EXIT

if command -v sha256sum >/dev/null 2>&1; then
  hash_cmd=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  hash_cmd=(shasum -a 256)
else
  echo "release-gate: missing checksum tool (sha256sum/shasum)" >&2
  exit 1
fi

sha256_file() {
  "${hash_cmd[@]}" "$1" | awk '{print $1}'
}

write_checksum_manifest() {
  local files=()

  while IFS= read -r -d '' file; do
    files+=("${file#${project_root}/}")
  done < <(find "${project_root}/src" "${project_root}/scripts" -type f \
    \( -name '*.adb' -o -name '*.ads' -o -name '*.sh' \) -print0)
  files+=("vericlaw.gpr" "Makefile")

  (
    cd "${project_root}"
    printf '%s\n' "${files[@]}" | LC_ALL=C sort -u | while IFS= read -r rel_path; do
      printf '%s  %s\n' "$(sha256_file "${rel_path}")" "${rel_path}"
    done >"${checksum_manifest_path}"
  )
}

if "${project_root}/scripts/check_toolchain.sh" --quiet >/dev/null 2>&1; then
  toolchain_mode="host"
  echo "release-gate: using host toolchain"
  make -C "${project_root}" check
  make -C "${project_root}" secrets-test
  make -C "${project_root}" measure-small
  CONFORMANCE_REPORT_PATH="${conformance_report_rel_path}" make -C "${project_root}" conformance-suite
  echo "release-gate: running borrow-wave conformance suite"
  CONFORMANCE_REPORT_PATH="${borrow_wave_conformance_report_rel_path}" make -C "${project_root}" conformance-suite
else
  toolchain_mode="container"
  echo "release-gate: using container toolchain"
  "${project_root}/scripts/run_container_ci.sh" check
  "${project_root}/scripts/run_container_ci.sh" secrets-test
  "${project_root}/scripts/run_container_ci.sh" measure-small
  CONFORMANCE_REPORT_PATH="${conformance_report_rel_path}" "${project_root}/scripts/run_container_ci.sh" conformance-suite
  echo "release-gate: running borrow-wave conformance suite"
  CONFORMANCE_REPORT_PATH="${borrow_wave_conformance_report_rel_path}" "${project_root}/scripts/run_container_ci.sh" conformance-suite
fi

write_checksum_manifest
checksum_manifest_sha256="$(sha256_file "${checksum_manifest_path}")"
generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ ! -f "${conformance_report_path}" || ! -f "${borrow_wave_conformance_report_path}" ]]; then
  echo "release-gate: missing conformance report artifacts" >&2
  exit 1
fi

cat >"${release_metadata_path}" <<EOF
{
  "generated_at": "${generated_at}",
  "gate": "hardened-expansion-release",
  "toolchain_mode": "${toolchain_mode}",
  "checks": {
    "check": "pass",
    "secrets_test": "pass",
    "measure_small": "pass",
    "conformance_suite": "pass",
    "borrow_wave_conformance_suite": "pass"
  },
  "artifacts": {
    "conformance_report": "${conformance_report_rel_path}",
    "borrow_wave_conformance_report": "${borrow_wave_conformance_report_rel_path}",
    "checksum_manifest": "tests/release_checksum_manifest.sha256",
    "checksum_manifest_sha256": "${checksum_manifest_sha256}"
  }
}
EOF

echo "release-gate: manifest=${checksum_manifest_path}"
echo "release-gate: metadata=${release_metadata_path}"
