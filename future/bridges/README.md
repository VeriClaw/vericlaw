# future/bridges/

Node.js protocol bridge sidecars, preserved from the original VeriClaw multi-channel architecture.

In v1.0-minimal, VeriClaw uses a bundled Rust companion binary (`vericlaw-signal`) for Signal integration — no Node.js required. These bridges return when their respective channels are re-added.

## Contents

| Directory | Package name | Protocol | Default port | Returns at |
|-----------|-------------|----------|-------------|------------|
| `whatsapp/` | `vericlaw-wa-bridge` | WhatsApp (Baileys) | 3000 | v1.3 |
| `slack/` | `vericlaw-slack-bridge` | Slack Socket Mode | 3001 | v1.1 |
| `discord/` | `vericlaw-discord-bridge` | Discord Gateway | 3002 | v1.1 |
| `email/` | `vericlaw-email-bridge` | IMAP/SMTP | 3003 | v1.1 |
| `irc/` | `irc-bridge` | IRC | 3005 | v1.2 |
| `matrix/` | `matrix-bridge` | Matrix | 3006 | v1.2 |
| `mcp/` | `vericlaw-mcp-bridge` | Model Context Protocol | 3004 | v1.3 |
| `browser/` | `browser-bridge` | Puppeteer (page fetch, screenshot) | 3007 | v1.3 |
| `common/` | shared utilities | Bridge common library | — | (with first bridge) |

## Architecture note

When bridges return, the architecture shifts from the v1.0 model (Rust companion binary, JSON IPC) to a sidecar model: each bridge exposes a local HTTP REST API with `/health` and `/ready` endpoints consumed by the Ada runtime. The `bridge_polling` Ada package in `src/channels/` handles this polling pattern and is already in place for when these return.
