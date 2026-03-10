# future/ci/

Advanced CI pipeline components not included in the v1.0-minimal pipeline.

v1.0-minimal CI has five steps: build Ada, build Rust, prove (4 SPARK packages), test, lint. Everything else is here.

## Contents

| Component | What it is | Returns at |
|-----------|-----------|------------|
| AFL++ fuzzing workflow | Grammar-guided fuzzing of the config parser, channel message parsers, and security policy inputs | v1.1 |
| CodeQL analysis | Semantic code analysis for security vulnerabilities in Ada/C components | v1.1 |
| Trivy container scanning | Vulnerability scanning of Docker images | v1.2 (when Docker is a real deployment path) |
| Supply-chain verification | SLSA provenance, Sigstore signing, dependency audit | v1.2 |
| Competitive benchmark gates | Performance comparison against ZeroClaw, NullClaw, PicoClaw | v1.2 |
| Full SPARK prove (level 4) | Weekly level-4 proof run (currently level-2 in CI) | v1.1 |
| Package manager publishing | Homebrew, Scoop, APT publish steps in release workflow | v1.2 |
| Conformance suite | BBT behavioral specification tests for the full channel/provider matrix | v1.1 |

## v1.0-minimal CI (in .github/workflows/)

```
build-ada     → alr build (linux-x86_64, linux-aarch64, macos-arm64, macos-x86_64)
build-rust    → cargo build --release in vericlaw-signal/ for all 4 targets
prove         → make prove (4 must-prove SPARK packages, level 2)
test          → make test + cargo test
lint          → -gnatwa -gnatwe + cargo clippy
release       → on tag: archives + SHA256 + GitHub Release
```
