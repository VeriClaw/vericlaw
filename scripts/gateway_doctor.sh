#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scripts/gateway_doctor.sh <doctor|audit|start> [options] [-- serve-command ...]

Run a local security audit (doctor/audit) or enforce startup refusal guards (start)
before serving.

Fail-closed defaults:
  --bind-host 127.0.0.1 --deny-public-bind --require-pairing --require-token

Options:
  --bind-host HOST
  --allow-public-bind | --deny-public-bind
  --require-pairing | --no-require-pairing
  --require-token   | --no-require-token
  --help
USAGE
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
audit_log_tool="${script_dir}/audit_event_log.py"
audit_log_db="${GATEWAY_AUDIT_LOG_DB:-${HOME:-/tmp}/.quasar-claw/audit-events.sqlite}"
audit_max_entries="${GATEWAY_AUDIT_MAX_ENTRIES:-1000}"
audit_max_age_seconds="${GATEWAY_AUDIT_MAX_AGE_SECONDS:-2592000}"

is_loopback_host() {
  case "$1" in
    localhost|127.*|::1) return 0 ;;
    *) return 1 ;;
  esac
}

append_suggestion() {
  local message="$1"
  local existing
  for existing in "${suggestions[@]-}"; do
    if [[ "$existing" == "$message" ]]; then
      return
    fi
  done
  suggestions+=("$message")
}

bool_to_json() {
  if [[ "$1" -eq 1 ]]; then
    echo "true"
  else
    echo "false"
  fi
}

persist_audit_event() {
  local event_kind="$1"
  local decision="$2"
  local summary="$3"
  local metadata_json

  if [[ ! -x "${audit_log_tool}" ]]; then
    return 0
  fi

  metadata_json="$(printf '{"bind_host":"%s","allow_public_bind":%s,"require_pairing":%s,"require_token":%s}' \
    "${bind_host}" \
    "$(bool_to_json "${allow_public_bind}")" \
    "$(bool_to_json "${require_pairing}")" \
    "$(bool_to_json "${require_token}")")"

  if ! "${audit_log_tool}" append \
    --db "${audit_log_db}" \
    --event-kind "${event_kind}" \
    --decision "${decision}" \
    --summary "${summary}" \
    --metadata-json "${metadata_json}" \
    --max-entries "${audit_max_entries}" \
    --max-age-seconds "${audit_max_age_seconds}" >/dev/null 2>&1; then
    echo "audit-log-warning: failed to persist redacted audit event." >&2
  fi
}

evaluate_policy() {
  diagnostics=()
  suggestions=()
  unsafe=0

  if is_loopback_host "$bind_host"; then
    diagnostics+=("bind host '${bind_host}' is loopback-only.")
  else
    diagnostics+=("bind host '${bind_host}' is non-loopback (remote reachable).")

    if [[ "$allow_public_bind" -ne 1 ]]; then
      unsafe=1
      diagnostics+=("non-loopback bind requires explicit --allow-public-bind, but it is disabled.")
      append_suggestion "Use --bind-host 127.0.0.1 to keep serving local-only."
      append_suggestion "If remote access is required, add --allow-public-bind explicitly."
    fi

    if [[ "$require_pairing" -ne 1 ]]; then
      unsafe=1
      diagnostics+=("pairing is disabled for a non-loopback bind.")
      append_suggestion "Enable pairing with --require-pairing before serving remotely."
    fi

    if [[ "$require_token" -ne 1 ]]; then
      unsafe=1
      diagnostics+=("token authentication is disabled for a non-loopback bind.")
      append_suggestion "Enable token auth with --require-token before serving remotely."
    fi
  fi

  if is_loopback_host "$bind_host" && [[ "$allow_public_bind" -eq 1 ]]; then
    diagnostics+=("public bind opt-in is set while host is loopback; no exposure change.")
    append_suggestion "Optional hardening: add --deny-public-bind to keep intent explicit."
  fi
}

print_report() {
  local line

  echo "security-audit: gateway startup configuration"
  echo "config: bind_host=${bind_host} allow_public_bind=${allow_public_bind} require_pairing=${require_pairing} require_token=${require_token}"

  if [[ "$unsafe" -eq 0 ]]; then
    echo "overall: PASS (fail-closed defaults preserved)"
  else
    echo "overall: FAIL (unsafe bind/auth combination detected)"
  fi

  echo "diagnostics:"
  for line in "${diagnostics[@]-}"; do
    echo "  - ${line}"
  done

  if [[ "${#suggestions[@]}" -gt 0 ]]; then
    echo "safe-fix-suggestions:"
    for line in "${suggestions[@]-}"; do
      echo "  - ${line}"
    done
  fi
}

command="${1-doctor}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$command" in
  doctor|audit|start) ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    echo "Unknown command: $command" >&2
    usage >&2
    exit 2
    ;;
esac

bind_host="${GATEWAY_BIND_HOST:-127.0.0.1}"
allow_public_bind=0
require_pairing=1
require_token=1
serve_cmd=()

diagnostics=()
suggestions=()
unsafe=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bind-host)
      [[ $# -ge 2 ]] || { echo "Missing value for --bind-host" >&2; exit 2; }
      bind_host="$2"
      shift 2
      ;;
    --allow-public-bind)
      allow_public_bind=1
      shift
      ;;
    --deny-public-bind)
      allow_public_bind=0
      shift
      ;;
    --require-pairing)
      require_pairing=1
      shift
      ;;
    --no-require-pairing)
      require_pairing=0
      shift
      ;;
    --require-token)
      require_token=1
      shift
      ;;
    --no-require-token)
      require_token=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      serve_cmd=("$@")
      break
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$bind_host" ]]; then
  echo "Bind host must not be empty." >&2
  exit 2
fi

evaluate_policy

case "$command" in
  doctor|audit)
    if [[ "$unsafe" -eq 0 ]]; then
      persist_audit_event "gateway_doctor_audit" "allow" "gateway doctor policy evaluation passed"
    else
      persist_audit_event "gateway_doctor_audit" "deny" "gateway doctor policy evaluation failed"
    fi
    print_report
    if [[ "$unsafe" -eq 0 ]]; then
      exit 0
    fi
    exit 1
    ;;
  start)
    if [[ "$unsafe" -ne 0 ]]; then
      persist_audit_event "gateway_start_refused" "deny" "gateway startup refused by fail-closed policy"
      print_report >&2
      echo "startup-refused: refusing to serve with unsafe bind/auth combination." >&2
      exit 2
    fi

    persist_audit_event "gateway_start_allowed" "allow" "gateway startup guard passed"
    echo "startup-guard: PASS"
    if [[ "${#serve_cmd[@]}" -eq 0 ]]; then
      echo "No serve command provided after '--'; startup guard completed without serving."
      exit 0
    fi

    exec "${serve_cmd[@]}"
    ;;
esac
