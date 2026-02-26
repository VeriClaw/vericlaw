#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/build_multiarch_image.sh

Environment variables:
  IMAGE_NAME       Image name (default: vericlaw)
  IMAGE_TAG        Image tag (default: latest)
  IMAGE_PLATFORMS  Buildx platform list (default: linux/amd64,linux/arm64,linux/arm/v7)
  DOCKERFILE_PATH  Dockerfile path (default: <project_root>/Dockerfile.release)
  BUILD_CONTEXT    Docker build context path (default: <project_root>)
  PUSH_IMAGE       Set to true to push image (default: false)
  LOAD_IMAGE       Set to true to load image into local Docker daemon (single-platform only, default: false)
  BUILDX_BUILDER   Optional buildx builder name
  ATTEST_PROVENANCE  Set to true to emit build provenance attestation (default: true)
  ATTEST_SBOM        Set to true to emit SBOM attestation (default: true)
  BUILD_METADATA_PATH Path for buildx metadata output (default: <project_root>/tests/multiarch_build_metadata.json)
  TRUST_METADATA_PATH Path for trust metadata summary (default: <project_root>/tests/multiarch_trust_metadata.json)
  SIGN_IMAGE       Set to true to sign pushed image digest (default: false)
  SIGNING_TOOL     Signing tool when SIGN_IMAGE=true (default: cosign)
  COSIGN_KEY       Optional cosign key reference/path passed to --key
  COSIGN_EXTRA_ARGS Optional extra args for cosign sign (space-delimited)
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
image_name="${IMAGE_NAME:-vericlaw}"
image_tag="${IMAGE_TAG:-latest}"
image_platforms="${IMAGE_PLATFORMS:-linux/amd64,linux/arm64,linux/arm/v7}"
dockerfile_path="${DOCKERFILE_PATH:-${project_root}/Dockerfile.release}"
build_context="${BUILD_CONTEXT:-${project_root}}"
push_image="${PUSH_IMAGE:-false}"
load_image="${LOAD_IMAGE:-false}"
buildx_builder="${BUILDX_BUILDER:-}"
attest_provenance="${ATTEST_PROVENANCE:-true}"
attest_sbom="${ATTEST_SBOM:-true}"
build_metadata_path="${BUILD_METADATA_PATH:-${project_root}/tests/multiarch_build_metadata.json}"
trust_metadata_path="${TRUST_METADATA_PATH:-${project_root}/tests/multiarch_trust_metadata.json}"
sign_image="${SIGN_IMAGE:-false}"
signing_tool="${SIGNING_TOOL:-cosign}"
cosign_key="${COSIGN_KEY:-}"
cosign_extra_args="${COSIGN_EXTRA_ARGS:-}"
signing_performed="false"

if [[ "${dockerfile_path}" != /* ]]; then
  dockerfile_path="${project_root}/${dockerfile_path}"
fi

if [[ "${build_context}" != /* ]]; then
  build_context="${project_root}/${build_context}"
fi

if [[ "${build_metadata_path}" != /* ]]; then
  build_metadata_path="${project_root}/${build_metadata_path}"
fi

if [[ "${trust_metadata_path}" != /* ]]; then
  trust_metadata_path="${project_root}/${trust_metadata_path}"
fi

if [[ "${push_image}" != "true" && "${push_image}" != "false" ]]; then
  echo "PUSH_IMAGE must be true or false." >&2
  exit 2
fi

if [[ "${load_image}" != "true" && "${load_image}" != "false" ]]; then
  echo "LOAD_IMAGE must be true or false." >&2
  exit 2
fi

if [[ "${attest_provenance}" != "true" && "${attest_provenance}" != "false" ]]; then
  echo "ATTEST_PROVENANCE must be true or false." >&2
  exit 2
fi

if [[ "${attest_sbom}" != "true" && "${attest_sbom}" != "false" ]]; then
  echo "ATTEST_SBOM must be true or false." >&2
  exit 2
fi

if [[ "${sign_image}" != "true" && "${sign_image}" != "false" ]]; then
  echo "SIGN_IMAGE must be true or false." >&2
  exit 2
fi

if [[ "${push_image}" == "true" && "${load_image}" == "true" ]]; then
  echo "PUSH_IMAGE and LOAD_IMAGE cannot both be true." >&2
  exit 2
fi

if [[ "${load_image}" == "true" && "${image_platforms}" == *","* ]]; then
  echo "LOAD_IMAGE=true only supports a single platform; current: ${image_platforms}" >&2
  exit 2
fi

if [[ "${sign_image}" == "true" && "${push_image}" != "true" ]]; then
  echo "SIGN_IMAGE=true requires PUSH_IMAGE=true so the multi-arch manifest digest can be signed." >&2
  exit 2
fi

if [[ "${sign_image}" == "true" ]]; then
  case "${signing_tool}" in
    cosign) ;;
    *)
      echo "Unsupported SIGNING_TOOL=${signing_tool}. Supported tools: cosign" >&2
      exit 2
      ;;
  esac
  if ! command -v cosign >/dev/null 2>&1; then
    echo "SIGN_IMAGE=true but cosign is unavailable; install cosign or disable signing." >&2
    exit 1
  fi
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker CLI not found. Install Docker and retry." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is unavailable. Start Docker and retry." >&2
  exit 1
fi

if ! docker buildx version >/dev/null 2>&1; then
  echo "Docker buildx is unavailable. Install/enable buildx and retry." >&2
  exit 1
fi

if [[ ! -f "${dockerfile_path}" ]]; then
  echo "Dockerfile not found: ${dockerfile_path}" >&2
  exit 1
fi

if [[ ! -d "${build_context}" ]]; then
  echo "Build context directory not found: ${build_context}" >&2
  exit 1
fi

image_ref="${image_name}:${image_tag}"
build_args=(
  --file "${dockerfile_path}"
  --platform "${image_platforms}"
  --tag "${image_ref}"
)
supports_metadata_file="false"
if docker buildx build --help 2>/dev/null | grep -Fq -- "--metadata-file"; then
  supports_metadata_file="true"
fi

mkdir -p "$(dirname "${build_metadata_path}")"
if [[ "${supports_metadata_file}" == "true" ]]; then
  build_args+=(--metadata-file "${build_metadata_path}")
elif [[ "${sign_image}" == "true" ]]; then
  echo "SIGN_IMAGE=true requires docker buildx --metadata-file support to resolve the pushed manifest digest." >&2
  exit 1
fi

mkdir -p "$(dirname "${trust_metadata_path}")"

if [[ -n "${buildx_builder}" ]]; then
  build_args+=(--builder "${buildx_builder}")
fi

if [[ "${push_image}" == "true" ]]; then
  build_args+=(--push)
elif [[ "${load_image}" == "true" ]]; then
  build_args+=(--load)
else
  build_args+=(--output=type=image,push=false)
fi

if [[ "${attest_provenance}" == "true" ]]; then
  build_args+=(--provenance=true)
fi

if [[ "${attest_sbom}" == "true" ]]; then
  build_args+=(--sbom=true)
fi

echo "Building ${image_ref} for platforms: ${image_platforms}"
docker buildx build "${build_args[@]}" "${build_context}"

if [[ "${supports_metadata_file}" != "true" ]]; then
  cat >"${build_metadata_path}" <<'EOF'
{
  "note": "docker buildx --metadata-file is unavailable in this environment"
}
EOF
fi

image_digest="$(python3 - "${build_metadata_path}" <<'PY'
import json
import pathlib
import sys

metadata_path = pathlib.Path(sys.argv[1])
digest = ""
if metadata_path.is_file():
    try:
        payload = json.loads(metadata_path.read_text(encoding="utf-8"))
    except Exception:
        payload = {}
    for key in ("containerimage.digest", "containerimage.descriptor.digest"):
        value = payload.get(key)
        if isinstance(value, str) and value.startswith("sha256:"):
            digest = value
            break
print(digest)
PY
)"
image_ref_with_digest=""
if [[ -n "${image_digest}" ]]; then
  image_ref_with_digest="${image_ref}@${image_digest}"
fi

if [[ "${sign_image}" == "true" ]]; then
  if [[ -z "${image_ref_with_digest}" ]]; then
    echo "SIGN_IMAGE=true but image digest was not found in ${build_metadata_path}." >&2
    exit 1
  fi

  sign_cmd=(cosign sign --yes)
  if [[ -n "${cosign_key}" ]]; then
    sign_cmd+=(--key "${cosign_key}")
  fi
  if [[ -n "${cosign_extra_args}" ]]; then
    read -r -a extra_args <<<"${cosign_extra_args}"
    sign_cmd+=("${extra_args[@]}")
  fi

  echo "Signing ${image_ref_with_digest} using ${signing_tool}"
  "${sign_cmd[@]}" "${image_ref_with_digest}"
  signing_performed="true"
fi

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
python3 - "${trust_metadata_path}" "${generated_at}" "${image_name}" "${image_tag}" "${image_platforms}" "${image_ref}" "${image_digest}" "${push_image}" "${load_image}" "${attest_provenance}" "${attest_sbom}" "${build_metadata_path}" "${project_root}" "${sign_image}" "${signing_performed}" "${signing_tool}" "${cosign_key}" <<'PY'
import hashlib
import json
import pathlib
import sys

trust_path = pathlib.Path(sys.argv[1])
generated_at = sys.argv[2]
image_name = sys.argv[3]
image_tag = sys.argv[4]
image_platforms = [entry for entry in sys.argv[5].split(",") if entry]
image_ref = sys.argv[6]
image_digest = sys.argv[7]
push_image = sys.argv[8] == "true"
load_image = sys.argv[9] == "true"
attest_provenance = sys.argv[10] == "true"
attest_sbom = sys.argv[11] == "true"
build_metadata_path = pathlib.Path(sys.argv[12])
project_root = pathlib.Path(sys.argv[13])
sign_requested = sys.argv[14] == "true"
sign_performed = sys.argv[15] == "true"
signing_tool = sys.argv[16]
cosign_key = sys.argv[17]

def rel_or_abs(path: pathlib.Path) -> str:
    try:
        return path.resolve().relative_to(project_root.resolve()).as_posix()
    except Exception:
        return path.as_posix()

payload = {
    "generated_at": generated_at,
    "image": {
        "name": image_name,
        "tag": image_tag,
        "reference": image_ref,
        "platforms": image_platforms,
    },
    "build": {
        "push_image": push_image,
        "load_image": load_image,
        "attest_provenance": attest_provenance,
        "attest_sbom": attest_sbom,
        "buildx_metadata_path": rel_or_abs(build_metadata_path),
    },
    "signing": {
        "requested": sign_requested,
        "performed": sign_performed,
        "tool": signing_tool if sign_requested else None,
        "key_configured": bool(cosign_key),
    },
}

if image_digest:
    payload["image"]["digest"] = image_digest
    payload["image"]["reference_with_digest"] = f"{image_ref}@{image_digest}"

if build_metadata_path.is_file():
    payload["build"]["buildx_metadata_sha256"] = hashlib.sha256(build_metadata_path.read_bytes()).hexdigest()

trust_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "build-multiarch: build_metadata=${build_metadata_path}"
echo "build-multiarch: trust_metadata=${trust_metadata_path}"
if [[ -n "${image_digest}" ]]; then
  echo "build-multiarch: digest=${image_digest}"
fi
