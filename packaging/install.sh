#!/usr/bin/env sh
# VeriClaw Universal Installer
# Usage: curl -fsSL https://get.vericlaw.dev | sh
#    or: sh install.sh [--version 1.0.0] [--dir ~/.local/bin]
set -eu

REPO="vericlaw/vericlaw"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
VERSION=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --dir)     INSTALL_DIR="$2"; shift 2 ;;
    --help)
      echo "Usage: install.sh [--version VERSION] [--dir INSTALL_DIR]"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Detect OS
OS="$(uname -s)"
case "$OS" in
  Linux)  OS_NAME="linux" ;;
  Darwin) OS_NAME="macos" ;;
  MINGW*|MSYS*|CYGWIN*) OS_NAME="windows" ;;
  *) echo "Error: Unsupported OS: $OS"; exit 1 ;;
esac

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)  ARCH_NAME="x86_64" ;;
  aarch64|arm64)  ARCH_NAME="aarch64" ;;
  armv7l|armhf)   ARCH_NAME="armv7" ;;
  *) echo "Error: Unsupported architecture: $ARCH"; exit 1 ;;
esac

# macOS uses universal binary
if [ "$OS_NAME" = "macos" ]; then
  TARGET="macos-universal"
else
  TARGET="${OS_NAME}-${ARCH_NAME}"
fi

# Get latest version if not specified
if [ -z "$VERSION" ]; then
  echo "Fetching latest version..."
  VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | \
    grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/')
  if [ -z "$VERSION" ]; then
    echo "Error: Could not determine latest version"
    exit 1
  fi
fi

echo "Installing VeriClaw v${VERSION} for ${TARGET}..."

# Determine URL and extension
if [ "$OS_NAME" = "windows" ]; then
  EXT="zip"
  BINARY="vericlaw.exe"
else
  EXT="tar.gz"
  BINARY="vericlaw"
fi

URL="https://github.com/${REPO}/releases/download/v${VERSION}/vericlaw-v${VERSION}-${TARGET}.${EXT}"
CHECKSUMS_URL="https://github.com/${REPO}/releases/download/v${VERSION}/checksums-sha256.txt"

# Create temp directory
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Download binary
echo "Downloading from ${URL}..."
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$URL" -o "${TMP_DIR}/archive.${EXT}"
elif command -v wget >/dev/null 2>&1; then
  wget -q "$URL" -O "${TMP_DIR}/archive.${EXT}"
else
  echo "Error: curl or wget required"
  exit 1
fi

# Download and verify checksum
echo "Verifying checksum..."
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$CHECKSUMS_URL" -o "${TMP_DIR}/checksums.txt" 2>/dev/null || true
elif command -v wget >/dev/null 2>&1; then
  wget -q "$CHECKSUMS_URL" -O "${TMP_DIR}/checksums.txt" 2>/dev/null || true
fi

if [ -f "${TMP_DIR}/checksums.txt" ]; then
  EXPECTED=$(grep "vericlaw-v${VERSION}-${TARGET}" "${TMP_DIR}/checksums.txt" | cut -d' ' -f1)
  if [ -n "$EXPECTED" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
      ACTUAL=$(sha256sum "${TMP_DIR}/archive.${EXT}" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
      ACTUAL=$(shasum -a 256 "${TMP_DIR}/archive.${EXT}" | cut -d' ' -f1)
    fi
    if [ -n "${ACTUAL:-}" ] && [ "$ACTUAL" != "$EXPECTED" ]; then
      echo "Error: Checksum mismatch!"
      echo "  Expected: $EXPECTED"
      echo "  Got:      $ACTUAL"
      exit 1
    fi
    echo "  Checksum verified ✓"
  fi
fi

# Extract
if [ "$EXT" = "tar.gz" ]; then
  tar xzf "${TMP_DIR}/archive.${EXT}" -C "${TMP_DIR}"
else
  unzip -q "${TMP_DIR}/archive.${EXT}" -d "${TMP_DIR}"
fi

# Install
mkdir -p "$INSTALL_DIR"
cp "${TMP_DIR}/${BINARY}" "${INSTALL_DIR}/${BINARY}"
chmod +x "${INSTALL_DIR}/${BINARY}"

echo ""
echo "✓ VeriClaw v${VERSION} installed to ${INSTALL_DIR}/${BINARY}"
echo ""

# Check if install dir is in PATH
case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ;;
  *)
    echo "⚠ ${INSTALL_DIR} is not in your PATH."
    echo "  Add it with:"
    echo "    export PATH=\"${INSTALL_DIR}:\$PATH\""
    echo ""
    SHELL_RC=""
    if [ -n "${BASH_VERSION:-}" ] || [ -f "$HOME/.bashrc" ]; then
      SHELL_RC="$HOME/.bashrc"
    elif [ -n "${ZSH_VERSION:-}" ] || [ -f "$HOME/.zshrc" ]; then
      SHELL_RC="$HOME/.zshrc"
    fi
    if [ -n "$SHELL_RC" ]; then
      echo "  Or permanently:"
      echo "    echo 'export PATH=\"${INSTALL_DIR}:\$PATH\"' >> ${SHELL_RC}"
    fi
    ;;
esac

echo "Get started:"
echo "  vericlaw --version"
echo "  vericlaw doctor"
