# Channels

[← Back to README](../README.md)

VeriClaw v0.3.0 supports **two channels**: CLI (built-in) and Signal (via `vericlaw-signal` bridge, in preview). Additional channels (Telegram, WhatsApp, Discord, Slack, Email, IRC, Matrix, Mattermost) are in [`future/channels/`](../future/channels/) and return in v1.1.

## Quick Reference

| Channel | Config `kind` | Bridge Required | Status |
|---------|--------------|-----------------|--------|
| CLI | `cli` | No | ✅ Stable |
| Signal | `signal` | Yes (`vericlaw-signal`) | 🔬 Preview |

---

## CLI

Works out of the box — no configuration needed.

```bash
vericlaw chat           # interactive conversation (streaming always-on)
vericlaw agent "..."    # one-shot mode
```

Streaming output is always-on — tokens print as they arrive.

---

## Signal

Requires the `vericlaw-signal` companion binary (built from `vericlaw-signal/`).

> **Note:** Signal integration is in preview in v0.3.0. The `vericlaw-signal` binary builds cleanly (Rust scaffold), but presage device linking is not yet wired to the Ada runtime. Full integration ships in v1.1.

**Config:**
```json
{
  "channels": [
    { "kind": "cli", "enabled": true },
    { "kind": "signal", "enabled": true, "bridge_url": "http://localhost:8080" }
  ]
}
```

**Roadmap:** See [`future/channels/`](../future/channels/README.md) for all channels being added in v1.1 and beyond.

---

## Troubleshooting

- **Channel not working?** Run `vericlaw doctor` to check connectivity.
- **Want a different channel?** Star the repo and watch for v1.1 — the channel backlog is large.
