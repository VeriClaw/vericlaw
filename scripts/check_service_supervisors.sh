#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
systemd_unit="${project_root}/deploy/systemd/vericlaw.service"
launchd_plist="${project_root}/deploy/launchd/com.vericlaw.plist"
windows_installer="${project_root}/deploy/windows/install-vericlaw-service.ps1"

for file in "${systemd_unit}" "${launchd_plist}" "${windows_installer}"; do
  if [[ ! -f "${file}" ]]; then
    echo "Missing supervisor artifact: ${file}" >&2
    exit 1
  fi
done

python3 - "${systemd_unit}" "${launchd_plist}" "${windows_installer}" <<'PY'
import configparser
import pathlib
import plistlib
import re
import sys

systemd_path = pathlib.Path(sys.argv[1])
launchd_path = pathlib.Path(sys.argv[2])
windows_path = pathlib.Path(sys.argv[3])
errors = []

unit = configparser.ConfigParser(interpolation=None, strict=False)
unit.optionxform = str
try:
    unit.read_string(systemd_path.read_text(encoding="utf-8"))
except Exception as exc:
    errors.append(f"Unable to parse systemd unit '{systemd_path}': {exc}")
else:
    required_systemd = {
        "Unit": {
            "After": "network-online.target",
            "Wants": "network-online.target",
        },
        "Service": {
            "Type": "simple",
            "User": "vericlaw",
            "Group": "vericlaw",
            "WorkingDirectory": "/opt/vericlaw",
            "ExecStart": "/opt/vericlaw/bin/vericlaw",
            "Restart": "on-failure",
            "RestartSec": "5",
            "NoNewPrivileges": "true",
            "PrivateTmp": "true",
            "ProtectSystem": "strict",
            "ProtectHome": "true",
            "ProtectControlGroups": "true",
            "ProtectKernelTunables": "true",
            "ProtectKernelModules": "true",
            "ProtectClock": "true",
            "RestrictNamespaces": "true",
            "RestrictRealtime": "true",
            "LockPersonality": "true",
            "MemoryDenyWriteExecute": "true",
            "CapabilityBoundingSet": "",
            "AmbientCapabilities": "",
            "ReadWritePaths": "/tmp",
            "RuntimeDirectory": "vericlaw",
            "RuntimeDirectoryMode": "0750",
        },
        "Install": {
            "WantedBy": "multi-user.target",
        },
    }
    for section, required_values in required_systemd.items():
        if not unit.has_section(section):
            errors.append(f"Systemd unit missing required section [{section}]")
            continue
        for key, expected in required_values.items():
            if not unit.has_option(section, key):
                errors.append(f"Systemd unit missing required setting: {key}")
                continue
            actual = unit.get(section, key)
            if actual != expected:
                errors.append(f"Systemd unit has {key}={actual!r}, expected {expected!r}")

try:
    plist_payload = plistlib.loads(launchd_path.read_bytes())
except Exception as exc:
    errors.append(f"Unable to parse launchd plist '{launchd_path}': {exc}")
else:
    required_plist = {
        "Label": "com.vericlaw",
        "WorkingDirectory": "/opt/vericlaw",
        "UserName": "vericlaw",
        "RunAtLoad": True,
        "KeepAlive": False,
        "StandardOutPath": "/var/log/vericlaw.out.log",
        "StandardErrorPath": "/var/log/vericlaw.err.log",
    }
    for key, expected in required_plist.items():
        actual = plist_payload.get(key)
        if actual != expected:
            errors.append(f"Launchd plist has {key}={actual!r}, expected {expected!r}")

    program_arguments = plist_payload.get("ProgramArguments")
    if program_arguments != ["/opt/vericlaw/bin/vericlaw"]:
        errors.append("Launchd plist ProgramArguments must be ['/opt/vericlaw/bin/vericlaw']")

    env_values = plist_payload.get("EnvironmentVariables")
    if not isinstance(env_values, dict):
        errors.append("Launchd plist missing EnvironmentVariables dictionary")
    else:
        expected_env = {
            "GATEWAY_BIND_HOST": "127.0.0.1",
            "ALLOW_PUBLIC_BIND": "false",
            "REQUIRE_PAIRING": "true",
        }
        for key, expected in expected_env.items():
            actual = env_values.get(key)
            if actual != expected:
                errors.append(f"Launchd plist EnvironmentVariables[{key}]={actual!r}, expected {expected!r}")

windows_text = windows_path.read_text(encoding="utf-8")
required_windows = (
    ("strict error handling", r'\$ErrorActionPreference\s*=\s*"Stop"'),
    ("binary existence guard", r'if\s*\(-not\s*\(Test-Path\s+-Path\s+\$BinaryPath\s+-PathType\s+Leaf\)\)'),
    ("duplicate service guard", r'if\s*\(Get-Service\s+-Name\s+\$ServiceName\s+-ErrorAction\s+SilentlyContinue\)'),
    ("service creation command", r'New-Service'),
    ("service display name", r'-DisplayName\s+"VeriClaw"'),
    ("service description", r'-Description\s+"VeriClaw secure runtime service"'),
    ("binary path quoting", r'-BinaryPathName\s+"`"\$BinaryPath`""'),
    ("automatic startup", r'-StartupType\s+Automatic'),
    ("local service credential", r'-Credential\s+"NT AUTHORITY\\LocalService"'),
    ("restart on failure hardening", r'sc\.exe\s+failure\s+\$ServiceName\s+reset=\s*60\s+actions=\s*restart/5000'),
)
for label, pattern in required_windows:
    if re.search(pattern, windows_text, flags=re.MULTILINE) is None:
        errors.append(f"Windows installer missing {label}")

if errors:
    for entry in errors:
        print(entry, file=sys.stderr)
    raise SystemExit(1)
PY

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "${launchd_plist}" >/dev/null
fi

if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -NonInteractive -File - "${windows_installer}" <<'PWSH'
param([string]$Path)
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
  $errors | ForEach-Object { Write-Error $_.Message }
  exit 1
}
PWSH
fi

echo "Service supervisor package checks passed."
