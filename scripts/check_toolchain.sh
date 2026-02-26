#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/check_toolchain.sh [--quiet]

Validate that gprbuild + gnatprove are available and runnable.
EOF
}

quiet=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet)
      quiet=1
      shift
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

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_file="${project_root}/quasar_claw.gpr"

if [[ ! -f "$project_file" ]]; then
  echo "Missing project file: $project_file" >&2
  exit 1
fi

missing_tools=()
for tool in gprbuild gnatprove; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing_tools+=("$tool")
  fi
done

if [[ ${#missing_tools[@]} -gt 0 ]]; then
  echo "Missing Ada/SPARK tools: ${missing_tools[*]}" >&2
  echo "Run ./scripts/bootstrap_toolchain.sh for host setup guidance." >&2
  echo "Or run ./scripts/run_container_ci.sh check if Docker is available." >&2
  exit 1
fi

for tool in gprbuild gnatprove; do
  if ! "$tool" --version >/dev/null 2>&1; then
    echo "Tool command exists but failed: $tool --version" >&2
    exit 1
  fi
done

if [[ "$quiet" -eq 0 ]]; then
  echo "Ada/SPARK toolchain looks good."
  gprbuild --version
  gnatprove --version
fi
