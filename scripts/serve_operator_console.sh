#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/serve_operator_console.sh [--host HOST] [--port PORT] [--allow-non-loopback]

Serve the local operator web console scaffold using Python's built-in static HTTP server.
Defaults: host=127.0.0.1, port=8088.
EOF
}

is_loopback_host() {
  case "$1" in
    localhost|127.*|::1) return 0 ;;
    *) return 1 ;;
  esac
}

host="${OPERATOR_CONSOLE_HOST:-127.0.0.1}"
port="${OPERATOR_CONSOLE_PORT:-8088}"
allow_non_loopback=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      [[ $# -ge 2 ]] || { echo "Missing value for --host" >&2; exit 2; }
      host="$2"
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || { echo "Missing value for --port" >&2; exit 2; }
      port="$2"
      shift 2
      ;;
    --allow-non-loopback)
      allow_non_loopback=1
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

if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
  echo "Port must be an integer in range 1..65535." >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to serve the operator console." >&2
  exit 1
fi

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
console_dir="${project_root}/operator-console"

if [[ ! -f "${console_dir}/index.html" ]]; then
  echo "Operator console not found at ${console_dir}" >&2
  exit 1
fi

if ! is_loopback_host "$host"; then
  if [[ "$allow_non_loopback" -ne 1 ]]; then
    echo "Refusing non-loopback host '${host}' without --allow-non-loopback." >&2
    exit 2
  fi
  echo "WARNING: serving on non-loopback host '${host}'. Restrict access explicitly." >&2
fi

echo "Serving operator console from ${console_dir}"
echo "Bind host: ${host}, port: ${port}"
echo "Telemetry: disabled (local static scaffold only)."
exec python3 -m http.server "$port" --bind "$host" --directory "$console_dir"
