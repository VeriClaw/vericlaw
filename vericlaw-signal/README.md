# vericlaw-signal

Signal companion binary for VeriClaw. Manages Signal device pairing, message receive, and message send — bridging the Signal protocol to the Ada runtime via JSON-over-stdin/stdout IPC.

## Status: Build-verified scaffold (v0.3.0)

In v0.3.0, `vericlaw-signal` **compiles cleanly** and the IPC event loop skeleton runs. The [presage](https://github.com/whisperfish/presage) Signal protocol library is not yet wired up — device linking, message receive, and message send are stubs.

Full Signal integration ships in **v1.1**. Track progress at: https://github.com/vericlaw/vericlaw/milestone/2

---

## IPC Protocol

`vericlaw-signal` communicates with the VeriClaw Ada runtime via JSON messages on **stdin** (Ada → Signal) and **stdout** (Signal → Ada). This keeps the protocol language-agnostic and eliminates shared memory or sockets.

### Incoming messages (Signal → Ada, written to stdout)

```json
{"type": "incoming", "from": "+447700900000", "body": "hello", "image": null, "audio": null}
{"type": "linked", "phone": "+447700900000"}
{"type": "error",  "message": "registration expired"}
{"type": "pong"}
```

### Outgoing messages (Ada → Signal, written to stdin)

```json
{"type": "send",        "to": "+447700900000", "body": "Hello from VeriClaw"}
{"type": "ping"}
{"type": "link_qr"}
{"type": "shutdown"}
```

---

## Building

```bash
# Debug build
cargo build --manifest-path vericlaw-signal/Cargo.toml

# Release build (optimised for size)
cargo build --release --manifest-path vericlaw-signal/Cargo.toml
```

Cross-compilation targets are configured in `vericlaw-signal/.cargo/config.toml`:

| Target | Architecture |
|--------|-------------|
| `x86_64-unknown-linux-musl` | Linux x86_64 (static) |
| `aarch64-unknown-linux-musl` | Linux ARM64 / Pi 4 (static) |
| `aarch64-apple-darwin` | macOS Apple Silicon |
| `x86_64-apple-darwin` | macOS Intel |

---

## Why Rust?

`presage` — the only mature Ada/Rust-friendly implementation of the Signal protocol client — is written in Rust. Rewriting it in Ada is not a realistic goal. The thin Rust binary handles only Signal protocol concerns; all agent logic remains in the Ada runtime.

---

## Roadmap

| Milestone | Change |
|-----------|--------|
| v1.1 | Wire presage — device linking, QR pairing, receive loop, send |
| v1.1 | `vericlaw onboard` Signal pairing flow end-to-end |
| v1.2 | Image/audio attachment support |
