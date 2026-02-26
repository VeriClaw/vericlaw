PROJECT := vericlaw.gpr
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
DOCKERFILE_DEV     ?= Dockerfile.dev
DEV_IMAGE_NAME     ?= vericlaw-dev
IMAGE_NAME ?= vericlaw
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

.PHONY: build prove check small-build edge-size-build edge-speed-build measure-small measure-edge-size measure-edge-speed secrets-test conformance-suite cross-platform-smoke release-check competitive-bench competitive-bench-multiarch competitive-direct-harness competitive-baseline-check competitive-regression-gate ingest-nullclaw ingest-zeroclaw supply-chain-attest supply-chain-verify vulnerability-license-gate release-candidate-gate competitive-v2-release-readiness-gate bootstrap bootstrap-validate container-build container-prove container-check container-measure-small container-secrets-test container-conformance-suite image-build-local image-build-multiarch docker-runtime-bundle-check service-supervisor-check audit-log-check operator-console-check operator-console-serve gateway-doctor-check runtime-tests config-test context-test memory-test tools-test docker-dev-image docker-dev-build docker-dev-shell docker-dev-prove docker-dev-test docker-dev-integration-test

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

config-test:
	$(TOOLCHAIN_CHECK)
	gprbuild -P tests/config_loader_test.gpr
	./tests/config_loader_test

context-test:
	$(TOOLCHAIN_CHECK)
	gprbuild -P tests/agent_context_test.gpr
	./tests/agent_context_test

memory-test:
	$(TOOLCHAIN_CHECK)
	gprbuild -P tests/memory_sqlite_test.gpr
	./tests/memory_sqlite_test

tools-test:
	$(TOOLCHAIN_CHECK)
	gprbuild -P tests/agent_tools_test.gpr
	./tests/agent_tools_test

runtime-tests: config-test context-test memory-test tools-test

conformance-suite:
	$(CONFORMANCE_RUNNER)

cross-platform-smoke:
	$(SMOKE_RUNNER)

release-check:
	$(RELEASE_CHECK)

competitive-bench:
	$(COMPETITIVE_BENCH)

ingest-nullclaw:
	./scripts/ingest_nullclaw_benchmarks.sh

ingest-zeroclaw:
	./scripts/ingest_zeroclaw_benchmarks.sh

competitive-bench-multiarch:
	$(COMPETITIVE_MULTIARCH_BENCH)

competitive-direct-harness:
	$(DIRECT_COMPETITIVE_HARNESS)

competitive-baseline-check:
	$(COMPETITIVE_BASELINE_CHECK)

competitive-regression-gate:
	$(COMPETITIVE_BENCH)
	$(DIRECT_COMPETITIVE_HARNESS) --vericlaw-report tests/competitive_benchmark_report.json
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

# ---------------------------------------------------------------------------
# Docker-based development workflow (Mac-friendly, no local GNAT required)
# ---------------------------------------------------------------------------
# Note: alire/gnat:community-latest is x86_64. On Apple Silicon it runs via
# QEMU emulation -- slower but fully functional for compilation and testing.

## Build the dev image (one-time; ~30s on first run, cached after that).
docker-dev-image:
	@command -v docker >/dev/null 2>&1 || { echo "Docker not found."; exit 1; }
	docker build --platform linux/amd64 \
	  --file "$(DOCKERFILE_DEV)" \
	  --tag "$(DEV_IMAGE_NAME):latest" .

## Compile the full project inside the dev container.
## The source is volume-mounted, so edits are picked up without rebuilding the image.
## On success the binary lands at ./main (x86_64 ELF, runnable inside Docker).
docker-dev-build: docker-dev-image
	docker run --rm --platform linux/amd64 \
	  -v "$(PWD):/workspace" \
	  -w /workspace \
	  "$(DEV_IMAGE_NAME):latest" \
	  gprbuild -P vericlaw.gpr -p -j0

## Interactive shell inside the dev container with source mounted.
## Use this to run gnat, gprbuild, gnatprove manually or inspect errors.
docker-dev-shell: docker-dev-image
	docker run --rm -it --platform linux/amd64 \
	  -v "$(PWD):/workspace" \
	  -w /workspace \
	  "$(DEV_IMAGE_NAME):latest" \
	  bash

## Run gnatprove on the SPARK security core inside the dev container.
docker-dev-prove: docker-dev-image
	docker run --rm --platform linux/amd64 \
	  -v "$(PWD):/workspace" \
	  -w /workspace \
	  "$(DEV_IMAGE_NAME):latest" \
	  gnatprove -P vericlaw.gpr --mode=flow -j0

## Build and smoke-test: vericlaw version + vericlaw doctor.
## Run with: make docker-dev-test
docker-dev-test: docker-dev-build
	@echo "=== vericlaw version ===" && \
	docker run --rm --platform linux/amd64 \
	  -v "$(PWD):/workspace" \
	  -w /workspace \
	  "$(DEV_IMAGE_NAME):latest" \
	  ./vericlaw version
	@echo "=== vericlaw doctor (exit 1 without config is expected) ===" && \
	docker run --rm --platform linux/amd64 \
	  -e HOME=/tmp \
	  -v "$(PWD):/workspace" \
	  -w /workspace \
	  "$(DEV_IMAGE_NAME):latest" \
	  ./vericlaw doctor || true

## End-to-end integration test: spins up a Python mock OpenAI-compat server
## inside the container, writes a config pointing to it, then runs
## `vericlaw agent "hello"` and asserts a non-empty reply.
## Run with: make docker-dev-integration-test
docker-dev-integration-test: docker-dev-build
	@echo "=== vericlaw integration test (mock LLM) ===" && \
	docker run --rm --platform linux/amd64 \
	  -e HOME=/tmp \
	  -v "$(PWD):/workspace" \
	  -w /workspace \
	  "$(DEV_IMAGE_NAME):latest" \
	  bash -c '\
	    python3 scripts/mock_llm_server.py 11434 & \
	    sleep 1 && \
	    mkdir -p /tmp/.vericlaw && \
	    printf '"'"'{"agent_name":"VeriClaw","system_prompt":"You are VeriClaw.","providers":[{"kind":"openai_compatible","base_url":"http://127.0.0.1:11434","api_key":"","model":"mock"}],"channels":[{"kind":"cli","enabled":true}],"tools":{"file":false,"shell":false,"web_fetch":false,"brave_search":false},"memory":{"max_history":5,"facts_enabled":false},"gateway":{"bind_host":"127.0.0.1","bind_port":8787}}'"'"' > /tmp/.vericlaw/config.json && \
	    REPLY=$$(./vericlaw agent hello 2>/dev/null) && \
	    echo "Reply: $$REPLY" && \
	    test -n "$$REPLY" && echo "INTEGRATION TEST PASSED" \
	  '
