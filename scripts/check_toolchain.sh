#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/check_toolchain.sh [--mode build|full|container|auto] [--quiet]

Report whether the blessed validation path is available.

Modes:
  build      require host gprbuild only
  full       require host gprbuild + gnatprove (default)
  container  require Docker CLI + daemon
  auto       require either full host validation or container validation
EOF
}

status_for_command() {
  local tool="$1"

  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "missing"
  elif "$tool" --version >/dev/null 2>&1; then
    echo "available"
  else
    echo "broken"
  fi
}

detect_container_status() {
  if ! command -v docker >/dev/null 2>&1; then
    docker_cli_status="missing"
    docker_daemon_status="unavailable"
    return
  fi

  docker_cli_status="available"
  if docker info >/dev/null 2>&1; then
    docker_daemon_status="available"
  else
    docker_daemon_status="unavailable"
  fi
}

print_status_line() {
  printf '  %-14s %s\n' "$1" "$2"
}

quiet=0
mode="full"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet)
      quiet=1
      shift
      ;;
    --mode)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --mode" >&2
        usage >&2
        exit 2
      fi
      mode="$2"
      shift 2
      ;;
    --mode=*)
      mode="${1#*=}"
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

case "$mode" in
  build|full|container|auto) ;;
  *)
    echo "Unsupported mode: $mode" >&2
    usage >&2
    exit 2
    ;;
esac

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_file="${project_root}/vericlaw.gpr"

if [[ ! -f "$project_file" ]]; then
  echo "Missing project file: $project_file" >&2
  exit 1
fi

gprbuild_status="$(status_for_command gprbuild)"
gnatprove_status="$(status_for_command gnatprove)"
detect_container_status

host_build_ready=0
host_full_ready=0
container_ready=0

if [[ "$gprbuild_status" == "available" ]]; then
  host_build_ready=1
fi

if [[ "$host_build_ready" -eq 1 && "$gnatprove_status" == "available" ]]; then
  host_full_ready=1
fi

if [[ "$docker_cli_status" == "available" && "$docker_daemon_status" == "available" ]]; then
  container_ready=1
fi

mode_satisfied=0
case "$mode" in
  build)
    if [[ "$host_build_ready" -eq 1 ]]; then
      mode_satisfied=1
    fi
    ;;
  full)
    if [[ "$host_full_ready" -eq 1 ]]; then
      mode_satisfied=1
    fi
    ;;
  container)
    if [[ "$container_ready" -eq 1 ]]; then
      mode_satisfied=1
    fi
    ;;
  auto)
    if [[ "$host_full_ready" -eq 1 || "$container_ready" -eq 1 ]]; then
      mode_satisfied=1
    fi
    ;;
esac

if [[ "$quiet" -eq 0 ]]; then
  echo "Validation readiness:"
  echo "Host toolchain:"
  print_status_line "gprbuild:" "$gprbuild_status"
  print_status_line "gnatprove:" "$gnatprove_status"
  echo "Container fallback:"
  print_status_line "docker CLI:" "$docker_cli_status"
  print_status_line "docker daemon:" "$docker_daemon_status"
  echo

  case "$mode" in
    build)
      if [[ "$mode_satisfied" -eq 1 ]]; then
        echo "Host build validation is available."
        if [[ "$host_full_ready" -eq 0 ]]; then
          echo "Install gnatprove to enable full proof validation with 'make validate'."
        fi
      else
        echo "Host build validation is unavailable."
      fi
      ;;
    full)
      if [[ "$mode_satisfied" -eq 1 ]]; then
        echo "Full host validation is available."
      else
        echo "Full host validation is unavailable."
      fi
      ;;
    container)
      if [[ "$mode_satisfied" -eq 1 ]]; then
        echo "Container validation is available."
      else
        echo "Container validation is unavailable."
      fi
      ;;
    auto)
      if [[ "$mode_satisfied" -eq 1 ]]; then
        if [[ "$host_full_ready" -eq 1 ]]; then
          echo "Blessed validation path is available on the host."
        else
          echo "Blessed validation path is available via container fallback."
        fi
      else
        echo "Blessed validation path is unavailable in this environment."
      fi
      ;;
  esac

  if [[ "$mode_satisfied" -eq 0 || "$mode" == "auto" ]]; then
    echo "Blessed entry point: make validate [VALIDATION_BACKEND=host|container]"
  fi

  if [[ "$host_build_ready" -eq 0 ]]; then
    echo "Run ./scripts/bootstrap_toolchain.sh for host setup guidance."
  elif [[ "$host_full_ready" -eq 0 ]]; then
    echo "Host builds are available; install gnatprove for local proof validation."
  fi

  if [[ "$docker_cli_status" == "available" && "$docker_daemon_status" != "available" ]]; then
    echo "Docker CLI is installed, but the daemon is unavailable."
  elif [[ "$container_ready" -eq 1 && "$host_full_ready" -eq 0 ]]; then
    echo "Container fallback is ready: make validate VALIDATION_BACKEND=container"
  fi
fi

if [[ "$mode_satisfied" -eq 1 ]]; then
  exit 0
fi

exit 1
