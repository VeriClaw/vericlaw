# future/deploy/

Deployment configurations not needed for v1.0-minimal's primary targets (Linux + Raspberry Pi 4).

v1.0-minimal keeps: `deploy/linux/` (seccomp/AppArmor) and `deploy/systemd/` (Pi service unit).

## Contents

| Directory | What it is | Returns at |
|-----------|-----------|------------|
| `macos/` | macOS launchd plist for running VeriClaw as a login item / LaunchAgent | v1.1 |
| `windows/` | Windows service installer (PowerShell) | v1.2 |
| `compose-full/` | Full Docker Compose configuration for multi-service gateway deployment (all bridges + Ada runtime) | v1.3 |

## macOS v1.0-minimal note

On macOS in v1.0-minimal, users run `vericlaw chat` manually or set up their own launch agent. The `launchd` plist returns in v1.1 when macOS is a first-class deployment target.

## Pi 4 deployment (v1.0-minimal)

See `docs/pi-deployment.md` — three steps using `deploy/systemd/vericlaw.service`.
