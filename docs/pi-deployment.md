[← Back to README](../README.md)

# Raspberry Pi 4 Deployment

VeriClaw runs on a Raspberry Pi 4 as a self-hosted, always-on AI assistant. The aarch64 binary is a single static file with no runtime dependencies. A Pi 4 with any amount of RAM works.

---

## Prerequisites

- Raspberry Pi 4 (any RAM variant — 2 GB is sufficient)
- [Raspberry Pi OS Lite (64-bit)](https://www.raspberrypi.com/software/operating-systems/) — the desktop image works too, but Lite is recommended for a headless deployment
- SSH access to the Pi

---

## Step 1: Get the binary

**Option A — Cross-compile from x86_64 (recommended for development)**

On your development machine, build an aarch64 binary and copy it to the Pi:

```bash
# Install Alire and the cross toolchain (Ubuntu/Debian)
curl -L https://alire.ada.dev/install.sh | bash
sudo apt-get install -y gcc-aarch64-linux-gnu gnat-aarch64-linux-gnu

# Clone and cross-compile
git clone https://github.com/vericlaw/vericlaw
cd vericlaw
alr build -- -XBUILD_PROFILE=release -XBUILD_TARGET=aarch64-linux-gnu

# Copy to Pi
scp bin/vericlaw pi@<pi-ip>:/usr/local/bin/
```

**Option B — Build directly on the Pi** (slower, ~20 min on RPi 4)

```bash
# On the Pi — install Alire first
curl -L https://alire.ada.dev/install.sh | bash

git clone https://github.com/vericlaw/vericlaw
cd vericlaw
alr build -- -XBUILD_PROFILE=release
sudo cp bin/vericlaw /usr/local/bin/
```

> **Pre-built aarch64 binaries** will be available from v1.0 onwards on [GitHub Releases](https://github.com/VeriClaw/vericlaw/releases).

---

## Step 2: Run onboard

```bash
./vericlaw onboard
```

Follow the six-step wizard:

1. Choose a provider and enter your API key (Anthropic recommended)
2. Enter your Signal phone number
3. Scan the QR code with Signal on your phone (**Signal → Settings → Linked Devices → +**)
4. Accept or change the workspace path
5. Wait for the system check to complete
6. Done — VeriClaw is ready

The QR code is rendered as UTF-8 block characters (`▄`, `▀`, `█`) directly in the terminal. This works in Termius on iOS over SSH — see the note below if the QR code does not render correctly.

---

## Step 3: Start chatting

```bash
vericlaw chat
```

Or send a Signal message to yourself — VeriClaw is now listening.

---

## Optional: Install as a systemd service

Run VeriClaw as a system service so it starts automatically on boot and restarts on crash.

```bash
sudo ./vericlaw service install
sudo systemctl enable vericlaw
sudo systemctl start vericlaw
```

Check the service is running:

```bash
sudo systemctl status vericlaw
```

View logs:

```bash
journalctl -u vericlaw -f
```

Stop the service:

```bash
sudo systemctl stop vericlaw
```

When running as a service, do not also run `vericlaw chat` in another terminal — two processes cannot share the SQLite memory database. Use `vericlaw status` to check the running instance.

---

## Check status

```bash
vericlaw doctor
```

Expected output when everything is healthy:

```
VeriClaw v0.3.0 — system check

  Config         ✓  ~/.vericlaw/config.json (valid)
  Provider       ✓  Anthropic — claude-sonnet-4 (responding)
  Signal         ✓  +447700900000 (linked, bridge running)
  Memory         ✓  SQLite — ~/vericlaw-workspace/memory.db
  Workspace      ✓  ~/vericlaw-workspace (writable)
  Security       ✓  SPARK proofs — 4/4 packages verified

All checks passed.
```

If Signal is not responding, run:

```bash
vericlaw onboard --repair-signal
```

---

## Termius on iOS

Termius is a good SSH client for managing your Pi from an iPhone or iPad. The QR code in `vericlaw onboard` renders as UTF-8 block characters and works correctly in Termius with its default font settings.

If the QR code appears garbled in Termius:

1. Ensure your Pi's locale is set to UTF-8 (`export LANG=en_US.UTF-8`)
2. Make your Termius terminal window wider (the QR code needs approximately 30 character columns)
3. Use Termius's default monospace font — some third-party fonts do not include Unicode block characters

See [troubleshooting.md](troubleshooting.md#5-signal-qr-code-not-displaying-correctly-over-ssh) for more detail.

---

## Azure VM as development environment

The Pi is the deployment showcase — it is what you put on a shelf or photograph for a README. For active development and CI, continue using an Azure Ubuntu VM (or any Linux x86_64 machine).

The recommended development workflow:

1. **Develop on an Azure VM** — fast CPU, easy to snapshot, disposable
2. **Build for aarch64 on CI** — cross-compilation from x86_64 to aarch64 is supported
3. **Deploy to Pi** — copy the aarch64 binary, run `vericlaw onboard` once, then leave it running

Use Termius on iOS for SSH access to both the Azure VM and the Pi. The same terminal setup that works for the Pi QR pairing works for general development.

---

## Release archive contents (from v1.0)

When GitHub Releases are published (v1.0+), the `vericlaw-linux-aarch64.tar.gz` archive will contain:

```
vericlaw              — main binary (~5 MB, statically linked)
vericlaw-signal       — Signal bridge (~8 MB, statically linked Rust)
README.txt            — quick-start: run ./vericlaw onboard
```

Total size will be under 15 MB. There are no shared library dependencies, no JVM, no Node.js runtime, no Docker required.
