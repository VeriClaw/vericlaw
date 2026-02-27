#!/bin/sh
set -e
# Stop and disable service if running
if command -v systemctl >/dev/null 2>&1; then
    systemctl stop vericlaw 2>/dev/null || true
    systemctl disable vericlaw 2>/dev/null || true
fi
