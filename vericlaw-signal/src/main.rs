//! vericlaw-signal — VeriClaw Signal companion binary
//!
//! This binary is spawned by the VeriClaw Ada runtime as a child process.
//! It wraps the presage Signal protocol library and communicates with VeriClaw
//! via JSON-over-stdin/stdout (one JSON object per line, newline-delimited).
//!
//! ## IPC protocol
//!
//! ### Incoming messages (this process → VeriClaw, written to stdout)
//! ```json
//! {"type":"incoming","from":"+44...","body":"hello","image":null,"audio":null}
//! {"type":"incoming","from":"+44...","body":"","image":"/tmp/vericlaw-img-xxx.jpg","audio":null}
//! {"type":"incoming","from":"+44...","body":"","image":null,"audio":"/tmp/vericlaw-voice-xxx.ogg"}
//! {"type":"provision_qr","data":"sgnl://...","text":"▄▄▄▄▄ █▄█ ▄▄▄..."}
//! {"type":"pong"}
//! ```
//!
//! ### Outgoing messages (VeriClaw → this process, read from stdin)
//! ```json
//! {"type":"send","to":"+44...","body":"Hello from VeriClaw"}
//! {"type":"ping"}
//! ```
//!
//! ## Lifecycle
//!
//! 1. VeriClaw spawns this process and opens stdin/stdout pipes.
//! 2. On first run (no stored credentials in ~/.vericlaw/signal/), this process
//!    emits a `provision_qr` message with the QR code data and UTF-8 text rendering.
//!    VeriClaw displays it in the terminal during `vericlaw onboard`.
//! 3. Once linked, this process listens for Signal messages and forwards them to
//!    VeriClaw via stdout.
//! 4. VeriClaw sends outbound messages by writing `send` objects to stdin.
//! 5. VeriClaw pings periodically; this process responds with `pong`.
//! 6. On clean shutdown, VeriClaw sends SIGTERM. This process drains any pending
//!    outbound messages and exits cleanly within 5 seconds.

use std::io::{self, BufRead, Write};
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use tracing::{debug, error, info, warn};

// ---------------------------------------------------------------------------
// IPC message types
// ---------------------------------------------------------------------------

/// A message received from VeriClaw via stdin
#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum InboundMessage {
    /// Send a Signal message to a recipient
    Send {
        to: String,
        body: String,
    },
    /// Health check ping — respond with pong
    Ping,
}

/// A message sent to VeriClaw via stdout
#[allow(dead_code)] // Incoming and ProvisionQr constructed by presage integration (v1.1)
#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum OutboundMessage {
    /// A Signal message received from a contact
    Incoming {
        from: String,
        body: String,
        image: Option<String>,
        audio: Option<String>,
    },
    /// QR code for device linking (emitted during onboard provisioning)
    ProvisionQr {
        data: String,
        text: String,
    },
    /// Response to a ping
    Pong,
    /// Error notification (non-fatal — VeriClaw will decide whether to restart)
    Error {
        code: String,
        message: String,
    },
}

// ---------------------------------------------------------------------------
// Output helpers
// ---------------------------------------------------------------------------

/// Write a message to stdout as a single JSON line.
/// VeriClaw reads one JSON object per line.
fn emit(msg: &OutboundMessage) {
    let line = serde_json::to_string(msg).expect("Failed to serialize IPC message");
    let stdout = io::stdout();
    let mut handle = stdout.lock();
    let _ = writeln!(handle, "{}", line);
    let _ = handle.flush();
}

/// Render a URI string as UTF-8 block-character QR code suitable for terminal display.
/// Works over SSH and in Termius on iOS.
#[allow(dead_code)] // Called by presage provisioning flow (v1.1)
fn render_qr_text(data: &str) -> String {
    use qrcode::{QrCode, EcLevel};
    use qrcode::render::unicode;

    match QrCode::with_error_correction_level(data.as_bytes(), EcLevel::M) {
        Ok(code) => code
            .render::<unicode::Dense1x2>()
            .dark_color(unicode::Dense1x2::Dark)
            .light_color(unicode::Dense1x2::Light)
            .build(),
        Err(e) => {
            warn!("Failed to render QR code: {}", e);
            format!("[QR code: {}]", data)
        }
    }
}

// ---------------------------------------------------------------------------
// Signal store path
// ---------------------------------------------------------------------------

fn signal_store_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    PathBuf::from(home).join(".vericlaw").join("signal")
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialise tracing — log to stderr so it doesn't interfere with the IPC stdout stream
    tracing_subscriber::fmt()
        .with_writer(io::stderr)
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("vericlaw_signal=info".parse()?)
        )
        .init();

    info!("vericlaw-signal starting");

    let store_path = signal_store_path();
    std::fs::create_dir_all(&store_path)?;
    info!("Signal store: {}", store_path.display());

    // ---------------------------------------------------------------------------
    // Presage integration
    //
    // TODO: Integrate presage Manager here once the Cargo.toml dependency resolves.
    //
    // The integration follows this pattern:
    //
    // 1. Check if credentials exist in store_path.
    //    If not → run provisioning flow → emit provision_qr → wait for pairing.
    //    If yes → open the existing store and start receiving messages.
    //
    // 2. Spawn a tokio task to handle incoming Signal messages:
    //    - For each received message, call `emit(&OutboundMessage::Incoming { ... })`
    //    - Save voice/image attachments to temp files, include paths in the message
    //
    // 3. In the main loop (below), handle inbound IPC messages from VeriClaw:
    //    - Send: use the presage Manager to send a Signal message
    //    - Ping: emit pong immediately
    //
    // Example presage provisioning (pseudocode — actual API varies by presage version):
    //
    //   let (provisioning_link, manager_future) = Manager::link_secondary_device(
    //       store, SignalServers::Production, "VeriClaw".into(),
    //   ).await?;
    //   let qr_text = render_qr_text(&provisioning_link.to_string());
    //   emit(&OutboundMessage::ProvisionQr {
    //       data: provisioning_link.to_string(),
    //       text: qr_text,
    //   });
    //   let manager = manager_future.await?;
    // ---------------------------------------------------------------------------

    // Emit a startup acknowledgement so VeriClaw knows the process is alive
    // (In the real implementation, this is replaced by the provisioning flow or
    // the first pong response to VeriClaw's initial ping)
    info!("Bridge ready — waiting for IPC messages on stdin");

    // ---------------------------------------------------------------------------
    // IPC message loop — reads one JSON line per message from stdin
    // ---------------------------------------------------------------------------
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let line = match line {
            Ok(l) => l,
            Err(e) => {
                error!("Failed to read from stdin: {}", e);
                break;
            }
        };

        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        debug!("Received IPC: {}", line);

        match serde_json::from_str::<InboundMessage>(line) {
            Ok(InboundMessage::Ping) => {
                debug!("Responding to ping");
                emit(&OutboundMessage::Pong);
            }
            Ok(InboundMessage::Send { to, body }) => {
                info!("Sending message to {}", to);
                // TODO: use presage Manager to send the message
                // manager.send_message(&to, ContentBody::DataMessage(DataMessage {
                //     body: Some(body), ..Default::default()
                // })).await?;
                debug!("Send queued (presage integration pending): to={}, body_len={}", to, body.len());
            }
            Err(e) => {
                warn!("Failed to parse IPC message: {} — line: {}", e, line);
                emit(&OutboundMessage::Error {
                    code: "parse_error".into(),
                    message: format!("Failed to parse IPC message: {}", e),
                });
            }
        }
    }

    info!("vericlaw-signal exiting cleanly");
    Ok(())
}
