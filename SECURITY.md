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
| `channels-adapters-*` | Flow analysis | No uninitialized reads in adapter specs |

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

## Vulnerability Reporting

To report a security vulnerability, open a GitHub issue with the title prefix **`[SECURITY]`**. Include a description of the vulnerability, steps to reproduce, and potential impact. Do not include active exploit code in the public issue.

For sensitive disclosures, email the maintainer directly (address in the GitHub profile) before opening a public issue.

---

## Known Limitations

| Limitation | Notes |
|---|---|
| No certificate pinning | TLS peer verification is enforced but certificates are not pinned to known AI provider keys |
| Tool argument validation is config-based | Tool call arguments (e.g. file paths for `file` tool) are validated by `security-policy` (SPARK proved), but allowed tool names and shell commands are config-driven, not proved |
| Structured logging not yet implemented | Log output is human-readable text; machine-parseable structured logging (Section 9.1 of ada-coding-practices.md) is planned |
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
