# VeriClaw Security Policy

## Threat Model Summary

VeriClaw is deployed as an AI agent accessible over multiple messaging channels. The threat model covers:

| Threat | Description |
|---|---|
| Untrusted user input | Any message arriving over any channel is untrusted |
| Prompt injection | Adversarial payloads in user messages or tool responses attempting to hijack agent behavior |
| Credential theft | Exfiltration of API keys, auth tokens, or pairing codes |
| Path traversal | `../` or null-byte sequences to escape the workspace boundary |
| API key leakage | Keys appearing in logs, error messages, or audit records |
| Unauthorized access | Requests from unauthenticated or unpaired clients |

---

## Security Controls

| Control | Implementation | Verification |
|---|---|---|
| Authentication | Token + pairing flow; lockout after repeated failures | `gateway-auth.ads` — SPARK proved |
| Channel allowlist | Per-channel allowlist; empty = deny all | `channels-security.ads` — SPARK proved |
| Rate limiting | Per-session 1 RPS default (configurable) | `channels-security.ads` — SPARK proved |
| Path traversal prevention | `../` and NUL byte sequences blocked before any file operation | `security-policy.ads` — SPARK proved |
| TLS | libcurl with `SSL_VERIFYPEER=1`, `SSL_VERIFYHOST=2`; TLS 1.2+ enforced | `http-client.adb` |
| Workspace isolation | All file operations restricted to `~/.vericlaw/workspace/` | `security-policy.ads` — SPARK proved |
| Secrets at rest | ChaCha20-Poly1305 authenticated encryption | `security-secrets-crypto.ads` — SPARK proved |
| Audit log | Tamper-evident append-only log + syslog forwarding; sensitive fields redacted | `security-audit.adb` |
| Tool allowlist | Config-driven gating; shell tool disabled by default | `agent-tools.adb` |
| MCP bridge auth | Bearer token required; 100 req/min rate limit; tool allowlist validation; localhost-only | `mcp-bridge.adb` |
| Browser bridge hardening | No `--single-process`; `--disable-extensions`/`--disable-background-networking`; bound to `127.0.0.1`; URL scheme validation (http/https only) | `browser-bridge.adb` |
| Config validation | Input validation on provider URLs, channel bridge URLs, allowlists, and gateway `bind_host`; rejects control characters and `javascript:` URIs | `config-validation.adb` |
| Gateway API security | `/api/chat` and `/api/chat/stream` reject non-`127.0.0.1` clients with 403 | `gateway.adb` |
| Structured logging | JSON-line format with request ID correlation and log level filtering | `logging.adb` |

---

## SPARK Verification Scope

The security core (Layer 1) is formally verified using GNATprove at **Silver level** (`--level=2`):

- **Silver level** proves absence of all Ada runtime errors: overflow, array index out of bounds, null dereference, division by zero, invalid enumeration value.
- **Flow analysis** proves absence of uninitialized reads and information flow violations in all security packages.

Verified packages:

| Package | Proof level | What is proved |
|---|---|---|
| `channels-security` | Silver (level 2) | No runtime errors; allowlist and rate-limit logic |
| `gateway-auth` | Silver (level 2) | No runtime errors; pairing state machine contracts |
| `security-policy` | Silver (level 2) | No runtime errors; path and egress decision functions |
| `security-secrets-crypto` | Silver (level 2) | No runtime errors; encrypt/decrypt contracts |
| `security-audit` | Flow analysis | No uninitialized reads; no information leakage |
| `channels-adapters-*` | Silver (level 2) | No runtime errors; upgraded from flow analysis to Silver for full runtime error proofs |

To re-run proofs locally:

```sh
gnatprove -P vericlaw.gpr --level=2
```

---

## Fail-Closed Defaults

- **Empty allowlist = deny all**: if no users are configured in an allowlist, no user is permitted access.
- **No public bind**: gateway mode binds to `127.0.0.1` by default; public exposure requires explicit config.
- **Shell tool disabled**: the `shell` tool must be explicitly enabled and its allowed commands explicitly listed.
- **Secrets required at startup**: missing required secrets cause a startup failure, not a degraded mode.

---

## Recent Security Hardening

### MCP Bridge Authentication

The MCP (Model Context Protocol) bridge now requires Bearer token authentication on all requests. Additional protections:

- **Rate limiting**: 100 requests per minute per client, enforced before handler dispatch.
- **Tool allowlist validation**: only tools listed in the configured allowlist may be invoked; unrecognized tool names are rejected immediately.
- **Localhost-only binding**: the bridge listener binds to `127.0.0.1`, preventing remote access without an explicit reverse proxy.

### Browser Bridge Hardening

The Chromium-based browser bridge launch flags have been tightened:

- Removed `--single-process` (security-critical renderer isolation was being bypassed).
- Added `--disable-extensions` and `--disable-background-networking` to reduce attack surface.
- Bound the debug port to `127.0.0.1` instead of `0.0.0.0`.
- URL scheme validation rejects anything other than `http://` or `https://` before navigation, preventing `javascript:`, `file:`, and `data:` URI abuse.

### Config Validation

All user-supplied configuration values are now validated at load time:

- **Provider URLs and channel bridge URLs**: must be well-formed URIs with `http` or `https` scheme; `javascript:` URIs and control characters are rejected.
- **Allowlists**: validated for well-formed user identifiers; empty strings and embedded control characters are rejected.
- **Gateway `bind_host`**: must be a valid IPv4/IPv6 address or `localhost`; hostnames that could resolve to public addresses are flagged.

### SPARK Silver Proofs

The `channels-adapters-*` packages have been upgraded from **flow analysis (level 1)** to **Silver (level 2)** verification. This means GNATprove now proves absence of all Ada runtime errors (overflow, index out of bounds, null dereference, division by zero) in the channel adapter layer, not just absence of uninitialized reads.

### Consistent Allowlist Enforcement

All five bridge-polling channels — Discord, Slack, Email, IRC, and Matrix — now use the SPARK-proved `Channels.Security.Allowlist_Allows` function for access control. Previously, some adapters used ad-hoc checks; the allowlist is now the single enforcement point across all channels.

### Gateway API Security

The `/api/chat` and `/api/chat/stream` endpoints now enforce localhost-only access:

- Requests from any source address other than `127.0.0.1` receive a `403 Forbidden` response.
- This complements the existing `bind_host` default and provides defense-in-depth at the handler level.

### Structured Logging

Log output has been migrated from human-readable text to **JSON-line** format:

- Each log entry includes a **request ID** for end-to-end correlation across channels, gateway, and tool calls.
- Log level filtering is configurable at runtime (`VERICLAW_LOG_LEVEL` environment variable).
- Sensitive fields (API keys, tokens) continue to be redacted before serialization.

---

## Vulnerability Reporting

To report a security vulnerability, open a GitHub issue with the title prefix **`[SECURITY]`**. Include a description of the vulnerability, steps to reproduce, and potential impact. Do not include active exploit code in the public issue.

For sensitive disclosures, email the maintainer directly (address in the GitHub profile) before opening a public issue.

---

## Known Limitations

| Limitation | Notes |
|---|---|
| No certificate pinning | TLS peer verification is enforced but certificates are not pinned to known AI provider keys |
| Tool argument validation is config-based | Tool call arguments (e.g. file paths for `file` tool) are validated by `security-policy` (SPARK proved), but allowed tool names and shell commands are config-driven, not proved |
| ~~Structured logging~~ | **Resolved.** JSON-line structured logging with request ID correlation and log level filtering is now implemented |
| No fuzz testing harness yet | Input parsing paths have not been fuzz-tested with AFL/libFuzzer |

---

## Security Checklist for Operators

Before deploying VeriClaw, verify the following:

- [ ] API keys and tokens are stored in the encrypted secrets store, not in plaintext config
- [ ] Channel allowlists are populated with known-good user IDs
- [ ] The `shell` tool is disabled unless explicitly required, with a minimal command allowlist
- [ ] `SSL_VERIFYPEER` and `SSL_VERIFYHOST` are not overridden anywhere in the deployment
- [ ] The workspace directory (`~/.vericlaw/workspace/`) has restricted filesystem permissions
- [ ] Audit log output is forwarded to a syslog target for off-host retention
- [ ] The Prometheus `/metrics` endpoint is not exposed to the public internet
- [ ] `make check` and `gnatprove -P vericlaw.gpr --level=2` pass cleanly before deploying a custom build
- [ ] `.gitignore` excludes config files containing secrets
- [ ] MCP bridge Bearer token is set and not a default/example value
- [ ] Browser bridge is not launched with `--single-process` or `--remote-debugging-port` on `0.0.0.0`
- [ ] Structured logging is directed to a log aggregator that supports JSON-line ingestion
- [ ] All five channel adapters reference the shared `Channels.Security.Allowlist_Allows` function
