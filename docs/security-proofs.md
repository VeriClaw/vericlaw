[← Back to README](../README.md)

# Security Proofs

VeriClaw's security core is written in [SPARK](https://www.adacore.com/about-spark), a formally verifiable subset of Ada. The proofs are not marketing copy — they are machine-checked by the GNATprove tool and run on every commit in CI.

---

## What SPARK Silver level proofs mean

SPARK proofs at **Silver level** prove the **absence of all runtime errors** in the proven code. Specifically, GNATprove verifies that the following cannot occur at runtime:

| Error class | Examples |
|---|---|
| Integer overflow | Counter exceeds `Integer'Last`, arithmetic wraps |
| Array index out of bounds | Reading past the end of a buffer |
| Null dereference | Accessing an uninitialised or null access value |
| Division by zero | Any integer or float division |
| Invalid enumeration values | Representation clauses or unchecked conversions |

If GNATprove certifies a package at Silver level, none of these errors can occur in that package — not in an edge case, not under adversarial input, not ever. This is a mathematical proof, not a test result.

---

## The four must-prove packages

These four packages must pass GNATprove before v1.0-minimal ships. They are VeriClaw's security core.

### `security-policy`

**What it proves:** Allowlist decisions are total functions with no runtime exceptions. The deny-by-default invariant holds for all inputs — any input not explicitly on the allowlist is denied. There is no code path through the policy check that returns `Allow` for an unlisted command.

**Why it matters:** This is the front door. Every tool invocation, every shell command, every file operation passes through the policy check. If the policy check has a runtime error or a gap in its coverage, the entire security model collapses.

### `security-secrets`

**What it proves:** Secret storage handles are always zeroed after use. No secret value can be read without an explicit unlock operation. The encrypted-at-rest invariant holds — secrets are never written to disk in plaintext.

**Why it matters:** API keys are the highest-value target for any attacker with access to the filesystem or a process dump. Proving that secrets are always zeroed after use eliminates the class of bugs where a key lingers in memory longer than necessary.

### `security-audit`

**What it proves:** Every security decision is logged. The audit trail cannot be silently dropped — there is no code path that makes a policy decision without writing an audit record. Redaction of secrets in log output is complete — no secret value appears in the audit log.

**Why it matters:** If the audit trail is unreliable, you cannot reconstruct what happened after an incident. Proving the trail is complete means the absence of an audit record proves the absence of the event.

### `channels-security`

**What it proves:** Per-session rate limiting has no integer overflow. Rate limit state transitions are monotonic — the counter never decreases except on an explicit reset. The allowlist check always runs before message dispatch — there is no code path that dispatches a message without first passing it through `security-policy`.

**Why it matters:** Rate limiting bugs are a classic source of denial-of-service and bypass vulnerabilities. An overflow in the rate limit counter could reset it to zero, allowing an attacker to bypass the limit. Proving monotonicity and overflow-freedom closes this class of bugs.

---

## What the proofs do NOT guarantee

Be precise about scope. The SPARK proofs guarantee the above properties for the four proven packages. They do not guarantee:

- **I/O correctness.** Whether VeriClaw sends the right response to the right person is not in scope for these proofs. The proofs cover the decision-making logic, not the network layer.
- **Logical errors in Ada code above the security core.** The chat loop, memory management, and tool execution are Ada (not SPARK) and are tested but not formally proven.
- **Signal protocol correctness.** The `vericlaw-signal` companion binary is written in Rust. Rust's borrow checker eliminates memory safety bugs, but it does not prove policy correctness. The Signal bridge is a trusted subprocess — it delivers messages to VeriClaw's Ada core, which then applies the proven security policy.
- **Correctness of the LLM's outputs.** What the model says is outside VeriClaw's control and outside the scope of any formal proof.
- **Configuration errors.** If you configure an overly permissive shell allowlist, the proven policy will faithfully enforce that permissive allowlist.

---

## SPARK proofs vs. language-level memory safety

VeriClaw's SPARK proofs and Rust's borrow checker (used by `vericlaw-signal`) are complementary, not competing. They prove different things:

| Guarantee | Rust borrow checker | Zig manual memory | SPARK Silver |
|---|---|---|---|
| No use-after-free | ✓ | ✗ (manual) | ✓ |
| No buffer overflow | ✓ | ✗ (manual) | ✓ |
| No integer overflow | ✗ | ✗ | ✓ |
| No null dereference | ✓ (Option type) | ✗ | ✓ |
| Policy correctness (allowlist always checked) | ✗ | ✗ | ✓ |
| Audit trail completeness | ✗ | ✗ | ✓ |
| Deny-by-default invariant holds | ✗ | ✗ | ✓ |

Rust and Zig prove that the program is memory-safe. SPARK proves that the program implements the *correct policy*. A memory-safe program can still have a bug where it allows a command it should deny, or drops an audit record, or overflows a rate limit counter. SPARK proves these policy-level properties; Rust and Zig do not.

This is VeriClaw's differentiator. Every competitor uses memory-safe languages. None of them can prove that their security policy is correctly implemented.

---

## How to verify the proofs yourself

```bash
git clone https://github.com/vericlaw/vericlaw
cd vericlaw
```

Install GNAT and GNATprove. The recommended method is via [Alire](https://alire.ada.dev):

```bash
# Install Alire (Ada package manager)
curl -fsSL https://alire.ada.dev/install.sh | sh

# Select the GNAT toolchain (includes GNATprove)
alr toolchain --select gnat_native
```

Run the proofs:

```bash
make prove
```

This runs GNATprove on all four must-prove packages and prints a summary.

---

## Reading GNATprove output

### A passing proof

```
security-policy.adb:47:12: info: overflow check proved
security-policy.adb:52:08: info: array index check proved
security-policy.adb:61:03: info: postcondition proved
[...]
Summary:
  0 checks unproved
  47 checks proved
  PASSED
```

Every line starting with `info:` is a discharged proof obligation — GNATprove found a mathematical proof for that check. The summary line shows the totals. A passing run has 0 unproved checks.

### A failing proof

```
security-policy.adb:83:15: medium: overflow check might fail
  reason: value of X + Y may be out of range at line 83
  counterexample: X = 2147483647, Y = 1
[...]
Summary:
  1 check unproved
  46 checks proved
  FAILED
```

A failing run shows `medium:` or `high:` warnings instead of `info:`, includes the reason the check could not be proved, and often includes a concrete counterexample showing the input values that would trigger the failure. The summary line shows unproved checks greater than zero and prints `FAILED`.

A failing proof in a must-prove package is a CI blocker. No PR merges with proof regressions.

---

## Further reading

- [SPARK by Example](https://learn.adacore.com/courses/intro-to-spark/index.html) — free online course
- [AdaCore SPARK documentation](https://docs.adacore.com/live/wave/spark2014/html/spark2014_rm/index.html)
- [VeriClaw SECURITY.md](../SECURITY.md) — which packages are currently proven and current proof status
