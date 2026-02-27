#!/usr/bin/env bash
# Updates Homebrew formula SHA-256 hashes after a release
set -euo pipefail
VERSION="${1:?Usage: $0 <version>}"
FORMULA="packaging/homebrew/vericlaw.rb"

for target in macos-universal linux-x86_64 linux-aarch64; do
  URL="https://github.com/vericlaw/vericlaw/releases/download/v${VERSION}/vericlaw-v${VERSION}-${target}.tar.gz"
  echo "Fetching SHA-256 for ${target}..."
  SHA=$(curl -fsSL "${URL}" | sha256sum | cut -d' ' -f1)
  echo "  ${target}: ${SHA}"
  
  case "${target}" in
    macos-universal)
      sed -i "s/PLACEHOLDER_SHA256_MACOS_ARM64/${SHA}/" "${FORMULA}"
      sed -i "s/PLACEHOLDER_SHA256_MACOS_X86_64/${SHA}/" "${FORMULA}"
      ;;
    linux-x86_64)
      sed -i "s/PLACEHOLDER_SHA256_LINUX_X86_64/${SHA}/" "${FORMULA}"
      ;;
    linux-aarch64)
      sed -i "s/PLACEHOLDER_SHA256_LINUX_AARCH64/${SHA}/" "${FORMULA}"
      ;;
  esac
done

# Update version
sed -i "s/version \".*\"/version \"${VERSION}\"/" "${FORMULA}"
echo "Formula updated for v${VERSION}"
