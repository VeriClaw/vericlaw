PROJECT := quasar_claw.gpr
TOOLCHAIN_CHECK := ./scripts/check_toolchain.sh
BOOTSTRAP := ./scripts/bootstrap_toolchain.sh
CONTAINER_RUNNER := ./scripts/run_container_ci.sh
SMALL_METRICS := ./scripts/measure_small_infra.sh
RELEASE_CHECK := ./scripts/release_check.sh
COMPETITIVE_BENCH := ./scripts/run_competitive_benchmarks.sh
COMPETITIVE_MULTIARCH_BENCH := ./scripts/run_competitive_multiarch_benchmarks.sh
DIRECT_COMPETITIVE_HARNESS := ./scripts/run_direct_competitor_harness.sh
CONFORMANCE_RUNNER := ./scripts/run_cross_repo_conformance_suite.sh
SMOKE_RUNNER := ./scripts/run_cross_platform_smoke_suite.sh
ATTESTATION := ./scripts/generate_attestation_artifacts.sh
SUPPLY_CHAIN_VERIFY := ./scripts/verify_supply_chain_artifacts.sh
COMPETITIVE_BASELINE_CHECK := ./scripts/check_competitive_baseline.sh
RC_GATE := ./scripts/release_candidate_gate.sh
COMPETITIVE_V2_READINESS_GATE := ./scripts/competitive_v2_release_readiness_gate.sh
DOCKER_BUNDLE_CHECK := ./scripts/check_docker_runtime_bundle.sh
SERVICE_SUPERVISOR_CHECK := ./scripts/check_service_supervisors.sh
AUDIT_LOG_CHECK := ./scripts/check_audit_event_log.sh
VULNERABILITY_LICENSE_GATE := ./scripts/vulnerability_license_gate.sh
DOCKERFILE_RELEASE ?= Dockerfile.release
IMAGE_NAME ?= quasar-claw-lab
IMAGE_TAG ?= latest
IMAGE_PLATFORMS ?= linux/amd64,linux/arm64,linux/arm/v7
PUSH_IMAGE ?= false
LOAD_IMAGE ?= false
BUILDX_BUILDER ?=
ATTEST_PROVENANCE ?= true
ATTEST_SBOM ?= true
SIGN_IMAGE ?= false
SIGNING_TOOL ?= cosign
BUILD_METADATA_PATH ?= tests/multiarch_build_metadata.json
TRUST_METADATA_PATH ?= tests/multiarch_trust_metadata.json
COSIGN_KEY ?=
COSIGN_EXTRA_ARGS ?=
EDGE_SIZE_BINDER_MODE ?= minimal
EDGE_SPEED_BINDER_MODE ?= portable

.PHONY: build prove check small-build edge-size-build edge-speed-build measure-small measure-edge-size measure-edge-speed secrets-test conformance-suite cross-platform-smoke release-check competitive-bench competitive-bench-multiarch competitive-direct-harness competitive-baseline-check competitive-regression-gate supply-chain-attest supply-chain-verify vulnerability-license-gate release-candidate-gate competitive-v2-release-readiness-gate bootstrap bootstrap-validate container-build container-prove container-check container-measure-small container-secrets-test container-conformance-suite image-build-local image-build-multiarch docker-runtime-bundle-check service-supervisor-check audit-log-check operator-console-check operator-console-serve gateway-doctor-check

build:
	$(TOOLCHAIN_CHECK)
	gprbuild -P $(PROJECT)

prove:
	$(TOOLCHAIN_CHECK)
	gnatprove -P $(PROJECT) --mode=flow --level=1

check:
	$(TOOLCHAIN_CHECK)
	gprbuild -P $(PROJECT)
	gnatprove -P $(PROJECT) --mode=flow --level=1
	$(AUDIT_LOG_CHECK)
	$(SERVICE_SUPERVISOR_CHECK)

small-build:
	$(TOOLCHAIN_CHECK)
	gprbuild -P $(PROJECT) -XBUILD_PROFILE=small

edge-size-build:
	$(TOOLCHAIN_CHECK)
	gprbuild -P $(PROJECT) -XBUILD_PROFILE=edge-size -XBINDER_MODE=$(EDGE_SIZE_BINDER_MODE)

edge-speed-build:
	$(TOOLCHAIN_CHECK)
	gprbuild -P $(PROJECT) -XBUILD_PROFILE=edge-speed -XBINDER_MODE=$(EDGE_SPEED_BINDER_MODE)

measure-small:
	$(SMALL_METRICS)

measure-edge-size:
	$(SMALL_METRICS) --profile edge-size --binder-mode $(EDGE_SIZE_BINDER_MODE)

measure-edge-speed:
	$(SMALL_METRICS) --profile edge-speed --binder-mode $(EDGE_SPEED_BINDER_MODE)

secrets-test:
	$(TOOLCHAIN_CHECK)
	gprbuild -P tests/security_secrets_tests.gpr
	./tests/security_secrets_tests
	$(AUDIT_LOG_CHECK)

conformance-suite:
	$(CONFORMANCE_RUNNER)

cross-platform-smoke:
	$(SMOKE_RUNNER)

release-check:
	$(RELEASE_CHECK)

competitive-bench:
	$(COMPETITIVE_BENCH)

competitive-bench-multiarch:
	$(COMPETITIVE_MULTIARCH_BENCH)

competitive-direct-harness:
	$(DIRECT_COMPETITIVE_HARNESS)

competitive-baseline-check:
	$(COMPETITIVE_BASELINE_CHECK)

competitive-regression-gate:
	$(COMPETITIVE_BENCH)
	$(DIRECT_COMPETITIVE_HARNESS) --quasar-report tests/competitive_benchmark_report.json
	$(COMPETITIVE_BASELINE_CHECK) --report tests/competitive_benchmark_report.json --direct-report tests/competitive_direct_benchmark_report.json

supply-chain-attest:
	$(ATTESTATION)

supply-chain-verify:
	$(SUPPLY_CHAIN_VERIFY)

vulnerability-license-gate:
	$(VULNERABILITY_LICENSE_GATE)

release-candidate-gate:
	$(RC_GATE)

competitive-v2-release-readiness-gate:
	$(COMPETITIVE_V2_READINESS_GATE)

bootstrap:
	$(BOOTSTRAP)

bootstrap-validate:
	$(BOOTSTRAP) --validate

container-build:
	$(CONTAINER_RUNNER) build

container-prove:
	$(CONTAINER_RUNNER) prove

container-check:
	$(CONTAINER_RUNNER) check

container-measure-small:
	$(CONTAINER_RUNNER) measure-small

container-secrets-test:
	$(CONTAINER_RUNNER) secrets-test

container-conformance-suite:
	$(CONTAINER_RUNNER) conformance-suite

image-build-local:
	@command -v docker >/dev/null 2>&1 || { echo "Docker CLI not found. Install Docker and retry."; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "Docker daemon is unavailable. Start Docker and retry."; exit 1; }
	docker build --file "$(DOCKERFILE_RELEASE)" --tag "$(IMAGE_NAME):$(IMAGE_TAG)" .

image-build-multiarch:
	IMAGE_NAME="$(IMAGE_NAME)" IMAGE_TAG="$(IMAGE_TAG)" IMAGE_PLATFORMS="$(IMAGE_PLATFORMS)" DOCKERFILE_PATH="$(DOCKERFILE_RELEASE)" PUSH_IMAGE="$(PUSH_IMAGE)" LOAD_IMAGE="$(LOAD_IMAGE)" BUILDX_BUILDER="$(BUILDX_BUILDER)" ATTEST_PROVENANCE="$(ATTEST_PROVENANCE)" ATTEST_SBOM="$(ATTEST_SBOM)" SIGN_IMAGE="$(SIGN_IMAGE)" SIGNING_TOOL="$(SIGNING_TOOL)" BUILD_METADATA_PATH="$(BUILD_METADATA_PATH)" TRUST_METADATA_PATH="$(TRUST_METADATA_PATH)" COSIGN_KEY="$(COSIGN_KEY)" COSIGN_EXTRA_ARGS="$(COSIGN_EXTRA_ARGS)" ./scripts/build_multiarch_image.sh

docker-runtime-bundle-check:
	$(DOCKER_BUNDLE_CHECK)

service-supervisor-check:
	$(SERVICE_SUPERVISOR_CHECK)

audit-log-check:
	$(AUDIT_LOG_CHECK)

operator-console-check:
	./scripts/check_operator_console.sh

operator-console-serve:
	./scripts/serve_operator_console.sh

gateway-doctor-check:
	./scripts/check_gateway_doctor.sh
