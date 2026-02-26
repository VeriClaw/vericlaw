#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/verify_supply_chain_artifacts.sh [--help]

Verify supply-chain provenance and optional image trust/signature metadata.

Environment variables:
  ATTESTATION_REPORT_PATH   Attestation report path
                            (default: <project_root>/tests/supply_chain_attestation_report.json)
  TRUST_METADATA_PATH       Image trust metadata path
                            (default: <project_root>/tests/multiarch_trust_metadata.json)
  VERIFICATION_REPORT_PATH  Verification report output path
                            (default: <project_root>/tests/supply_chain_verification_report.json)
  REQUIRE_TRUST_METADATA    Require trust metadata verification (default: false)
  REQUIRE_IMAGE_SIGNATURE   Require signed-image evidence in trust metadata (default: false)
EOF
}

if [[ $# -gt 0 ]]; then
  case "$1" in
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
fi

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
attestation_report_path="${ATTESTATION_REPORT_PATH:-${project_root}/tests/supply_chain_attestation_report.json}"
trust_metadata_path="${TRUST_METADATA_PATH:-${project_root}/tests/multiarch_trust_metadata.json}"
verification_report_path="${VERIFICATION_REPORT_PATH:-${project_root}/tests/supply_chain_verification_report.json}"
require_trust_metadata="${REQUIRE_TRUST_METADATA:-false}"
require_image_signature="${REQUIRE_IMAGE_SIGNATURE:-false}"

for flag in require_trust_metadata require_image_signature; do
  value="${!flag}"
  if [[ "${value}" != "true" && "${value}" != "false" ]]; then
    echo "${flag^^} must be true or false." >&2
    exit 2
  fi
done

if [[ "${require_image_signature}" == "true" ]]; then
  require_trust_metadata="true"
fi

mkdir -p "$(dirname "${verification_report_path}")"

python3 - "${project_root}" "${attestation_report_path}" "${trust_metadata_path}" "${verification_report_path}" "${require_trust_metadata}" "${require_image_signature}" <<'PY'
import datetime as dt
import hashlib
import json
import pathlib
import re
import sys

project_root = pathlib.Path(sys.argv[1])
attestation_report_path = pathlib.Path(sys.argv[2])
trust_metadata_path = pathlib.Path(sys.argv[3])
verification_report_path = pathlib.Path(sys.argv[4])
require_trust_metadata = sys.argv[5] == "true"
require_image_signature = sys.argv[6] == "true"

checks = []
overall_status = "pass"


def to_rel(path: pathlib.Path) -> str:
    try:
        return path.resolve().relative_to(project_root.resolve()).as_posix()
    except Exception:
        return path.as_posix()


def resolve(path_value: str) -> pathlib.Path:
    path = pathlib.Path(path_value)
    if path.is_absolute():
        return path
    return project_root / path


def record(check: str, status: str, message: str) -> None:
    global overall_status
    checks.append({"check": check, "status": status, "message": message})
    if status == "fail":
        overall_status = "fail"


def load_json(path: pathlib.Path, check_name: str):
    if not path.is_file():
        record(check_name, "fail", f"Missing file: {to_rel(path)}")
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        record(check_name, "fail", f"Invalid JSON in {to_rel(path)}: {exc}")
        return None
    record(check_name, "pass", f"Loaded {to_rel(path)}")
    return payload


def sha256(path: pathlib.Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


attestation_report = load_json(attestation_report_path, "attestation-report-json")
manifest_path = None
provenance_path = None
sbom_path = None

if attestation_report is not None:
    if isinstance(attestation_report, dict):
        if attestation_report.get("overall_status") == "pass":
            record("attestation-report-status", "pass", "Attestation report status is pass.")
        else:
            record("attestation-report-status", "fail", "Attestation report overall_status must be pass.")

        for field_name in ("attestation_manifest", "provenance", "sbom"):
            field_value = attestation_report.get(field_name)
            if not isinstance(field_value, str) or not field_value:
                record(f"attestation-report-{field_name}", "fail", f"Missing or invalid '{field_name}' path.")
                continue
            field_path = resolve(field_value)
            if not field_path.is_file():
                record(f"attestation-report-{field_name}", "fail", f"Referenced file missing: {field_value}")
                continue
            record(f"attestation-report-{field_name}", "pass", f"Found {field_value}")
            if field_name == "attestation_manifest":
                manifest_path = field_path
            elif field_name == "provenance":
                provenance_path = field_path
            elif field_name == "sbom":
                sbom_path = field_path
    else:
        record("attestation-report-structure", "fail", "Attestation report must be a JSON object.")

if manifest_path and manifest_path.is_file():
    entry_re = re.compile(r"^([0-9a-fA-F]{64})\s{2}(.+)$")
    manifest_errors = []
    verified_entries = {}
    for line in manifest_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        match = entry_re.match(line)
        if not match:
            manifest_errors.append(f"Invalid manifest line format: {line}")
            continue
        expected_digest, rel_path = match.groups()
        target_path = resolve(rel_path)
        if not target_path.is_file():
            manifest_errors.append(f"Manifest target missing: {rel_path}")
            continue
        actual_digest = sha256(target_path)
        if actual_digest.lower() != expected_digest.lower():
            manifest_errors.append(
                f"Checksum mismatch for {rel_path}: expected {expected_digest.lower()} got {actual_digest.lower()}"
            )
            continue
        verified_entries[to_rel(target_path)] = expected_digest.lower()

    if provenance_path is not None and to_rel(provenance_path) not in verified_entries:
        manifest_errors.append(f"Manifest missing provenance entry: {to_rel(provenance_path)}")
    if sbom_path is not None and to_rel(sbom_path) not in verified_entries:
        manifest_errors.append(f"Manifest missing SBOM entry: {to_rel(sbom_path)}")

    if manifest_errors:
        record("attestation-manifest-integrity", "fail", "; ".join(manifest_errors))
    else:
        record("attestation-manifest-integrity", "pass", f"Verified {len(verified_entries)} manifest entries.")

if provenance_path and provenance_path.is_file():
    provenance_payload = load_json(provenance_path, "provenance-json")
    if provenance_payload is not None:
        if not isinstance(provenance_payload, dict):
            record("provenance-structure", "fail", "Provenance payload must be a JSON object.")
        else:
            if provenance_payload.get("builder") == "scripts/generate_attestation_artifacts.sh":
                record("provenance-builder", "pass", "Builder matches expected script.")
            else:
                record("provenance-builder", "fail", "Unexpected provenance builder.")

            materials = provenance_payload.get("materials")
            if isinstance(materials, list) and materials:
                malformed_materials = [
                    material
                    for material in materials
                    if not isinstance(material, dict)
                    or not isinstance(material.get("uri"), str)
                    or not material.get("uri")
                    or not isinstance(material.get("digest"), dict)
                    or not re.fullmatch(r"[0-9a-fA-F]{64}", str(material.get("digest", {}).get("sha256", "")))
                ]
                if malformed_materials:
                    record("provenance-materials", "fail", "One or more provenance materials are malformed.")
                else:
                    record("provenance-materials", "pass", f"Validated {len(materials)} provenance materials.")
            else:
                record("provenance-materials", "fail", "Provenance materials must be a non-empty list.")

trust_payload = None
if trust_metadata_path.is_file():
    trust_payload = load_json(trust_metadata_path, "trust-metadata-json")
elif require_trust_metadata:
    record("trust-metadata-required", "fail", f"Missing required trust metadata: {to_rel(trust_metadata_path)}")
else:
    record("trust-metadata-required", "skip", f"Optional trust metadata not present: {to_rel(trust_metadata_path)}")

if trust_payload is not None:
    if not isinstance(trust_payload, dict):
        record("trust-metadata-structure", "fail", "Trust metadata payload must be a JSON object.")
    else:
        image = trust_payload.get("image")
        build = trust_payload.get("build")
        signing = trust_payload.get("signing")

        if not isinstance(image, dict) or not isinstance(image.get("reference"), str) or not image.get("reference"):
            record("trust-metadata-image", "fail", "Trust metadata image reference is missing.")
        else:
            record("trust-metadata-image", "pass", "Image reference present.")

        if not isinstance(build, dict):
            record("trust-metadata-build", "fail", "Trust metadata build section is missing.")
        else:
            metadata_path = build.get("buildx_metadata_path")
            if isinstance(metadata_path, str) and metadata_path:
                metadata_file = resolve(metadata_path)
                if metadata_file.is_file():
                    record("trust-metadata-buildx-path", "pass", f"Build metadata found: {metadata_path}")
                else:
                    record("trust-metadata-buildx-path", "fail", f"Build metadata missing: {metadata_path}")
            else:
                record("trust-metadata-buildx-path", "fail", "buildx_metadata_path is missing.")

        if not isinstance(signing, dict):
            record("trust-metadata-signing", "fail", "Trust metadata signing section is missing.")
        else:
            requested = signing.get("requested")
            performed = signing.get("performed")
            if not isinstance(requested, bool) or not isinstance(performed, bool):
                record("trust-metadata-signing", "fail", "Signing requested/performed flags must be booleans.")
            else:
                if requested and not performed:
                    record("trust-metadata-signing-requested", "fail", "Signing was requested but not performed.")
                else:
                    record("trust-metadata-signing-requested", "pass", "Signing requested/performed state is coherent.")

                digest = image.get("digest") if isinstance(image, dict) else None
                reference_with_digest = image.get("reference_with_digest") if isinstance(image, dict) else None
                if performed:
                    if not isinstance(digest, str) or not digest.startswith("sha256:"):
                        record("trust-metadata-digest", "fail", "Signed trust metadata must include image digest.")
                    else:
                        record("trust-metadata-digest", "pass", "Image digest present for signed image.")
                    if not isinstance(reference_with_digest, str) or "@" not in reference_with_digest:
                        record("trust-metadata-reference-with-digest", "fail", "Signed trust metadata must include reference_with_digest.")
                    else:
                        record("trust-metadata-reference-with-digest", "pass", "reference_with_digest present for signed image.")

                if require_image_signature and not performed:
                    record("trust-metadata-signature-required", "fail", "Image signature verification required, but signature evidence is absent.")
                elif require_image_signature and performed:
                    record("trust-metadata-signature-required", "pass", "Required signed-image evidence is present.")

generated_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
report_payload = {
    "generated_at": generated_at,
    "overall_status": overall_status,
    "policy": {
        "require_trust_metadata": require_trust_metadata,
        "require_image_signature": require_image_signature,
    },
    "inputs": {
        "attestation_report": to_rel(attestation_report_path),
        "trust_metadata": to_rel(trust_metadata_path),
    },
    "summary": {
        "total_checks": len(checks),
        "passed_checks": sum(1 for check in checks if check.get("status") == "pass"),
        "failed_checks": sum(1 for check in checks if check.get("status") == "fail"),
        "skipped_checks": sum(1 for check in checks if check.get("status") == "skip"),
    },
    "checks": checks,
}

verification_report_path.write_text(json.dumps(report_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

if overall_status != "pass":
    sys.exit(1)
PY

report_display="${verification_report_path}"
if [[ "${verification_report_path}" == "${project_root}/"* ]]; then
  report_display="${verification_report_path#${project_root}/}"
fi
echo "supply-chain-verify: report=${report_display}"
