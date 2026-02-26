#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import sys
import time
from pathlib import Path
from typing import Any

SENSITIVE_INLINE_PATTERN = re.compile(
    r"(?:bearer\s+[a-z0-9._-]+|\b(?:secret|token|password|api[_-]?key|authorization)\b\s*[:=])",
    flags=re.IGNORECASE,
)
SENSITIVE_KEYS = {
    "secret",
    "token",
    "password",
    "api_key",
    "apikey",
    "authorization",
    "credential",
    "private_key",
}
REDACTED_SENTINELS = {"", "redacted", "[REDACTED]", "***", "null"}
CHAIN_VERSION = "v1"


def parse_bool(raw: str) -> bool:
    value = raw.strip().lower()
    if value in {"1", "true", "yes", "y"}:
        return True
    if value in {"0", "false", "no", "n"}:
        return False
    raise argparse.ArgumentTypeError(f"Invalid boolean value: {raw!r}")


def as_bool_int(value: bool) -> int:
    return 1 if value else 0


def parse_metadata_json(raw: str) -> dict[str, Any]:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid --metadata-json payload: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError("Audit metadata must be a JSON object.")
    return value


def is_redacted_placeholder(value: Any) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in REDACTED_SENTINELS:
            return True
        if normalized.startswith("[redacted"):
            return True
    return False


def metadata_contains_sensitive_material(payload: Any, key_hint: str = "") -> bool:
    if isinstance(payload, dict):
        for key, value in payload.items():
            normalized_key = str(key).strip().lower()
            if normalized_key in SENSITIVE_KEYS and not is_redacted_placeholder(value):
                return True
            if metadata_contains_sensitive_material(value, normalized_key):
                return True
        return False

    if isinstance(payload, list):
        return any(metadata_contains_sensitive_material(item, key_hint) for item in payload)

    if isinstance(payload, str):
        if SENSITIVE_INLINE_PATTERN.search(payload):
            return True
        if key_hint in SENSITIVE_KEYS and not is_redacted_placeholder(payload):
            return True
    return False


def validate_redaction_constraints(
    subject_set: bool,
    classification_set: bool,
    redaction_metadata_valid: bool,
    includes_secret_material: bool,
    includes_token_material: bool,
    summary: str,
    metadata: dict[str, Any],
) -> None:
    if not subject_set:
        raise ValueError("Audit event rejected: subject_set must be true.")
    if not classification_set:
        raise ValueError("Audit event rejected: classification_set must be true.")
    if not redaction_metadata_valid:
        raise ValueError("Audit event rejected: redaction_metadata_valid must be true.")
    if includes_secret_material:
        raise ValueError("Audit event rejected: includes_secret_material must be false.")
    if includes_token_material:
        raise ValueError("Audit event rejected: includes_token_material must be false.")
    if SENSITIVE_INLINE_PATTERN.search(summary):
        raise ValueError("Audit event rejected: summary appears to contain sensitive material.")
    if metadata_contains_sensitive_material(metadata):
        raise ValueError("Audit event rejected: metadata appears to contain sensitive material.")


def connect_db(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def build_chain_payload(row: sqlite3.Row, chain_prev_hash: str, chain_version: str) -> dict[str, Any]:
    return {
        "chain_prev_hash": chain_prev_hash,
        "chain_version": chain_version,
        "classification_set": int(row["classification_set"]),
        "created_at": row["created_at"],
        "decision": row["decision"],
        "event_id": int(row["event_id"]),
        "event_kind": row["event_kind"],
        "event_ts": int(row["event_ts"]),
        "includes_secret_material": int(row["includes_secret_material"]),
        "includes_token_material": int(row["includes_token_material"]),
        "metadata_json": row["metadata_json"],
        "redaction_metadata_valid": int(row["redaction_metadata_valid"]),
        "redaction_status": row["redaction_status"],
        "redaction_version": row["redaction_version"],
        "subject_set": int(row["subject_set"]),
        "summary": row["summary"],
    }


def compute_chain_hash(payload: dict[str, Any]) -> str:
    canonical_payload = json.dumps(payload, separators=(",", ":"), sort_keys=True)
    return hashlib.sha256(canonical_payload.encode("utf-8")).hexdigest()


def rebuild_chain_metadata(conn: sqlite3.Connection) -> None:
    rows = conn.execute(
        """
        SELECT event_id, event_ts, event_kind, decision, summary,
               subject_set, classification_set, redaction_metadata_valid,
               includes_secret_material, includes_token_material,
               redaction_status, redaction_version, metadata_json, created_at
        FROM audit_events
        ORDER BY event_ts ASC, event_id ASC
        """
    ).fetchall()

    previous_hash = ""
    for row in rows:
        payload = build_chain_payload(row, previous_hash, CHAIN_VERSION)
        chain_hash = compute_chain_hash(payload)
        conn.execute(
            """
            UPDATE audit_events
            SET chain_prev_hash = ?, chain_hash = ?, chain_version = ?
            WHERE event_id = ?
            """,
            (previous_hash, chain_hash, CHAIN_VERSION, row["event_id"]),
        )
        previous_hash = chain_hash


def verify_chain_metadata(
    conn: sqlite3.Connection,
) -> tuple[bool, list[dict[str, Any]], int]:
    rows = conn.execute(
        """
        SELECT event_id, event_ts, event_kind, decision, summary,
               subject_set, classification_set, redaction_metadata_valid,
               includes_secret_material, includes_token_material,
               redaction_status, redaction_version, metadata_json, created_at,
               chain_prev_hash, chain_hash, chain_version
        FROM audit_events
        ORDER BY event_ts ASC, event_id ASC
        """
    ).fetchall()

    issues: list[dict[str, Any]] = []
    previous_hash = ""
    for row in rows:
        event_id = int(row["event_id"])
        stored_prev_hash = row["chain_prev_hash"] or ""
        stored_hash = row["chain_hash"] or ""
        row_chain_version = row["chain_version"] or ""

        if stored_prev_hash != previous_hash:
            issues.append(
                {
                    "event_id": event_id,
                    "issue": "chain_link_mismatch",
                    "expected_chain_prev_hash": previous_hash,
                    "actual_chain_prev_hash": stored_prev_hash,
                }
            )

        if row_chain_version != CHAIN_VERSION:
            issues.append(
                {
                    "event_id": event_id,
                    "issue": "unsupported_chain_version",
                    "chain_version": row_chain_version,
                    "expected_chain_version": CHAIN_VERSION,
                }
            )

        expected_hash = compute_chain_hash(
            build_chain_payload(row, stored_prev_hash, row_chain_version or CHAIN_VERSION)
        )
        if stored_hash != expected_hash:
            issues.append(
                {
                    "event_id": event_id,
                    "issue": "chain_hash_mismatch",
                    "expected_chain_hash": expected_hash,
                    "actual_chain_hash": stored_hash,
                }
            )

        previous_hash = stored_hash

    return len(issues) == 0, issues, len(rows)


def ensure_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS audit_events (
            event_id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_ts INTEGER NOT NULL,
            event_kind TEXT NOT NULL,
            decision TEXT NOT NULL,
            summary TEXT NOT NULL,
            subject_set INTEGER NOT NULL CHECK(subject_set IN (0, 1) AND subject_set = 1),
            classification_set INTEGER NOT NULL CHECK(classification_set IN (0, 1) AND classification_set = 1),
            redaction_metadata_valid INTEGER NOT NULL CHECK(redaction_metadata_valid IN (0, 1) AND redaction_metadata_valid = 1),
            includes_secret_material INTEGER NOT NULL CHECK(includes_secret_material IN (0, 1) AND includes_secret_material = 0),
            includes_token_material INTEGER NOT NULL CHECK(includes_token_material IN (0, 1) AND includes_token_material = 0),
            redaction_status TEXT NOT NULL CHECK(redaction_status = 'redacted'),
            redaction_version TEXT NOT NULL,
            metadata_json TEXT NOT NULL,
            chain_prev_hash TEXT NOT NULL DEFAULT '',
            chain_hash TEXT NOT NULL DEFAULT '',
            chain_version TEXT NOT NULL DEFAULT 'v1',
            created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
        );

        CREATE INDEX IF NOT EXISTS idx_audit_events_kind_ts
            ON audit_events(event_kind, event_ts DESC, event_id DESC);

        CREATE TABLE IF NOT EXISTS audit_retention_governance (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            max_entries INTEGER NOT NULL CHECK (max_entries > 0),
            max_age_seconds INTEGER NOT NULL CHECK (max_age_seconds > 0),
            updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
        );
        """
    )

    table_columns = {
        row["name"] for row in conn.execute("PRAGMA table_info(audit_events)").fetchall()
    }
    if "chain_prev_hash" not in table_columns:
        conn.execute("ALTER TABLE audit_events ADD COLUMN chain_prev_hash TEXT NOT NULL DEFAULT ''")
    if "chain_hash" not in table_columns:
        conn.execute("ALTER TABLE audit_events ADD COLUMN chain_hash TEXT NOT NULL DEFAULT ''")
    if "chain_version" not in table_columns:
        conn.execute(
            f"ALTER TABLE audit_events ADD COLUMN chain_version TEXT NOT NULL DEFAULT '{CHAIN_VERSION}'"
        )

    missing_chain_metadata = conn.execute(
        """
        SELECT COUNT(*) AS c
        FROM audit_events
        WHERE chain_hash = '' OR chain_version != ?
        """,
        (CHAIN_VERSION,),
    ).fetchone()
    if missing_chain_metadata is not None and int(missing_chain_metadata["c"]) > 0:
        rebuild_chain_metadata(conn)


def upsert_retention_governance(
    conn: sqlite3.Connection, max_entries: int, max_age_seconds: int
) -> None:
    conn.execute(
        """
        INSERT INTO audit_retention_governance (id, max_entries, max_age_seconds, updated_at)
        VALUES (1, ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
        ON CONFLICT(id) DO UPDATE SET
            max_entries = excluded.max_entries,
            max_age_seconds = excluded.max_age_seconds,
            updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        """,
        (max_entries, max_age_seconds),
    )


def current_entry_stats(conn: sqlite3.Connection, now: int) -> tuple[int, int]:
    row = conn.execute("SELECT COUNT(*) AS c, MIN(event_ts) AS min_ts FROM audit_events").fetchone()
    count = int(row["c"]) if row is not None else 0
    min_ts = row["min_ts"] if row is not None else None
    if min_ts is None:
        return count, 0
    oldest_age_seconds = max(0, now - int(min_ts))
    return count, oldest_age_seconds


def retention_policy_decision(
    current_entries: int, max_entries: int, oldest_age_seconds: int, max_age_seconds: int
) -> str:
    if max_entries <= 0 or max_age_seconds <= 0:
        return "Retention_Deny_Invalid_Limits"
    needs_entry_prune = current_entries > max_entries
    needs_age_prune = current_entries > 0 and oldest_age_seconds > max_age_seconds
    if needs_entry_prune and needs_age_prune:
        return "Retention_Drop_Oldest_Max_Entries_And_Age"
    if needs_entry_prune:
        return "Retention_Drop_Oldest_Max_Entries"
    if needs_age_prune:
        return "Retention_Drop_Oldest_Max_Age"
    return "Retention_Keep"


def apply_retention_policy(
    conn: sqlite3.Connection, now: int, max_entries: int, max_age_seconds: int
) -> str:
    if max_entries <= 0 or max_age_seconds <= 0:
        return "Retention_Deny_Invalid_Limits"

    age_threshold = now - max_age_seconds
    age_cursor = conn.execute(
        "DELETE FROM audit_events WHERE event_ts < ?",
        (age_threshold,),
    )
    dropped_by_age = age_cursor.rowcount if age_cursor.rowcount is not None else 0
    if dropped_by_age < 0:
        dropped_by_age = 0

    count_row = conn.execute("SELECT COUNT(*) AS c FROM audit_events").fetchone()
    current_entries = int(count_row["c"]) if count_row is not None else 0
    overflow = max(0, current_entries - max_entries)
    dropped_by_entries = 0

    if overflow > 0:
        entry_cursor = conn.execute(
            """
            DELETE FROM audit_events
            WHERE event_id IN (
                SELECT event_id
                FROM audit_events
                ORDER BY event_ts ASC, event_id ASC
                LIMIT ?
            )
            """,
            (overflow,),
        )
        dropped_by_entries = entry_cursor.rowcount if entry_cursor.rowcount is not None else overflow
        if dropped_by_entries < 0:
            dropped_by_entries = overflow

    if dropped_by_age > 0 and dropped_by_entries > 0:
        return "Retention_Drop_Oldest_Max_Entries_And_Age"
    if dropped_by_entries > 0:
        return "Retention_Drop_Oldest_Max_Entries"
    if dropped_by_age > 0:
        return "Retention_Drop_Oldest_Max_Age"
    return "Retention_Keep"


def cmd_append(args: argparse.Namespace) -> int:
    db_path = Path(args.db_path).expanduser()
    event_ts = args.event_ts if args.event_ts is not None else int(time.time())
    metadata = parse_metadata_json(args.metadata_json)

    validate_redaction_constraints(
        subject_set=args.subject_set,
        classification_set=args.classification_set,
        redaction_metadata_valid=args.redaction_metadata_valid,
        includes_secret_material=args.includes_secret_material,
        includes_token_material=args.includes_token_material,
        summary=args.summary,
        metadata=metadata,
    )

    if args.max_entries <= 0 or args.max_age_seconds <= 0:
        raise ValueError("Retention limits must be positive.")

    with connect_db(db_path) as conn:
        ensure_schema(conn)
        upsert_retention_governance(conn, args.max_entries, args.max_age_seconds)
        insert_cursor = conn.execute(
            """
            INSERT INTO audit_events (
                event_ts,
                event_kind,
                decision,
                summary,
                subject_set,
                classification_set,
                redaction_metadata_valid,
                includes_secret_material,
                includes_token_material,
                redaction_status,
                redaction_version,
                metadata_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'redacted', ?, ?)
            """,
            (
                event_ts,
                args.event_kind,
                args.decision,
                args.summary,
                as_bool_int(args.subject_set),
                as_bool_int(args.classification_set),
                as_bool_int(args.redaction_metadata_valid),
                as_bool_int(args.includes_secret_material),
                as_bool_int(args.includes_token_material),
                args.redaction_version,
                json.dumps(metadata, separators=(",", ":"), sort_keys=True),
            ),
        )

        now = int(time.time())
        retention_decision = apply_retention_policy(conn, now, args.max_entries, args.max_age_seconds)
        rebuild_chain_metadata(conn)
        current_entries, oldest_age_seconds = current_entry_stats(conn, now)

        payload = {
            "db_path": str(db_path),
            "event_id": insert_cursor.lastrowid,
            "retention_decision": retention_decision,
            "current_entries": current_entries,
            "oldest_age_seconds": oldest_age_seconds,
        }
        print(json.dumps(payload, sort_keys=True))
    return 0


def cmd_query(args: argparse.Namespace) -> int:
    db_path = Path(args.db_path).expanduser()

    with connect_db(db_path) as conn:
        ensure_schema(conn)
        where = []
        params: list[Any] = []
        if args.event_kind:
            where.append("event_kind = ?")
            params.append(args.event_kind)
        if args.decision:
            where.append("decision = ?")
            params.append(args.decision)
        if args.since_epoch is not None:
            where.append("event_ts >= ?")
            params.append(args.since_epoch)
        if args.until_epoch is not None:
            where.append("event_ts <= ?")
            params.append(args.until_epoch)

        sql = """
            SELECT event_id, event_ts, event_kind, decision, summary,
                   subject_set, classification_set, redaction_metadata_valid,
                   includes_secret_material, includes_token_material,
                   redaction_status, redaction_version, metadata_json,
                   chain_prev_hash, chain_hash, chain_version, created_at
            FROM audit_events
        """
        if where:
            sql += " WHERE " + " AND ".join(where)
        sql += " ORDER BY event_ts DESC, event_id DESC LIMIT ?"
        params.append(args.limit)
        if args.offset > 0:
            sql += " OFFSET ?"
            params.append(args.offset)

        rows = conn.execute(sql, params).fetchall()
        events = []
        for row in rows:
            try:
                metadata = json.loads(row["metadata_json"])
            except json.JSONDecodeError:
                metadata = {"raw": row["metadata_json"]}
            events.append(
                {
                    "event_id": row["event_id"],
                    "event_ts": row["event_ts"],
                    "event_kind": row["event_kind"],
                    "decision": row["decision"],
                    "summary": row["summary"],
                    "subject_set": bool(row["subject_set"]),
                    "classification_set": bool(row["classification_set"]),
                    "redaction_metadata_valid": bool(row["redaction_metadata_valid"]),
                    "includes_secret_material": bool(row["includes_secret_material"]),
                    "includes_token_material": bool(row["includes_token_material"]),
                    "redaction_status": row["redaction_status"],
                    "redaction_version": row["redaction_version"],
                    "metadata": metadata,
                    "chain_prev_hash": row["chain_prev_hash"],
                    "chain_hash": row["chain_hash"],
                    "chain_version": row["chain_version"],
                    "created_at": row["created_at"],
                }
            )

        governance_row = conn.execute(
            "SELECT max_entries, max_age_seconds, updated_at FROM audit_retention_governance WHERE id = 1"
        ).fetchone()
        governance = (
            {
                "max_entries": governance_row["max_entries"],
                "max_age_seconds": governance_row["max_age_seconds"],
                "updated_at": governance_row["updated_at"],
            }
            if governance_row is not None
            else None
        )

    print(
        json.dumps(
            {
                "db_path": str(db_path),
                "governance": governance,
                "events": events,
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


def cmd_retention_check(args: argparse.Namespace) -> int:
    now = int(time.time())
    current_entries = args.current_entries
    oldest_age_seconds = args.oldest_age_seconds

    if args.db_path:
        db_path = Path(args.db_path).expanduser()
        with connect_db(db_path) as conn:
            ensure_schema(conn)
            db_entries, db_oldest_age = current_entry_stats(conn, now)
        if current_entries is None:
            current_entries = db_entries
        if oldest_age_seconds is None:
            oldest_age_seconds = db_oldest_age

    if current_entries is None:
        current_entries = 0
    if oldest_age_seconds is None:
        oldest_age_seconds = 0

    decision = retention_policy_decision(
        current_entries=current_entries,
        max_entries=args.max_entries,
        oldest_age_seconds=oldest_age_seconds,
        max_age_seconds=args.max_age_seconds,
    )

    print(
        json.dumps(
            {
                "current_entries": current_entries,
                "oldest_age_seconds": oldest_age_seconds,
                "max_entries": args.max_entries,
                "max_age_seconds": args.max_age_seconds,
                "decision": decision,
            },
            sort_keys=True,
        )
    )
    if args.enforce and decision == "Retention_Deny_Invalid_Limits":
        return 1
    return 0


def cmd_verify_chain(args: argparse.Namespace) -> int:
    db_path = Path(args.db_path).expanduser()

    with connect_db(db_path) as conn:
        ensure_schema(conn)
        valid, issues, checked_entries = verify_chain_metadata(conn)

    print(
        json.dumps(
            {
                "db_path": str(db_path),
                "checked_entries": checked_entries,
                "valid": valid,
                "issues": issues,
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0 if valid else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Durable local audit log with strict redaction and retention governance."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    append_parser = subparsers.add_parser("append", help="Append a redacted audit event.")
    append_parser.add_argument(
        "--db",
        dest="db_path",
        default=str(Path.home() / ".vericlaw" / "audit-events.sqlite"),
        help="SQLite database path.",
    )
    append_parser.add_argument("--event-kind", required=True, help="Audit event kind identifier.")
    append_parser.add_argument("--decision", required=True, help="Policy decision (allow/deny/etc).")
    append_parser.add_argument("--summary", required=True, help="Redacted event summary.")
    append_parser.add_argument(
        "--metadata-json",
        default="{}",
        help="Additional redacted metadata as a JSON object.",
    )
    append_parser.add_argument(
        "--redaction-version",
        default="v1",
        help="Redaction policy/schema version.",
    )
    append_parser.add_argument("--event-ts", type=int, help="Unix epoch seconds for the event.")
    append_parser.add_argument(
        "--subject-set",
        type=parse_bool,
        default=True,
        help="Whether subject metadata is set (true/false).",
    )
    append_parser.add_argument(
        "--classification-set",
        type=parse_bool,
        default=True,
        help="Whether classification metadata is set (true/false).",
    )
    append_parser.add_argument(
        "--redaction-metadata-valid",
        type=parse_bool,
        default=True,
        help="Whether redaction metadata is valid (true/false).",
    )
    append_parser.add_argument(
        "--includes-secret-material",
        type=parse_bool,
        default=False,
        help="Whether payload includes secret material (must be false).",
    )
    append_parser.add_argument(
        "--includes-token-material",
        type=parse_bool,
        default=False,
        help="Whether payload includes token material (must be false).",
    )
    append_parser.add_argument(
        "--max-entries",
        type=int,
        default=1_000,
        help="Retention cap for total rows.",
    )
    append_parser.add_argument(
        "--max-age-seconds",
        type=int,
        default=2_592_000,
        help="Retention cap for row age in seconds.",
    )

    query_parser = subparsers.add_parser("query", help="Query persisted audit events.")
    query_parser.add_argument(
        "--db",
        dest="db_path",
        default=str(Path.home() / ".vericlaw" / "audit-events.sqlite"),
        help="SQLite database path.",
    )
    query_parser.add_argument("--event-kind", help="Filter by event kind.")
    query_parser.add_argument("--decision", help="Filter by decision.")
    query_parser.add_argument("--since-epoch", type=int, help="Filter for event_ts >= since.")
    query_parser.add_argument("--until-epoch", type=int, help="Filter for event_ts <= until.")
    query_parser.add_argument("--limit", type=int, default=100, help="Max rows to return.")
    query_parser.add_argument("--offset", type=int, default=0, help="Offset into ordered results.")

    retention_parser = subparsers.add_parser(
        "retention-check", help="Evaluate retention governance for provided state."
    )
    retention_parser.add_argument("--db", dest="db_path", help="Optional DB path to infer current state.")
    retention_parser.add_argument("--current-entries", type=int, help="Current entry count.")
    retention_parser.add_argument("--oldest-age-seconds", type=int, help="Oldest entry age in seconds.")
    retention_parser.add_argument("--max-entries", type=int, required=True, help="Retention max entries.")
    retention_parser.add_argument(
        "--max-age-seconds",
        type=int,
        required=True,
        help="Retention max age in seconds.",
    )
    retention_parser.add_argument(
        "--enforce",
        action="store_true",
        help="Exit non-zero when limits are invalid.",
    )

    verify_parser = subparsers.add_parser(
        "verify-chain", help="Validate tamper-evident audit chain metadata."
    )
    verify_parser.add_argument(
        "--db",
        dest="db_path",
        default=str(Path.home() / ".vericlaw" / "audit-events.sqlite"),
        help="SQLite database path.",
    )

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        if args.command == "append":
            return cmd_append(args)
        if args.command == "query":
            return cmd_query(args)
        if args.command == "retention-check":
            return cmd_retention_check(args)
        if args.command == "verify-chain":
            return cmd_verify_chain(args)
    except (ValueError, sqlite3.IntegrityError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    parser.error(f"Unsupported command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
