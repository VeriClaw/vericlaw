# VeriClaw Security Policy

## Threat Model

VeriClaw is deployed as an AI agent accessible over messaging channels. Every inbound message is untrusted. The threat model covers:

| Threat | Description |
|---|---|
| Untrusted user input | Any message arriving over any channel is untrusted |
| Prompt injection | Adversarial payloads in user messages or tool responses attempting to hijack agent behaviour |
| Credential theft | Exfiltration of API keys, auth tokens, or pairing codes |
| Path traversal | `../` or null-byte sequences to escape the workspace boundary |
| API key leakage | Keys appearing in logs, error messages, or audit records |
| Unauthorized access | Requests from unauthenticated or unpaired clients |

---

## Security Controls (v0.3.0)

The following controls are present in the v0.3.0 release. Controls for future versions are listed in the roadmap section of [README.md](README.md) and are not yet implemented.

| Control | Implementation | Verification |
|---|---|---|
| Channel allowlist | Per-channel allowlist; empty = deny all | `security-policy` — SPARK proved (v1.0) |
| Rate limiting | Per-session 1 RPS default; no integer overflow | `channels-security` — SPARK proved (v1.0) |
| Path traversal prevention | `../` and NUL sequences blocked before any file operation | `security-policy` — SPARK proved (v1.0) |
| Workspace isolation | All file operations restricted to `~/.vericlaw/workspace/` | `security-policy` — SPARK proved (v1.0) |
| Secrets at rest | ChaCha20-Poly1305 authenticated encryption; handles zeroed after use | `security-secrets` — SPARK proved (v1.0) |
| Audit log | Append-only log; security decisions cannot be silently dropped | `security-audit` — SPARK proved (v1.0) |
| TLS | libcurl with `SSL_VERIFYPEER=1`, `SSL_VERIFYHOST=2`; TLS 1.2+ enforced | `http-client.adb` |
| Tool allowlist | Config-driven gating; shell tool disabled by default | `agent-tools.adb` |
| Config validation | Input validation on provider URLs, allowlists, and bridge URLs | `config-validation.adb` |

---

## SPARK Verification Scope

### Must-prove for v1.0 (currently proved)

These four packages are proved at **Silver level** (`--level=2`) using GNATprove. Silver level proves absence of all Ada runtime errors: overflow, array index out of bounds, null dereference, division by zero, and invalid enumeration value.

| Package | What is proved |
|---|---|
| `security-policy` | Allowlist decisions are total functions; deny is the default; path-traversal and egress decisions have no runtime errors |
| `security-secrets` | Secret handles are zeroed after use; encrypted-at-rest invariant holds; no buffer overruns in key material handling |
| `security-audit` | Every security decision is logged; audit trail entries cannot be silently dropped; no uninitialized reads |
| `channels-security` | Per-session rate limiting has no integer overflow; allowlist checks and state transitions are monotonic |

### v1.1 targets (not yet proved)

These packages are in scope for SPARK proof in v1.1 but are **not currently proved**. Do not treat them as having verified security properties until v1.1 ships.

| Package | Target invariants |
|---|---|
| `gateway-auth` | Token validation total functions; pairing code state machine; lockout monotonicity |
| `security-secrets-crypto` | No plaintext secret survives past decryption scope |
| `channels-adapters-signal` | Input sanitisation for Signal payloads; no injection via message fields |

---

## How to verify the proofs yourself

```sh
make prove
```

This runs:

```sh
gnatprove -P vericlaw.gpr --level=2 --prover=z3,cvc4,altergo --timeout=60 --report=fail \
  -u security-policy -u security-secrets -u security-audit -u channels-security
```

GNATprove must be installed (part of GNAT Pro or the community edition). A clean run with no `FAILED` lines confirms all four v1.0 packages are proved.

---

## Fail-Closed Defaults

- **Empty allowlist = deny all**: if no users are configured in an allowlist, no user is permitted access.
- **No public bind**: gateway mode binds to `127.0.0.1` by default; public exposure requires explicit config.
- **Shell tool disabled**: the `shell` tool must be explicitly enabled, with allowed commands explicitly listed.
- **Secrets required at startup**: missing required secrets cause a startup failure, not a degraded mode.

---

## Known Limitations

| Limitation | Notes |
|---|---|
| `gateway-auth` not yet proved | Token validation and pairing flow are implemented but not SPARK-verified until v1.1 |
| `security-secrets-crypto` not yet proved | Plaintext-secret scope invariant is a v1.1 target |
| `channels-adapters-signal` not yet proved | Signal input sanitisation is a v1.1 target |
| No certificate pinning | TLS peer verification is enforced but certificates are not pinned to known AI provider keys |
| Tool argument validation is config-based | Allowed tool names and shell commands are config-driven, not proved |
| No fuzz testing harness yet | Input parsing paths have not been fuzz-tested with AFL/libFuzzer |

---

## Security Checklist for Operators

- [ ] API keys and tokens are stored in the encrypted secrets store, not in plaintext config
- [ ] Channel allowlists are populated with known-good user IDs
- [ ] The `shell` tool is disabled unless explicitly required, with a minimal command allowlist
- [ ] `SSL_VERIFYPEER` and `SSL_VERIFYHOST` are not overridden anywhere in the deployment
- [ ] The workspace directory (`~/.vericlaw/workspace/`) has restricted filesystem permissions
- [ ] Audit log output is forwarded to a syslog target for off-host retention
- [ ] `.gitignore` excludes config files containing secrets
- [ ] `make prove` passes cleanly before deploying a custom build

---

## Vulnerability Reporting

**Please do not file public GitHub issues for security vulnerabilities.**

Use GitHub's private security advisory feature instead:

👉 **[Report a Vulnerability](https://github.com/vericlaw/vericlaw/security/advisories/new)**

### Response SLA

| Severity | Acknowledgement | Patch Target |
|----------|----------------|--------------|
| Critical (CVSS ≥ 9.0) | Within 24 hours | Within 7 days |
| High (CVSS 7.0–8.9) | Within 48 hours | Within 14 days |
| Medium / Low | Within 72 hours | Next scheduled release |

We will coordinate disclosure timing with you. We follow [responsible disclosure](https://en.wikipedia.org/wiki/Responsible_disclosure) — please give us a reasonable fix window before publishing.

### Scope

In scope: VeriClaw Ada runtime, `vericlaw-signal` Rust binary, the config loader, HTTP client, and all SPARK security packages. Out of scope: third-party LLM providers, Signal protocol itself, user-written shell allowlists.
