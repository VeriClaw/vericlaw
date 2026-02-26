#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
audit_log_tool="${project_root}/scripts/audit_event_log.py"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

db_path="${tmp_dir}/audit-events.sqlite"

"${audit_log_tool}" append \
  --db "${db_path}" \
  --event-kind "gateway_auth_denied" \
  --decision "deny" \
  --summary "pairing policy denied request with redacted subject." \
  --metadata-json '{"policy":"pairing","subject":"[REDACTED]"}' \
  --max-entries 5 \
  --max-age-seconds 10000 >/dev/null

if "${audit_log_tool}" append \
  --db "${db_path}" \
  --event-kind "gateway_auth_denied" \
  --decision "deny" \
  --summary "token:abc123 should never be logged" \
  --metadata-json '{"policy":"pairing"}' \
  --max-entries 5 \
  --max-age-seconds 10000 >/dev/null 2>&1; then
  echo "Expected redaction guard to block unredacted token-bearing summary." >&2
  exit 1
fi

old_event_ts="$(( $(date +%s) - 7200 ))"
"${audit_log_tool}" append \
  --db "${db_path}" \
  --event-kind "gateway_auth_denied" \
  --decision "deny" \
  --summary "historical redacted auth deny event." \
  --metadata-json '{"policy":"history","subject":"[REDACTED]"}' \
  --event-ts "${old_event_ts}" \
  --max-entries 5 \
  --max-age-seconds 10000 >/dev/null

"${audit_log_tool}" append \
  --db "${db_path}" \
  --event-kind "gateway_auth_allowed" \
  --decision "allow" \
  --summary "redacted auth decision accepted." \
  --metadata-json '{"policy":"pairing","subject":"[REDACTED]"}' \
  --max-entries 5 \
  --max-age-seconds 60 >/dev/null

for iteration in 1 2 3; do
  "${audit_log_tool}" append \
    --db "${db_path}" \
    --event-kind "gateway_start_refused" \
    --decision "deny" \
    --summary "gateway startup refused by fail-closed policy iteration ${iteration}." \
    --metadata-json '{"policy":"startup_guard","subject":"[REDACTED]"}' \
    --max-entries 2 \
    --max-age-seconds 3600 >/dev/null
done

all_events_json="${tmp_dir}/all-events.json"
"${audit_log_tool}" query --db "${db_path}" --limit 10 >"${all_events_json}"

python3 - "${all_events_json}" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
governance = payload.get("governance") or {}
events = payload.get("events") or []

if governance.get("max_entries") != 2:
    raise SystemExit("Retention governance max_entries was not persisted as expected.")
if governance.get("max_age_seconds") != 3600:
    raise SystemExit("Retention governance max_age_seconds was not persisted as expected.")
if len(events) != 2:
    raise SystemExit(f"Expected 2 retained events, found {len(events)}.")
for event in events:
    if event.get("event_kind") != "gateway_start_refused":
        raise SystemExit(f"Unexpected retained event kind: {event.get('event_kind')!r}")
    if not event.get("subject_set"):
        raise SystemExit("Retained event violated subject_set redaction constraint.")
    if not event.get("classification_set"):
        raise SystemExit("Retained event violated classification_set redaction constraint.")
    if event.get("includes_secret_material"):
        raise SystemExit("Retained event contains secret material.")
    if event.get("includes_token_material"):
        raise SystemExit("Retained event contains token material.")
    if event.get("chain_version") != "v1":
        raise SystemExit(f"Unexpected chain version: {event.get('chain_version')!r}")
    chain_hash = event.get("chain_hash") or ""
    if len(chain_hash) != 64:
        raise SystemExit("Retained event is missing a deterministic chain hash.")
PY

filtered_events_json="${tmp_dir}/filtered-events.json"
"${audit_log_tool}" query \
  --db "${db_path}" \
  --event-kind "gateway_start_refused" \
  --decision "deny" \
  --limit 10 >"${filtered_events_json}"

python3 - "${filtered_events_json}" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
events = payload.get("events") or []
if len(events) == 0:
    raise SystemExit("Filtered query unexpectedly returned zero events.")
PY

"${audit_log_tool}" retention-check \
  --db "${db_path}" \
  --max-entries 2 \
  --max-age-seconds 3600 \
  --enforce >/dev/null

if "${audit_log_tool}" retention-check \
  --max-entries 0 \
  --max-age-seconds 60 \
  --current-entries 0 \
  --oldest-age-seconds 0 \
  --enforce >/dev/null 2>&1; then
  echo "Expected invalid retention limits to fail governance enforcement." >&2
  exit 1
fi

"${audit_log_tool}" verify-chain --db "${db_path}" >/dev/null

python3 - "${db_path}" <<'PY'
import sqlite3
import sys

with sqlite3.connect(sys.argv[1]) as conn:
    conn.execute(
        """
        UPDATE audit_events
        SET summary = summary || ' [tampered]'
        WHERE event_id = (
            SELECT event_id
            FROM audit_events
            ORDER BY event_ts DESC, event_id DESC
            LIMIT 1
        )
        """
    )
PY

if "${audit_log_tool}" verify-chain --db "${db_path}" >/dev/null 2>&1; then
  echo "Expected verify-chain to fail after tampering with persisted audit events." >&2
  exit 1
fi

echo "Audit event log persistence checks passed."
