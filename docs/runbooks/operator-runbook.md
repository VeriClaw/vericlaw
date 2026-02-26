# Quasar Operator Runbook

## Deploy (container-first)
1. Build image:
   - `make image-build-local`
   - or `make image-build-multiarch`
   - for signed production pushes: `PUSH_IMAGE=true SIGN_IMAGE=true COSIGN_KEY=./cosign.key make image-build-multiarch`
   - trust artifacts emitted: `tests/multiarch_build_metadata.json`, `tests/multiarch_trust_metadata.json`
2. Validate runtime hardening:
   - `make docker-runtime-bundle-check`
3. Launch with secure defaults:
   - `docker compose -f docker-compose.secure.yml up --build`

## Verify health
1. Run conformance and release checks:
   - `make conformance-suite`
   - `make release-check`
   - `make competitive-baseline-check` (requires `tests/competitive_direct_benchmark_report.json` and emits `tests/competitive_scorecard_report.json` + `tests/competitive_regression_gate_report.json`)
   - `make competitive-regression-gate` (runs benchmark + direct harness + baseline gate together)
2. Run blocking vulnerability + license policy gate:
   - `IMAGE_REF=quasar-claw-lab:rc-gate make vulnerability-license-gate`
3. Run smoke matrix:
   - `make cross-platform-smoke`
   - for blocking CI/RC enforcement of non-blocking suites: `SMOKE_FAIL_ON_NON_BLOCKING=true make cross-platform-smoke`
4. Verify attestation + trust metadata:
   - `make supply-chain-verify`
5. Open local console:
   - `make operator-console-serve`

## Service packaging
- Linux (systemd): `deploy/systemd/quasar-claw.service`
- macOS (launchd): `deploy/launchd/com.quasar.claw.plist`
- Windows (service installer): `deploy/windows/install-quasar-claw-service.ps1`

## Incident response
1. Run startup guard diagnostics:
   - `./scripts/gateway_doctor.sh doctor`
2. Regenerate release artifacts:
   - `make release-check`
3. Regenerate attestation artifacts:
   - `make supply-chain-attest`
4. Re-verify attestation/trust artifacts:
   - `make supply-chain-verify`
5. Regenerate vulnerability/license gate artifacts:
   - `IMAGE_REF=quasar-claw-lab:rc-gate make vulnerability-license-gate`
6. Re-run RC gate:
   - `make release-candidate-gate`
