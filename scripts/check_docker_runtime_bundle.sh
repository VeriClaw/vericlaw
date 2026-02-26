#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle_path="${project_root}/docker-compose.secure.yml"
tmp_dir="$(mktemp -d)"
out="${tmp_dir}/out.txt"

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

required_patterns=(
  "GATEWAY_BIND_HOST: \"127.0.0.1\""
  "ALLOW_PUBLIC_BIND: \"false\""
  "REQUIRE_PAIRING: \"true\""
  "read_only: true"
  "tmpfs:"
  "- /tmp"
  "cap_drop:"
  "- ALL"
  "security_opt:"
  "no-new-privileges:true"
  "user: \"10001:10001\""
  "127.0.0.1:8787:8787"
)

insecure_patterns=(
  "0.0.0.0:8787:8787"
  "\"8787:8787\""
  "ALLOW_PUBLIC_BIND: \"true\""
)

check_bundle() {
  local candidate="$1"
  local label pattern

  if [[ ! -f "${candidate}" ]]; then
    echo "Missing docker runtime bundle: ${candidate}" >&2
    return 1
  fi

  label="$(basename "${candidate}")"

  for pattern in "${insecure_patterns[@]}"; do
    if grep -Fq -- "${pattern}" "${candidate}"; then
      echo "${label} contains insecure setting: ${pattern}" >&2
      return 1
    fi
  done

  for pattern in "${required_patterns[@]}"; do
    if ! grep -Fq -- "${pattern}" "${candidate}"; then
      echo "${label} missing required setting: ${pattern}" >&2
      return 1
    fi
  done
}

check_bundle "${bundle_path}"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "${bundle_path}" config >/dev/null
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose -f "${bundle_path}" config >/dev/null
  fi
fi

public_bind_bundle="${tmp_dir}/insecure-public-bind.yml"
sed 's/127\.0\.0\.1:8787:8787/0.0.0.0:8787:8787/' "${bundle_path}" >"${public_bind_bundle}"
if check_bundle "${public_bind_bundle}" >"${out}" 2>&1; then
  echo "Expected insecure public bind bundle to be rejected." >&2
  exit 1
fi
grep -Fq "contains insecure setting: 0.0.0.0:8787:8787" "${out}"

missing_pairing_bundle="${tmp_dir}/insecure-missing-pairing.yml"
grep -Fv '      REQUIRE_PAIRING: "true"' "${bundle_path}" >"${missing_pairing_bundle}"
if check_bundle "${missing_pairing_bundle}" >"${out}" 2>&1; then
  echo "Expected missing runtime hardening knob to be rejected." >&2
  exit 1
fi
grep -Fq 'missing required setting: REQUIRE_PAIRING: "true"' "${out}"

echo "Docker runtime bundle security profile checks passed."
