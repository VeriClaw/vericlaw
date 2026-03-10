# future/packaging/

Package manager distribution configurations — not needed until VeriClaw has a stable release cadence and user base to justify the maintenance overhead.

## Contents

| Directory | Package manager | Platform | Returns at |
|-----------|----------------|----------|------------|
| `homebrew/` | Homebrew | macOS / Linux | v1.2 |
| `scoop/` | Scoop | Windows | v1.2 |
| `winget/` | Winget | Windows | v1.2 |
| `apt/` | APT/DEB (via nfpm) | Debian / Ubuntu | v1.2 |

## v1.0-minimal install method

```bash
curl -fsSL https://vericlaw.dev/install.sh | sh
```

The install script handles OS/arch detection, binary download, checksum verification, and PATH setup. It's simpler to maintain than four package manager formulas and works on all v1.0-minimal targets.

Package manager distribution returns in v1.2 once the release process is stable and the install script has been validated across all platforms.
