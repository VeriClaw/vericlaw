param(
  [string]$ServiceName = "QuasarClaw",
  [string]$BinaryPath = "C:\quasar-claw\quasar-claw.exe"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $BinaryPath -PathType Leaf)) {
  throw "Binary not found at '$BinaryPath'."
}

if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
  throw "Service '$ServiceName' already exists."
}

New-Service `
  -Name $ServiceName `
  -DisplayName "Quasar Claw Lab" `
  -Description "Quasar Claw Lab secure runtime service" `
  -BinaryPathName "`"$BinaryPath`"" `
  -StartupType Automatic `
  -Credential "NT AUTHORITY\LocalService"

sc.exe failure $ServiceName reset= 60 actions= restart/5000 | Out-Null
Write-Host "Installed service '$ServiceName' for '$BinaryPath'."
