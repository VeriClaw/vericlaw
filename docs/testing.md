# Testing & CI Guide

[← Back to README](../README.md)

---

## Quick Test Commands

```bash
make validate         # full build + proof + tests (preferred)
make runtime-tests    # all 4 runtime test suites
make fuzz-suite       # security boundary fuzz
```

---

## SPARK Security Policy Tests

These tests exercise the formally verified SPARK security core — secrets
management, channel allowlists, adapter policy, and cryptographic routines.

```bash
make secrets-test        # crypto + secret store policy (SPARK)
make conformance-suite   # channel allowlist + adapter policy (SPARK)
make validate            # full build + proof + tests (preferred)
make check               # alias for make validate
```

`make validate` (or its alias `make check`) is the single blessed entrypoint:
it builds the binary, runs GNATprove Silver proofs, then executes every test
suite. Prefer it over running individual targets unless you are iterating on a
specific module.

---

## Runtime Unit Tests

The agent runtime is covered by four focused test suites. Run them all at once
with `make runtime-tests`, or individually:

| Target | Command | What It Covers |
|--------|---------|----------------|
| Config | `make config-test` | Config JSON parsing + schema defaults |
| Context | `make context-test` | Conversation context add / evict / format |
| Memory | `make memory-test` | SQLite memory save / retrieve / FTS5 search |
| Tools | `make tools-test` | Tool schema builder + dispatch gating |

> [!NOTE]
> `memory-test` requires `gnatcoll_sqlite`. It is skipped gracefully in the
> Docker dev image (`vericlaw-dev`) which uses GNAT Community 2021 without that
> component. The SQLite memory backend is fully functional in the main binary —
> only the isolated test suite requires it.
> To run `memory-test`, install `gnatcoll_sqlite` via Alire:
> ```bash
> alr with gnatcoll_sqlite
> ```

---

## Security Regression Fuzz Suite

```bash
make fuzz-suite    # boundary-value + combinatorial fuzz of all SPARK policy modules
```

Covers: channel security, gateway auth, provider routing, credential scoping,
runtime admission, audit retention, and config migration — exercising every
boundary in the SPARK-verified decision functions.

---

## Build Profiles

| Profile | Command | Optimizations | Use Case |
|---------|---------|---------------|----------|
| dev | `make build` | Full SPARK assertions (`-gnata`) | Development |
| release | `make validate` | Build + proofs + tests | CI / release gate |
| small | `make small-build` | `-Os`, `gc-sections` | Size-optimized |
| edge-size | `make edge-size-build` | Minimal binder (~400–600 KB) | Smallest binary |
| edge-speed | `make edge-speed-build` | `-O2` (~6.84 MB) | Speed-optimized |

> There is no separate `make release-build`; `make validate` is the release
> entrypoint because it includes proofs and tests in addition to building.

---

## CI / Release Quick Start

Follow these five steps in order for a full release-candidate pipeline:

### 1. Validate toolchain

```bash
make toolchain-status
make bootstrap-validate
make bootstrap             # only if validation fails
```

### 2. Run core quality checks

```bash
make validate
make secrets-test
make conformance-suite
```

### 3. Run competitive benchmarks

```bash
make competitive-regression-gate
```

### 4. Secure local deployment

```bash
make docker-runtime-bundle-check
docker compose -f docker-compose.secure.yml up --build
```

### 5. Operator console (local)

```bash
make operator-console-check
make operator-console-serve
```

---

## Gate Commands and Report Artifacts

Every CI gate command and its corresponding report artifact:

| Category | Command | Report Artifact |
|----------|---------|-----------------|
| Build + proof | `make validate` (`make check` alias) | — |
| Security tests | `make secrets-test` | — |
| Runtime tests | `make runtime-tests` | — |
| Conformance | `make conformance-suite` | `tests/cross_repo_conformance_report.json` |
| Benchmarks | `make competitive-regression-gate` | `tests/competitive_regression_gate_report.json` |
| Vuln scan | `make vulnerability-license-gate` | `tests/vulnerability_license_gate_report.json` |
| Smoke test | `make cross-platform-smoke` | `tests/cross_platform_smoke_report.json` |
| Supply chain | `make supply-chain-verify` | `tests/supply_chain_verification_report.json` |
| Full RC gate | `make release-candidate-gate` | `tests/release_candidate_report.json` |
| V2 readiness | `make competitive-v2-release-readiness-gate` | `tests/competitive_v2_release_readiness_gate_report.json` |

---

## Running GNATprove

GNATprove performs Silver-level formal verification (absence of runtime errors)
on all security core modules using Z3, CVC4, and Alt-Ergo at `--level=2`.

```bash
make validate                              # build + proofs + tests (auto host/container)
make prove-host                            # explicit Silver proof on a local toolchain
VALIDATION_BACKEND=container make validate # force Docker-based validation
```

| Option | Effect |
|--------|--------|
| `make validate` | Auto-detects whether to use a local or containerized toolchain |
| `make prove-host` | Runs GNATprove directly against the host GNAT installation |
| `VALIDATION_BACKEND=container` | Forces the Docker dev image for reproducible CI runs |

Modules covered by Silver proofs: auth, channel allowlist + rate limit, secrets,
workspace isolation, and path-traversal blocking.
