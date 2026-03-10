#!/bin/sh
# VeriClaw installer — curl -fsSL https://vericlaw.dev/install.sh | sh
# Sets VERICLAW_INSTALL_DIR or VERICLAW_VERSION to override defaults.
set -e

REPO="vericlaw/vericlaw"
INSTALL_DIR="${VERICLAW_INSTALL_DIR:-$HOME/.vericlaw/bin}"
VERSION="${VERICLAW_VERSION:-latest}"

say() { printf "  %s\n" "$1"; }
die() { printf "\n✗  %s\n   %s\n\n" "$1" "$2" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required tool not found: $1" "Install $1 and retry."; }

OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS" in
  Linux)  case "$ARCH" in x86_64) T="linux-x86_64";; aarch64) T="linux-aarch64";; *) die "Unsupported Linux arch: $ARCH" "See https://github.com/$REPO";; esac;;
  Darwin) case "$ARCH" in arm64)  T="macos-arm64";;  x86_64)  T="macos-x86_64";;  *) die "Unsupported macOS arch: $ARCH"  "See https://github.com/$REPO";; esac;;
  *) die "Unsupported OS: $OS" "Windows: download manually from https://github.com/$REPO/releases";;
esac

need curl; need tar
command -v sha256sum >/dev/null 2>&1 || need shasum

printf "\nVeriClaw installer\n\n"

if [ "$VERSION" = "latest" ]; then
  say "Fetching latest version..."
  VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | sed 's/.*"tag_name": "\(.*\)".*/\1/')"
  [ -n "$VERSION" ] || die "Failed to fetch latest version" "Pin a version: VERICLAW_VERSION=v1.0.0"
fi

say "Version: $VERSION  Target: $T  Install: $INSTALL_DIR"; printf "\n"

ARCHIVE="vericlaw-${T}.tar.gz"
BASE_URL="https://github.com/$REPO/releases/download/$VERSION"
TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT

say "Downloading..."
curl -fsSL --progress-bar "$BASE_URL/$ARCHIVE"        -o "$TMPDIR/$ARCHIVE"        || die "Download failed"          "$BASE_URL/$ARCHIVE"
curl -fsSL                 "$BASE_URL/$ARCHIVE.sha256" -o "$TMPDIR/$ARCHIVE.sha256" || die "Checksum download failed"  "$BASE_URL/$ARCHIVE.sha256"

say "Verifying checksum..."
(cd "$TMPDIR" && \
  if command -v sha256sum >/dev/null 2>&1; then sha256sum -c "$ARCHIVE.sha256" >/dev/null 2>&1
  else shasum -a 256 -c "$ARCHIVE.sha256" >/dev/null 2>&1; fi) \
  || die "Checksum mismatch" "The archive may be corrupt — try again."
say "Checksum verified ✓"

say "Installing..."
tar -xzf "$TMPDIR/$ARCHIVE" -C "$TMPDIR"
mkdir -p "$INSTALL_DIR"
install -m 755 "$TMPDIR/vericlaw"        "$INSTALL_DIR/vericlaw"        || die "Install failed" "Check permissions on $INSTALL_DIR"
install -m 755 "$TMPDIR/vericlaw-signal" "$INSTALL_DIR/vericlaw-signal" || die "Install failed" "Check permissions on $INSTALL_DIR"
say "Installed to $INSTALL_DIR"

PATH_LINE="export PATH=\"\$PATH:$INSTALL_DIR\""
add_to_path() { grep -qF "$INSTALL_DIR" "$1" 2>/dev/null || printf "\n# VeriClaw\n%s\n" "$PATH_LINE" >> "$1" && say "Added to PATH in $1"; }

if ! echo "$PATH" | grep -qF "$INSTALL_DIR"; then
  if   [ -f "$HOME/.zshrc"   ]; then add_to_path "$HOME/.zshrc"
  elif [ -f "$HOME/.bashrc"  ]; then add_to_path "$HOME/.bashrc"
  elif [ -f "$HOME/.profile" ]; then add_to_path "$HOME/.profile"; fi
fi

printf "\n✓  VeriClaw %s installed\n\n  Run: vericlaw onboard\n\n  (You may need to: source ~/.zshrc)\n\n" "$VERSION"
