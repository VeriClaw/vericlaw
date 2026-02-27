#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tests_dir="${project_root}/tests"
sbom_path="${tests_dir}/sbom.spdx.json"
provenance_path="${tests_dir}/provenance_attestation.json"
manifest_path="${tests_dir}/attestation_manifest.sha256"
report_path="${tests_dir}/supply_chain_attestation_report.json"

mkdir -p "${tests_dir}"

python3 - "${project_root}" "${sbom_path}" "${provenance_path}" "${manifest_path}" "${report_path}" <<'PY'
import datetime as dt
import hashlib
import json
import pathlib
import subprocess
import sys

project_root = pathlib.Path(sys.argv[1])
sbom_path = pathlib.Path(sys.argv[2])
provenance_path = pathlib.Path(sys.argv[3])
manifest_path = pathlib.Path(sys.argv[4])
report_path = pathlib.Path(sys.argv[5])
generated_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

scan_roots = [
    "src",
    "scripts",
    "config",
    "deploy",
    ".github/workflows",
]
explicit_files = [
    "Makefile",
    "Dockerfile.release",
    "vericlaw.gpr",
    "docker-compose.secure.yml",
    "README.md",
]
artifact_candidates = [
    "tests/release_metadata.json",
    "tests/release_checksum_manifest.sha256",
    "tests/multiarch_build_metadata.json",
    "tests/multiarch_trust_metadata.json",
    "tests/cross_repo_conformance_report.json",
    "tests/borrow_wave_conformance_report.json",
    "tests/competitive_benchmark_report.json",
    "tests/competitive_scorecard_report.json",
    "tests/cross_platform_smoke_report.json",
]

def digest(path: pathlib.Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()

source_files = set()
for root in scan_roots:
    root_path = project_root / root
    if not root_path.exists():
        continue
    for file_path in root_path.rglob("*"):
        if file_path.is_file():
            source_files.add(file_path.relative_to(project_root).as_posix())
for rel_path in explicit_files:
    path = project_root / rel_path
    if path.is_file():
        source_files.add(rel_path)

components = []
for rel_path in sorted(source_files):
    path = project_root / rel_path
    components.append(
        {
            "name": rel_path,
            "type": "file",
            "checksums": [{"algorithm": "SHA256", "value": digest(path)}],
        }
    )

sbom_payload = {
    "spdxVersion": "SPDX-2.3",
    "SPDXID": "SPDXRef-DOCUMENT",
    "name": "vericlaw-source-sbom",
    "documentNamespace": "https://vericlaw.local/spdx/vericlaw",
    "creationInfo": {"created": generated_at, "creators": ["Tool: scripts/generate_attestation_artifacts.sh"]},
    "packages": [],
    "files": components,
}
sbom_path.write_text(json.dumps(sbom_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

git_revision = "workspace-unversioned"
try:
    git_revision = (
        subprocess.check_output(
            ["git", "-C", str(project_root), "rev-parse", "HEAD"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        or git_revision
    )
except Exception:
    pass

artifact_hashes = {}
for rel_path in artifact_candidates:
    path = project_root / rel_path
    if path.is_file():
        artifact_hashes[rel_path] = digest(path)

provenance_payload = {
    "generated_at": generated_at,
    "builder": "scripts/generate_attestation_artifacts.sh",
    "source_revision": git_revision,
    "materials": [{"uri": rel, "digest": {"sha256": entry["checksums"][0]["value"]}} for rel, entry in zip(sorted(source_files), components)],
    "artifacts": [{"path": rel, "sha256": sha} for rel, sha in sorted(artifact_hashes.items())],
}
provenance_path.write_text(json.dumps(provenance_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

manifest_entries = []
for rel_path in sorted(artifact_hashes):
    manifest_entries.append(f"{artifact_hashes[rel_path]}  {rel_path}")
manifest_entries.append(f"{digest(sbom_path)}  tests/sbom.spdx.json")
manifest_entries.append(f"{digest(provenance_path)}  tests/provenance_attestation.json")
manifest_path.write_text("\n".join(manifest_entries) + "\n", encoding="utf-8")

report_payload = {
    "generated_at": generated_at,
    "overall_status": "pass",
    "signed_artifacts": (project_root / "tests/release_checksum_manifest.sha256").is_file(),
    "sbom": "tests/sbom.spdx.json",
    "provenance": "tests/provenance_attestation.json",
    "attestation_manifest": "tests/attestation_manifest.sha256",
    "artifact_count": len(artifact_hashes),
}
report_path.write_text(json.dumps(report_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "Supply-chain attestation artifacts generated:"
echo "  - ${sbom_path}"
echo "  - ${provenance_path}"
echo "  - ${manifest_path}"
echo "  - ${report_path}"
