#!/usr/bin/env bash
# Build .deb and .rpm packages using nfpm
set -euo pipefail

VERSION="${VERSION:-0.1.0}"
ARCH="${ARCH:-amd64}"

# Check nfpm is installed
if ! command -v nfpm >/dev/null 2>&1; then
    echo "Installing nfpm..."
    curl -sfL https://install.goreleaser.com/github.com/goreleaser/nfpm.sh | sh -s -- -b /usr/local/bin
fi

# Build .deb
echo "Building .deb package (${ARCH})..."
VERSION="${VERSION}" GOARCH="${ARCH}" nfpm package \
    --config packaging/nfpm.yaml \
    --packager deb \
    --target "release/vericlaw_${VERSION}_${ARCH}.deb"

# Build .rpm
echo "Building .rpm package (${ARCH})..."
VERSION="${VERSION}" GOARCH="${ARCH}" nfpm package \
    --config packaging/nfpm.yaml \
    --packager rpm \
    --target "release/vericlaw-${VERSION}-1.${ARCH}.rpm"

echo "Packages built in release/"
ls -la release/vericlaw*
