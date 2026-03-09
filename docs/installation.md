[← Back to README](../README.md)

# Installation

> [!TIP]
> The fastest path today is **From Source** or **GitHub Releases**. Package manager channels are being set up.

---

## From Source (Recommended)

Building from source gives you the latest code and works on all supported platforms.

```bash
# 1. Install Alire (Ada package manager)
curl -L https://alire.ada.dev/install.sh | bash

# 2. Clone and build
git clone https://github.com/vericlaw/vericlaw
cd vericlaw
alr build -- -XBUILD_PROFILE=release
```

---

## GitHub Releases

Download pre-built binaries for your platform from the
[Releases page](https://github.com/VeriClaw/vericlaw/releases).

Each release includes binaries for Linux (x86_64, aarch64, armv7), macOS
(universal), and Windows (x86_64), plus `.deb` and `.rpm` packages for Linux.

---

## Docker

> [!NOTE]
> GHCR publishing is not yet active. The image names below reflect the planned
> naming scheme. For now, build locally with `Dockerfile.release`.

```bash
# Multi-arch image (linux/amd64, linux/arm64, linux/arm/v7)
docker pull ghcr.io/vericlaw/vericlaw:latest
docker run --rm -it ghcr.io/vericlaw/vericlaw

# Specific version
docker pull ghcr.io/vericlaw/vericlaw:<release-tag>
```

---

## Homebrew (macOS / Linux)

> [!NOTE]
> The tap exists but is not yet a verified public install path. Prefer
> GitHub Releases or building from source for now.

```bash
brew install vericlaw/tap/vericlaw
```

---

## Scoop (Windows)

> [!NOTE]
> Bucket metadata exists but is not yet a verified public install path. Prefer
> GitHub Releases or building from source for now.

```powershell
scoop bucket add vericlaw https://github.com/vericlaw/scoop-vericlaw
scoop install vericlaw
```

---

## APT (Debian/Ubuntu)

> [!NOTE]
> The `apt.vericlaw.dev` repository is coming soon. Use `.deb` assets from
> [GitHub Releases](https://github.com/VeriClaw/vericlaw/releases) for now.

When the repository is live, installation will look like:

```bash
curl -fsSL https://apt.vericlaw.dev/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/vericlaw.gpg
echo "deb [signed-by=/usr/share/keyrings/vericlaw.gpg] https://apt.vericlaw.dev stable main" \
  | sudo tee /etc/apt/sources.list.d/vericlaw.list
sudo apt update && sudo apt install vericlaw
```

---

## Winget (Windows)

> [!NOTE]
> Manifest templates exist but the package is not yet in the public registry.
> Use GitHub Releases in the meantime.

```powershell
winget install VeriClaw.VeriClaw
```

---

## Raspberry Pi

VeriClaw ships native ARM binaries for Raspberry Pi:

| Model | OS | Binary | Install Method |
|-------|-----|--------|---------------|
| RPi 5 / RPi 4 | Raspberry Pi OS (64-bit) | `linux-aarch64` | `.deb`, apt (TBC), Homebrew (TBC) |
| RPi 4 / RPi 3 | Raspberry Pi OS (32-bit) | `linux-armv7` | `.deb`, apt (TBC) |
| RPi 2 | Raspberry Pi OS (32-bit) | `linux-armv7` | `.deb`, apt (TBC) |
| RPi Zero 2 W | Raspberry Pi OS (64-bit) | `linux-aarch64` | `.deb`, apt (TBC) |

Install via `.deb` package:

```bash
# Replace <tag> / <version> with the release you want, e.g. v0.2.0 / 0.2.0

# 64-bit (aarch64)
curl -fsSLO https://github.com/VeriClaw/vericlaw/releases/download/<tag>/vericlaw_<version>_arm64.deb
sudo dpkg -i vericlaw_*.deb

# 32-bit (armv7)
curl -fsSLO https://github.com/VeriClaw/vericlaw/releases/download/<tag>/vericlaw_<version>_armhf.deb
sudo dpkg -i vericlaw_*.deb
```

**Performance notes:**

- **RPi 4 (4 GB+):** Full agent functionality, recommended for production
- **RPi 3 / Zero 2 W:** Agent works but with higher latency on large contexts
- **RPi 2:** CLI commands work; agent mode may be memory-constrained
- VeriClaw uses ~50 MB RAM at idle, ~200 MB under typical agent workload
- Runtime sandbox auto-applies `setrlimit` memory caps appropriate for the platform

---

## Verify Installation

```bash
vericlaw --version       # Print the installed version
vericlaw doctor          # Check runtime dependencies and configuration
vericlaw update-check    # See if a newer release is available
```

---

## Next Steps

Once VeriClaw is installed and verified:

1. **Run the setup wizard** to configure your LLM provider and channel:
   ```bash
   vericlaw onboard
   ```
   The wizard walks you through provider selection, API key entry, and channel
   setup with colored confirmations at each step.

2. **Check your setup** with the built-in doctor:
   ```bash
   vericlaw doctor
   ```
   Shows colored ✓/✗ health checks for config, database, bridges, and security.

3. **Start chatting**:
   ```bash
   vericlaw chat
   ```

> [!TIP]
> See [getting-started.md](getting-started.md) for the full walkthrough with
> examples of what you'll see at each step.

---

## Supported Platforms

| OS | Architecture | Binary | Homebrew | Scoop | DEB | RPM | install.sh |
|----|-------------|--------|----------|-------|-----|-----|------------|
| Linux | x86_64 | ✅ | ⚠️ TBC | — | ✅ | ✅ | 🔜 TBC |
| Linux | aarch64 (ARM64) | ✅ | ⚠️ TBC | — | ✅ | ✅ | 🔜 TBC |
| Linux | armv7 (RPi) | ✅ | — | — | ✅ | ✅ | 🔜 TBC |
| macOS | Apple Silicon | ✅ (universal) | ⚠️ TBC | — | — | — | 🔜 TBC |
| macOS | Intel | ✅ (universal) | ⚠️ TBC | — | — | — | 🔜 TBC |
| Windows | x86_64 | ✅ | — | ⚠️ TBC | — | — | 🔜 TBC |
