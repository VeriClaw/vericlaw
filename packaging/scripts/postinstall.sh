#!/bin/sh
set -e
# Create vericlaw system user if it doesn't exist
if ! getent passwd vericlaw >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin vericlaw
fi
# Create config directory
mkdir -p /etc/vericlaw
chown vericlaw:vericlaw /etc/vericlaw
chmod 750 /etc/vericlaw
# Reload systemd if available
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
fi
