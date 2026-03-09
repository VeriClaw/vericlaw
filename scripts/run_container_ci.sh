#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/run_container_ci.sh [build|prove|test|validate|check|measure-small|secrets-test|conformance-suite]

Runs blessed build/test/proof commands in a GNAT/SPARK container image.
EOF
}

action="${1-check}"
if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

case "$action" in
  build|prove|test|validate|check|measure-small|secrets-test|conformance-suite) ;;
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
make_env=""

case "$action" in
  build)
    make_target="build-host"
    ;;
  prove)
    make_target="prove-host"
    ;;
  test)
    make_target="test-host"
    ;;
  validate|check)
    make_target="validate-host"
    ;;
  measure-small)
    make_target="measure-small"
    ;;
  secrets-test)
    make_target="secrets-test"
    ;;
  conformance-suite)
    make_target="conformance-suite"
    make_env="CONFORMANCE_FORCE_LOCAL=1"
    ;;
esac

echo "Running '${action}' using container image ${image}"
docker run --rm --platform "${platform}" -e CONFORMANCE_REPORT_PATH="${CONFORMANCE_REPORT_PATH:-}" -v "${project_root}:/workspace" -w /workspace "${image}" \
  bash -lc "
    if [ -d /opt/gnat/bin ]; then export PATH=/opt/gnat/bin:\$PATH; fi
    export GPR_PROJECT_PATH=/opt/gnat/share/gpr
    apt-get update -qq && apt-get install -y --no-install-recommends libsqlite3-dev libcurl4-openssl-dev >/dev/null 2>&1
    ${make_env} make -C /workspace ${make_target}"
