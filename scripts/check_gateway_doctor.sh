#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
doctor="${project_root}/scripts/gateway_doctor.sh"
audit_log_tool="${project_root}/scripts/audit_event_log.py"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

out="${tmp_dir}/out.txt"
audit_log_db="${tmp_dir}/audit-events.sqlite"

run_doctor() {
  GATEWAY_AUDIT_LOG_DB="${audit_log_db}" \
    GATEWAY_AUDIT_MAX_ENTRIES=3 \
    GATEWAY_AUDIT_MAX_AGE_SECONDS=3600 \
    "${doctor}" "$@"
}

run_doctor doctor >"${out}"
grep -q "overall: PASS" "${out}"
grep -q "fail-closed defaults preserved" "${out}"

if run_doctor start --bind-host 0.0.0.0 >"${out}" 2>&1; then
  echo "Expected startup refusal for non-loopback bind without explicit auth guards." >&2
  exit 1
fi
grep -q "overall: FAIL" "${out}"
grep -q "startup-refused" "${out}"
grep -q "safe-fix-suggestions:" "${out}"

if run_doctor start --bind-host 0.0.0.0 --allow-public-bind --no-require-pairing >"${out}" 2>&1; then
  echo "Expected startup refusal when pairing is disabled for non-loopback bind." >&2
  exit 1
fi
grep -q "pairing is disabled" "${out}"

if run_doctor start --bind-host 0.0.0.0 --allow-public-bind --no-require-token >"${out}" 2>&1; then
  echo "Expected startup refusal when token authentication is disabled for non-loopback bind." >&2
  exit 1
fi
grep -q "token authentication is disabled" "${out}"

run_doctor start --bind-host 0.0.0.0 --allow-public-bind --require-pairing --require-token -- printf 'guarded-start-ok\n' >"${out}"
grep -q "guarded-start-ok" "${out}"

audit_query="${tmp_dir}/audit-query.json"
"${audit_log_tool}" query --db "${audit_log_db}" --limit 10 >"${audit_query}"

python3 - "${audit_query}" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
governance = payload.get("governance") or {}
events = payload.get("events") or []

if governance.get("max_entries") != 3:
    raise SystemExit("Gateway doctor audit log missing expected max_entries governance setting.")
if governance.get("max_age_seconds") != 3600:
    raise SystemExit("Gateway doctor audit log missing expected max_age_seconds governance setting.")
if len(events) == 0:
    raise SystemExit("Gateway doctor audit log query returned no events.")
if len(events) > 3:
    raise SystemExit(f"Gateway doctor audit log retention failed, found {len(events)} events.")

kinds = {event.get("event_kind") for event in events}
if "gateway_start_refused" not in kinds:
    raise SystemExit("Gateway doctor audit log missing gateway_start_refused event.")
if "gateway_start_allowed" not in kinds:
    raise SystemExit("Gateway doctor audit log missing gateway_start_allowed event.")
for event in events:
    if not event.get("subject_set"):
        raise SystemExit("Gateway doctor emitted audit event without subject_set metadata.")
    if event.get("includes_secret_material"):
        raise SystemExit("Gateway doctor emitted audit event with secret material.")
    if event.get("includes_token_material"):
        raise SystemExit("Gateway doctor emitted audit event with token material.")
PY

echo "Gateway doctor startup guard and audit log checks passed."
