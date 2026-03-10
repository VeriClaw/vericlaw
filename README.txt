VeriClaw v0.3.0
The only AI agent runtime with formally verified security.
Runs on a Pi. Talks over Signal.

─────────────────────────────────────────────────────────────────
Quick start (3 steps)
─────────────────────────────────────────────────────────────────

1. Add the binaries in this archive to your PATH:

   Linux/macOS:
     mkdir -p ~/.vericlaw/bin
     cp vericlaw vericlaw-signal ~/.vericlaw/bin/
     echo 'export PATH="$HOME/.vericlaw/bin:$PATH"' >> ~/.bashrc  # or ~/.zshrc
     source ~/.bashrc

2. Run the guided setup wizard:

     vericlaw onboard

   This will walk you through:
     [1/6] AI provider (Anthropic or OpenAI-compatible)
     [2/6] Signal phone number
     [3/6] Signal device pairing (QR code in terminal)
     [4/6] Workspace directory
     [5/6] System health check
     [6/6] Done

3. Start VeriClaw:

     vericlaw chat           # CLI + Signal
     vericlaw chat --local   # CLI only

─────────────────────────────────────────────────────────────────
Archive contents
─────────────────────────────────────────────────────────────────

  vericlaw          Ada binary — the main VeriClaw agent (~5 MB, statically linked)
  vericlaw-signal   Rust binary — Signal bridge companion (~8 MB, statically linked)
  README.txt        This file

Both binaries are statically linked. No runtime dependencies beyond libc.

─────────────────────────────────────────────────────────────────
Documentation
─────────────────────────────────────────────────────────────────

  Getting started:   https://github.com/vericlaw/vericlaw/blob/main/docs/getting-started.md
  Providers:         https://github.com/vericlaw/vericlaw/blob/main/docs/providers.md
  Pi deployment:     https://github.com/vericlaw/vericlaw/blob/main/docs/pi-deployment.md
  Troubleshooting:   https://github.com/vericlaw/vericlaw/blob/main/docs/troubleshooting.md
  Security proofs:   https://github.com/vericlaw/vericlaw/blob/main/docs/security-proofs.md

─────────────────────────────────────────────────────────────────
License: MIT — https://github.com/vericlaw/vericlaw/blob/main/LICENSE
─────────────────────────────────────────────────────────────────
