# VeriClaw

[![CI](https://github.com/VeriClaw/vericlaw/actions/workflows/ci.yml/badge.svg)](https://github.com/VeriClaw/vericlaw/actions/workflows/ci.yml)
[![Release](https://github.com/VeriClaw/vericlaw/actions/workflows/publish.yml/badge.svg)](https://github.com/VeriClaw/vericlaw/actions/workflows/publish.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Ada/SPARK](https://img.shields.io/badge/Ada%2FSPARK-2022-orange.svg)](https://www.adacore.com/about-spark)

**VeriClaw: the only AI agent runtime with a formally verified security core. Runs on a Pi. Talks over Signal.**

> [!NOTE]
> **VeriClaw is v1.0-minimal and in active development.** The CLI and Signal channel are functional. APIs and config formats may still change. See the [changelog](CHANGELOG.md) for what shipped recently.

VeriClaw is an AI agent runtime written in Ada/SPARK — the only runtime in its class with a formally verified security core. It ships as a single static binary that runs on hardware as modest as a Raspberry Pi 4, and lets you talk to your AI assistant over Signal. The security core (policy enforcement, secret management, audit logging, channel access control) is proved at compile time using the SPARK theorem prover. The agent loop, tool dispatch, and provider routing are not proven — see [docs/security-proofs.md](docs/security-proofs.md) for exactly what is and isn't covered.

## What makes VeriClaw different

VeriClaw's security core is formally verified using SPARK 2022 at Silver level: GNATprove proves the absence of all runtime errors — overflow, buffer overrun, null dereference — in the policy, secrets, audit, and channel-security modules. Allowlist decisions are total functions with deny as the default; that property is not a unit test, it is a mathematical proof. Secret handles are proved to be zeroed after use, and the audit trail is proved to be undroppable. See [SECURITY.md](SECURITY.md) for the full list of proved invariants and instructions for re-running the proofs yourself.

## Quick start

```sh
curl -fsSL https://vericlaw.dev/install.sh | sh
vericlaw onboard
vericlaw chat
```

## Supported providers

Anthropic (Claude) natively, plus any OpenAI-compatible endpoint
(Azure AI Foundry, Google Gemini, Ollama, OpenRouter, Groq, DeepSeek, etc.)

## Deploy on Raspberry Pi 4

VeriClaw ships as a single static binary under 6 MB and runs comfortably within the Pi 4's 1 GB RAM. See [docs/pi-deployment.md](docs/pi-deployment.md) for the full walkthrough: cross-compiling with Alire, systemd service setup, and Signal channel configuration.

## Security

**What is proved (v1.0):** allowlist deny-by-default, secret zeroing after use, encrypted-at-rest invariant, undroppable audit trail, integer-overflow-free rate limiting, and monotonic channel state transitions — all verified by SPARK Silver proofs.

**What is not yet proved:** token validation (`gateway-auth`), plaintext-secret scope (`security-secrets-crypto`), and Signal input sanitisation (`channels-adapters-signal`) — these are v1.1 targets.

See [SECURITY.md](SECURITY.md) for the full threat model, controls table, and instructions for running the proofs yourself (`make prove`).

## Roadmap

- **v1.1** — SPARK proofs for `gateway-auth`, `security-secrets-crypto`, and `channels-adapters-signal`; Telegram channel; improved onboarding
- **v1.2** — WhatsApp channel; MCP client; cron scheduler
- **v1.3** — Multi-provider routing with automatic failover; Prometheus metrics
- **v2.0** — Multi-channel gateway (all channels concurrent); operator web console; REST API

## License

[MIT](LICENSE)
