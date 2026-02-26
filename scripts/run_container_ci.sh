#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/run_container_ci.sh [build|prove|check|measure-small|secrets-test|conformance-suite]

Runs build/proof commands in a GNAT/SPARK container image.
EOF
}

action="${1-check}"
if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

case "$action" in
  build|prove|check|measure-small|secrets-test|conformance-suite) ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    echo "Unknown action: $action" >&2
    usage >&2
    exit 2
    ;;
esac

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker CLI not found. Install Docker or use host toolchain setup." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is unavailable. Start Docker and retry." >&2
  exit 1
fi

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${ADA_CONTAINER_IMAGE:-alire/gnat:community-latest}"
platform="${ADA_CONTAINER_PLATFORM:-linux/amd64}"

case "$action" in
  build)
    inner_cmd="gprbuild -P quasar_claw.gpr"
    ;;
  prove)
    inner_cmd="gnatprove -P quasar_claw.gpr --mode=flow --level=1"
    ;;
  check)
    inner_cmd="gprbuild -P quasar_claw.gpr && gnatprove -P quasar_claw.gpr --mode=flow --level=1 && ./scripts/check_audit_event_log.sh && ./scripts/check_service_supervisors.sh"
    ;;
  measure-small)
    inner_cmd="./scripts/measure_small_infra.sh"
    ;;
  secrets-test)
    inner_cmd="gprbuild -P tests/security_secrets_tests.gpr && ./tests/security_secrets_tests && ./scripts/check_audit_event_log.sh"
    ;;
  conformance-suite)
    inner_cmd="CONFORMANCE_FORCE_LOCAL=1 ./scripts/run_cross_repo_conformance_suite.sh"
    ;;
esac

echo "Running '${action}' using container image ${image}"
docker run --rm --platform "${platform}" -e CONFORMANCE_REPORT_PATH="${CONFORMANCE_REPORT_PATH:-}" -v "${project_root}:/workspace" -w /workspace "${image}" \
  bash -lc "if [ -d /opt/gnat/bin ]; then export PATH=/opt/gnat/bin:\$PATH; fi; ${inner_cmd}"
