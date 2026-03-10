# VeriClaw Deep Dive

This document is a repo-grounded, single-file guide to what VeriClaw is, how it works, how it is built, how it is operated, and how it is written. It is intentionally broader than the README: the goal is to give a new maintainer, operator, evaluator, or contributor one place to understand the whole project.

---

## 1. Executive summary

**VeriClaw is a security-first AI assistant runtime written in Ada/SPARK.**

At a practical level, it is both:

- a **local CLI assistant** you can run from your terminal, and
- a **gateway runtime** that can run across many chat channels at once.

What makes it unusual is not just that it supports multiple providers, tools, channels, and deployment modes. Its main differentiator is that the security-critical core is designed around **SPARK-verified packages**. In other words, the project is explicitly trying to build an AI agent runtime with a stronger correctness and security story than most agent stacks.

The project currently presents itself as:

- **active development** on the `0.2.0` line,
- **edge-friendly**, with a small native binary and modest footprint,
- **multi-provider**, **multi-channel**, and **operations-aware**,
- and strongly focused on **provable security boundaries**, **fail-closed defaults**, and **structured operational behavior**.

If you want the shortest possible summary, it is this:

> VeriClaw is an Ada/SPARK AI runtime that tries to bring real systems engineering discipline to the agent world: formal verification where it matters, explicit trust boundaries, small native deployment artifacts, and enough tooling to be useful in both local and service-style deployments.

---

## 2. Project snapshot

| Topic | Current repo position |
|---|---|
| Name | `vericlaw` |
| Primary language | Ada 2022 |
| Verification model | SPARK for security-critical packages |
| License | MIT |
| Current release line in docs | `0.2.0` |
| Local repo status | Active development / not fully stabilized |
| Runtime modes | CLI chat, one-shot agent, gateway daemon |
| Main differentiator | Formally verified security core |
| Build tooling | Alire + GNAT/GPRbuild + GNATprove |
| Key native dependencies | `gnatcoll`, `aws`, `libcurl`, `libsqlite3` |
| Channel model | Built-in CLI/native channels plus bridge-backed sidecars |
| Operational model | Local app or multi-channel gateway with metrics/logging/API |

Notable practical characteristics surfaced in the repo docs:

- The README positions VeriClaw as a **5.3 MB** binary with a **37.1 MB** container image.
- The docs describe it as **edge-friendly** and suitable for Raspberry Pi-class hardware.
- The security docs emphasize **SPARK Silver proofs** on the core policy surface.
- The installation docs also make it clear that **source builds and GitHub Releases are the most reliable paths today**, while some package-manager channels are still maturing.

---

## 3. What VeriClaw is trying to solve

VeriClaw is not just "a chatbot." It is trying to solve a specific systems problem:

**How do you run a useful AI assistant across real interfaces and tools without giving up too much on security, correctness, and operational control?**

The repo shows several concrete answers to that question.

### 3.1 Security boundary for agent behavior

Instead of assuming the model or tool layer is trustworthy, VeriClaw isolates security decisions into SPARK packages, including:

- authentication,
- allowlists,
- rate limiting,
- workspace/path access rules,
- secret handling,
- audit behavior.

That means the project does not treat security as a thin wrapper around a general-purpose agent loop. It treats it as a first-class subsystem.

### 3.2 One runtime, many interfaces

VeriClaw can present the same assistant through:

- local CLI,
- Telegram,
- Signal,
- WhatsApp,
- Slack,
- Discord,
- Email,
- IRC,
- Matrix,
- Mattermost.

This matters if you want one assistant personality and policy surface but many ways to access it.

### 3.3 Multi-provider resilience

The project does not assume a single model vendor. It supports multiple provider families and an ordered failover chain, which is useful for:

- resilience,
- cost control,
- privacy or locality preferences,
- testing against different model backends.

### 3.4 Real operational behavior

Unlike many toy agent repos, VeriClaw includes:

- a documented HTTP gateway,
- metrics,
- structured logging,
- service packaging,
- hot config reload,
- Docker deployment scaffolding,
- release and CI flows,
- documentation for testing and operations.

This strongly suggests the project is aiming at long-running, operator-managed deployments, not only ad hoc local experiments.

---

## 4. What the project is made of

At the highest level, VeriClaw is a **three-layer system**.

### 4.1 Layer 1: SPARK security core

This is the project’s most important architectural decision.

Security-critical packages are separated into a formally verified layer. The key packages called out in the repo docs are:

- `channels-security`
- `gateway-auth`
- `security-policy`
- `security-secrets` / `security-secrets-crypto`
- `security-audit`
- `channels-adapters-*`

What lives here:

- channel allowlist decisions,
- per-session rate limiting,
- token and pairing decisions,
- workspace/path checks,
- URL/egress checks,
- encrypted secret handling,
- audit/redaction behavior,
- adapter-level contracts for channel-facing logic.

Why this matters:

- It keeps the most sensitive decisions out of ad hoc runtime logic.
- It uses SPARK contracts and proofs rather than trusting manual reasoning alone.
- It gives the rest of the runtime a typed, explicit policy layer to call into.

### 4.2 Layer 2: Ada runtime

This is the main runtime: the part that makes VeriClaw useful.

It handles:

- agent orchestration,
- provider calls,
- tool dispatch,
- memory,
- HTTP server/gateway behavior,
- config loading,
- observability,
- channel coordination,
- CLI UX.

Important subtrees and packages include:

- `src/agent/`
- `src/channels/`
- `src/providers/`
- `src/tools/`
- `src/memory/`
- `src/config/`
- `src/http/`
- `src/observability/`
- `src/terminal/`
- `src/sandbox/`

This layer does the heavy lifting, but the architecture docs make it clear that it is expected to **call into Layer 1 for security decisions rather than bypass them**.

### 4.3 Layer 3: Node.js bridge sidecars

Some external protocols are easiest to support through dedicated sidecars rather than reimplementing every integration natively in Ada.

The repo contains sidecars such as:

- `wa-bridge`
- `slack-bridge`
- `discord-bridge`
- `email-bridge`
- `irc-bridge`
- `matrix-bridge`
- `mcp-bridge`
- `browser-bridge`

These sidecars are intentionally **local protocol adapters**. They expose localhost HTTP endpoints and let the Ada runtime stay focused on core behavior while sidecars handle ecosystem-specific APIs and SDKs.

This is a sensible compromise:

- keep security policy and orchestration in the native runtime,
- use protocol-specific sidecars where that is more practical,
- keep sidecars away from being the source of truth for security policy.

---

## 5. How VeriClaw works at runtime

A typical request flow looks like this:

1. A message arrives from the CLI or a channel.
2. The channel layer routes it into the runtime.
3. The request is checked against security policy:
   - allowlist,
   - rate limiting,
   - auth/pairing,
   - workspace/egress rules where relevant.
4. The agent loop builds the current context:
   - system prompt,
   - session history,
   - compacted history if required,
   - optional memory retrieval.
5. The runtime selects the current provider using configured routing order.
6. The runtime sends the request over TLS to the LLM provider.
7. If the model requests tools, tool calls are parsed and dispatched.
8. Each tool call is checked against policy before execution.
9. Tool results are appended back into the conversation.
10. The loop continues until a final answer is produced.
11. The reply is formatted for the active channel and returned.
12. Memory, logs, metrics, and audit records are updated.

### 5.1 Provider routing

The providers docs describe an ordered model:

- `providers[0]`: primary
- `providers[1]`: dedicated failover
- `providers[2..n]`: long-tail fallback chain

This is a practical design. It avoids hard-coding retries in application logic and gives operators a simple high-level resilience mechanism.

### 5.2 Context and memory

The repo docs describe several layers of state:

- in-memory conversation history,
- SQLite-backed persistent memory,
- FTS5 search,
- optional facts store,
- optional vector memory via `sqlite-vec`,
- deterministic context compaction via `memory.compact_at_pct`.

This means the runtime is designed for more than stateless prompt-in / answer-out behavior.

### 5.3 Parallel execution

When the model emits multiple tool calls, VeriClaw can execute them concurrently using **Ada tasks**. The docs also call out that order-sensitive tools are handled sequentially.

This is one of the more interesting implementation details because it uses Ada’s concurrency model in a way that fits the problem well.

---

## 6. Repository layout and what the major directories do

### 6.1 Top-level repository map

Here is the important shape of the repo as it exists locally:

```text
vericlaw/
├── README.md
├── ARCHITECTURE.md
├── SECURITY.md
├── CONTRIBUTING.md
├── CHANGELOG.md
├── alire.toml
├── vericlaw.gpr
├── spark.adc
├── Makefile
├── Dockerfile.*
├── docker-compose.yml
├── docs/
├── src/
├── tests/
├── deploy/
├── operator-console/
├── config/
├── packaging/
├── scripts/
├── bridge-common/
├── wa-bridge/
├── slack-bridge/
├── discord-bridge/
├── email-bridge/
├── irc-bridge/
├── matrix-bridge/
├── mcp-bridge/
├── browser-bridge/
└── .github/
```

### 6.2 What the important top-level items mean

| Path | Purpose |
|---|---|
| `README.md` | Project entrypoint and high-level feature story |
| `ARCHITECTURE.md` | Layer model, security boundary, request flow |
| `SECURITY.md` | Threat model, controls, operator security checklist |
| `CONTRIBUTING.md` | Contribution workflow and coding rules |
| `docs/` | The real reference corpus: install, providers, channels, tools, ops, testing, API |
| `src/` | Main Ada/SPARK codebase |
| `tests/` | Runtime tests, policy tests, conformance, regression gates |
| `deploy/` | Service definitions and platform-specific deployment artifacts |
| `operator-console/` | Browser-based local console/UI for the gateway |
| `config/` | Sample and example runtime configs |
| `scripts/` | Build, CI, validation, benchmarking, and supply-chain helpers |
| `docker-compose.yml` | Full local stack wiring for bridges and gateway |
| `alire.toml` | Ada package metadata and externals |
| `vericlaw.gpr` | GNAT project definition and build/proof settings |

### 6.3 How the source tree is conceptually organized

The repo follows a disciplined split between concerns:

- **security/policy** concerns are isolated,
- **runtime/orchestration** concerns are centralized,
- **external protocols** are adapted through bridges,
- **docs and ops** are treated as part of the product, not an afterthought.

This is exactly the kind of structure you want in a long-lived systems project.

---

## 7. Technology stack

### 7.1 Core languages and platforms

- **Ada 2022** for the main runtime
- **SPARK** for verification-oriented security packages
- **Node.js** for sidecar bridges and browser/MCP integrations
- **SQLite** for memory/state
- **libcurl** for outbound HTTP/TLS
- **AWS (Ada Web Server)** for HTTP serving

### 7.2 Native Ada dependencies

From `alire.toml`:

- `gnatcoll`
- `aws`

From the runtime/build files:

- `libcurl`
- `libsqlite3`

### 7.3 JavaScript/Node footprint

The repo root `package.json` is intentionally small and only declares `express` at the top level. Most ecosystem-specific behavior lives in dedicated bridge directories and their local dependencies.

### 7.4 Toolchain

- **Alire** for Ada dependency management
- **GNAT/GPRbuild** for compiling
- **GNATprove** for proofs
- **Make** as the main human-friendly command surface
- **Docker / Docker Compose** for deployment and dev environments

---

## 8. Setup and installation

The installation docs are refreshingly honest: **the most reliable paths today are source builds and GitHub Releases**.

### 8.1 Recommended installation path: source build

```bash
curl -L https://alire.ada.dev/install.sh | bash
git clone https://github.com/vericlaw/vericlaw
cd vericlaw
alr build -- -XBUILD_PROFILE=release
```

This is the clearest path if you want the latest repo state.

### 8.2 GitHub Releases

The docs describe release binaries for:

- Linux x86_64
- Linux aarch64
- Linux armv7
- macOS universal
- Windows x86_64

### 8.3 Docker

The repo includes multiple Dockerfiles plus a compose file for the full runtime + sidecar story.

### 8.4 Package manager story

The docs show intent for several channels, but also note that some are still maturing:

- Homebrew: exists conceptually, not the most trusted path yet
- Scoop: same story on Windows
- APT: planned / coming soon in docs
- Winget: templates exist, public registry path not fully realized yet

That matters because it tells you the project is thinking like a distributable product, even if some release channels are still catching up.

### 8.5 Raspberry Pi story

The installation docs explicitly discuss Raspberry Pi models and ARM builds. That reinforces the project’s “native, small, edge-friendly” identity.

---

## 9. Configuration model

A simple example from `config/config.json` in this repo:

```json
{
  "agent_name": "VeriClaw",
  "system_prompt": "You are VeriClaw, a helpful AI assistant.",
  "providers": [{
    "kind": "openai",
    "base_url": "http://host.docker.internal:11434",
    "api_key": "ollama",
    "model": "llama3.2:1b"
  }],
  "channels": [{"kind": "cli", "enabled": true}],
  "tools": {"file": false, "shell": false, "web_fetch": false, "brave_search": false},
  "memory": {"max_history": 10, "facts_enabled": false}
}
```

### 9.1 Configuration precedence

The architecture docs describe this order:

1. `VERICLAW_CONFIG`
2. `~/.vericlaw/config.json`
3. built-in defaults

### 9.2 Important configuration areas

- `agent_name`
- `system_prompt`
- `providers`
- `channels`
- `tools`
- `memory`
- gateway bind information
- bridge URLs / tokens
- allowlists / rate limits

### 9.3 Configuration philosophy

The project leans toward:

- validation at load time,
- explicit errors rather than silent fallback,
- safe defaults,
- rejection of malformed or suspicious values.

The security docs explicitly call out validation of:

- URLs,
- strings,
- allowlist entries,
- gateway bind hosts,
- unsafe URI schemes such as `javascript:`.

---

## 10. Providers

The providers docs define **five provider families**:

- OpenAI
- Anthropic
- Google Gemini
- Azure AI Foundry
- OpenAI-compatible endpoints

### 10.1 Why this is useful

This lets VeriClaw support a wide range of deployment styles:

- first-party cloud APIs,
- OpenAI-shaped hosted APIs,
- local/self-hosted options like Ollama,
- routing and fallback across many endpoints.

### 10.2 OpenAI-compatible aliases

A nice usability touch is the built-in alias/preset model for popular providers such as:

- Groq
- Mistral
- DeepSeek
- xAI
- OpenRouter
- Perplexity
- Together
- Fireworks
- Cerebras

That means onboarding is not just “paste raw endpoints manually.” The runtime includes operator experience work here too.

### 10.3 Streaming model

The docs describe:

- always-on streaming in CLI mode for supported providers,
- SSE-style responses in gateway mode,
- graceful fallback to non-streaming when a provider does not support streaming.

---

## 11. Channels and user-facing surfaces

The repo currently documents **10 channels**:

1. CLI
2. Telegram
3. Signal
4. WhatsApp
5. Slack
6. Discord
7. Email
8. IRC
9. Matrix
10. Mattermost

A small note on repo consistency: `docs/channels.md` and the README clearly position the project around 10 channels, while one overview doc still appears to lag behind in one summary table. The channel docs themselves are the more detailed and current source.

### 11.1 Native vs sidecar-backed channels

- **Native/no sidecar**: CLI, Telegram
- **Bridge-backed**: Signal, WhatsApp, Slack, Discord, Email, IRC, Matrix, Mattermost

### 11.2 Multi-user gateway model

One of the more interesting operational features is **operator vs guest isolation**.

The channel docs describe a shared deployment model where:

- allowlisted users can be treated as operators,
- public users can be treated as guests,
- guest memory is isolated into its own namespace,
- guests do not gain access to operator memory or facts.

That is a thoughtful feature for anyone exposing a single bot more broadly.

### 11.3 Gateway startup model

`vericlaw gateway` starts all enabled channels concurrently, and the docs show the runtime surfacing a boot status panel with model, memory, active channels, and bind URL.

That is exactly the kind of small UX decision that makes service software friendlier to run.

---

## 12. Tools and extensibility

The tools docs position VeriClaw as shipping with a substantial built-in tool surface plus MCP-based extensibility.

### 12.1 Built-in tool categories

The documented surface includes:

- file I/O
- shell execution
- web fetch
- Brave Search
- git operations
- cron scheduling
- spawn
- delegate
- plugin registry inspection
- browser browse
- browser screenshot
- memory search / RAG
- MCP-discovered tools

### 12.2 Important safety choices

The tool docs and security docs make several good design choices explicit:

- file access is workspace-scoped,
- path traversal is blocked,
- shell is disabled by default,
- shell allowlists are explicit,
- tool use is audited,
- browser behavior is sandboxed/hardened,
- private/internal network access is blocked in important paths,
- MCP is localhost-only and bearer-token protected.

### 12.3 Sub-agents and delegation

The repo includes a concept of:

- `spawn` for isolated sub-agent work,
- `delegate` for role-specialized sub-agent work.

This suggests VeriClaw is not only a single-loop assistant but is moving toward structured multi-agent orchestration with depth limits and explicit control.

---

## 13. Memory, state, and RAG

VeriClaw is not stateless. The memory layer is part of the design.

### 13.1 What it stores

The docs mention:

- session history,
- facts,
- searchable memory,
- vector embeddings for semantic recall,
- scheduled jobs,
- operator/guest isolation in shared deployments.

### 13.2 Why SQLite is a good fit here

SQLite plus WAL mode is a strong practical choice for this kind of system because it gives:

- easy single-binary deployment,
- enough concurrency for many lightweight runtime cases,
- persistence without bringing in a whole external database stack,
- good compatibility with local and edge deployment.

### 13.3 Context compaction

The addition of `memory.compact_at_pct` is worth calling out. It shows the runtime is thinking about long-lived sessions and bounded contexts rather than pretending infinite chat history is free.

---

## 14. HTTP API and operator console

When running in gateway mode, VeriClaw exposes:

- `GET /health`
- `GET /metrics`
- `GET /api/status`
- `GET /api/channels`
- `GET /api/plugins`
- `GET /api/metrics/summary`
- `POST /api/chat`
- `POST /api/chat/stream`

### 14.1 Important API characteristics

From the API and operations docs:

- operator endpoints are **localhost-only**,
- responses include security headers,
- `/metrics` is Prometheus-compatible,
- `/api/chat/stream` currently advertises **buffered SSE** behavior,
- structured logs include request IDs for correlation.

### 14.2 Operator console

The `operator-console/` directory is a browser-facing control surface that can:

- connect to the local gateway,
- surface status, channels, metrics, and plugins,
- keep a local session ID and transcript,
- act as a browser UI for the assistant.

This is a useful bridge between CLI-only developer ergonomics and full web product ergonomics.

---

## 15. Command-line interface and user experience

The docs consistently position the CLI as a first-class interface, not just an admin tool.

### 15.1 Core commands

The repo materials mention these key commands:

- `vericlaw onboard`
- `vericlaw doctor`
- `vericlaw config validate`
- `vericlaw config edit`
- `vericlaw reset`
- `vericlaw chat`
- `vericlaw agent "..."`
- `vericlaw gateway`
- `vericlaw channels login --channel <name>`
- `vericlaw status`
- `vericlaw export --session <id>`
- `vericlaw update-check`
- `vericlaw version`

### 15.2 CLI UX details that matter

The project explicitly includes:

- color-coded output,
- `--no-color` and `NO_COLOR` support,
- first-run guidance,
- a styled banner,
- interactive health-check output,
- slash commands in chat mode.

### 15.3 Interactive chat commands

The docs mention:

- `/help`
- `/clear`
- `/memory`
- `/edit N`
- `/exit`

These are the kinds of small affordances that make a local assistant feel like a product rather than a demo.

---

## 16. Supported user journeys

This is one of the easiest ways to understand what the project is really for.

### 16.1 Journey: first-time local user

1. Install from source or download a release.
2. Run `vericlaw onboard`.
3. Pick a provider and model.
4. Start with the `cli` channel.
5. Run `vericlaw doctor`.
6. Use `vericlaw chat`.

This is the most approachable path and clearly supported in the docs.

### 16.2 Journey: local power user with tools

1. Enable selected tools.
2. Keep shell disabled unless needed.
3. Use file/git/web tooling in a workspace-scoped way.
4. Optionally enable browser or RAG support.

This is where VeriClaw starts to feel more like an agent runtime than a plain assistant wrapper.

### 16.3 Journey: multi-channel operator

1. Configure multiple channels.
2. Bring up bridge services with Docker Compose.
3. Run `vericlaw gateway`.
4. Monitor health via `/health`, `/metrics`, and `/api/status`.
5. Adjust config and reload without a full restart.

This is a strong target use case for the project.

### 16.4 Journey: public/shared bot owner

1. Configure allowlists and guest behavior.
2. Expose selected channels.
3. Preserve operator-only memory while sandboxing guests.
4. Use audit logging and metrics for visibility.

This is more advanced than the typical personal-assistant-only model.

### 16.5 Journey: contributor

1. Install the Ada/SPARK toolchain.
2. Build with the project GPR/Alire setup.
3. Run `make validate`.
4. Run targeted tests for touched areas.
5. Add docs for new channels/providers/tools.
6. Respect SPARK boundaries for security-sensitive code.

This is clearly supported by the docs and repo structure.

---

## 17. How the code is written

This project is interesting not just because of what it does, but because of **how it is coded**.

### 17.1 Ada package discipline

The coding-practices doc emphasizes the classic Ada split:

- `.ads` specification files
- `.adb` body files

This encourages:

- clear interfaces,
- tighter modularity,
- more explicit contracts,
- better separation between stable boundaries and implementation detail.

### 17.2 Strong typing

The coding-practices doc strongly recommends:

- constrained types,
- explicit subtypes,
- enumerations over magic strings or numbers,
- minimal unchecked conversions,
- careful ownership and resource behavior.

This matches the overall philosophy of the project very well.

### 17.3 SPARK where it matters, not everywhere for its own sake

The docs are practical rather than dogmatic:

- security-critical logic should be in `SPARK_Mode (On)` packages,
- I/O-heavy code can explicitly be `SPARK_Mode (Off)`,
- formal boundaries should be intentional.

This is a mature approach. It does not try to force proof tooling into places where it would not help much.

### 17.4 Contract-based design

The docs and architecture notes emphasize:

- `Pre` / `Post` conditions,
- typed decision enums,
- discriminated results for expected failures,
- no hidden assumptions about policy outcomes.

This is exactly what you want when a runtime needs to remain understandable under pressure.

### 17.5 Error handling philosophy

A recurring rule across the docs is:

> Do not silently swallow failures.

The contributing and coding docs explicitly discourage patterns like:

- `when others => null`

Instead, the guidance is to:

- re-raise,
- log with context,
- increment metrics,
- return explicit result records for expected failures.

### 17.6 Resource management

The project guidance encourages `Ada.Finalization.Controlled` for RAII-style cleanup of files, sockets, and database handles.

That matters because long-running assistant runtimes can die by resource leaks just as easily as by logic bugs.

### 17.7 Concurrency model

The architecture docs describe:

- **Ada tasks** for concurrent runtime work,
- **protected objects** for shared safe state,
- WAL-backed SQLite for concurrent access patterns.

This is one of the most distinctive parts of the implementation style.

---

## 18. Best practices the project follows

If you want the project’s engineering worldview in one section, this is it.

### 18.1 Security best practices

The repo strongly demonstrates:

- fail-closed defaults,
- explicit allowlists,
- localhost-only operator APIs,
- required secrets instead of silent degraded behavior,
- TLS verification,
- path traversal protection,
- audit logs with redaction,
- shell disabled by default,
- validation of user-controlled config inputs,
- request-level rate limiting,
- browser bridge hardening,
- bearer-token protection for MCP bridge access.

### 18.2 Correctness best practices

The project also follows strong correctness patterns:

- typed boundaries,
- proof-backed policy logic,
- warnings as errors,
- validity/assertion flags,
- hardening linker flags,
- explicit build profiles,
- tested runtime modules,
- reproducible validation entrypoints.

### 18.3 Developer experience best practices

- good documentation coverage,
- onboarding flow,
- doctor command,
- status command,
- interactive config editing,
- clearly named make targets,
- explicit contribution instructions.

### 18.4 Operational best practices

- structured JSON-line logs,
- request ID correlation,
- metrics,
- service packaging,
- Docker Compose healthchecks,
- release pipeline design,
- supply-chain verification hooks,
- benchmark and gate artifacts.

### 18.5 Honest maturity signaling

A subtle but important best practice here is honesty. The docs do not pretend everything is fully polished. They explicitly call out when package channels are not yet the best install path or when parts of the runtime are still evolving.

That makes the project easier to trust.

---

## 19. Build, proof, test, and release workflow

### 19.1 Build metadata and profiles

From `alire.toml` and `vericlaw.gpr`, the project supports profiles such as:

- `dev`
- `release`
- `small`
- `edge-size`
- `edge-speed`
- `coverage`

It also supports multiple targets including native, Linux variants, Windows, and macOS targets.

### 19.2 Compiler and linker posture

`vericlaw.gpr` shows a strong default stance:

- Ada 2022 mode
- assertions and validity checks
- warnings enabled aggressively
- optional warnings-as-errors
- optimization tuned by profile
- stack protection
- section garbage collection / stripping in size-focused builds
- hardening flags on Linux releases

### 19.3 Proof workflow

The GPR file configures GNATprove with:

- `--level=2`
- `z3,cvc4,altergo`
- 60 second timeout
- fail reporting

The testing docs and contributing guide point contributors at:

```bash
make validate
make prove-host
```

### 19.4 Test workflow

The docs position these as key commands:

```bash
make validate
make runtime-tests
make secrets-test
make conformance-suite
make fuzz-suite
```

There are also higher-level gates and report-generating targets for:

- conformance,
- competitive regression,
- vulnerability/license scanning,
- supply chain verification,
- release-candidate readiness.

### 19.5 Release posture

The repo has clear signs of product-minded release engineering:

- GitHub Actions workflows,
- cross-platform builds,
- package-manager update intent,
- Docker release images,
- checksums/signing/provenance mindset,
- benchmark and supply-chain scripts.

---

## 20. Deployment and operations

### 20.1 Local deployment

The easiest path is still local CLI + one configured provider.

### 20.2 Compose-based multi-service deployment

`docker-compose.yml` wires together sidecars such as:

- `wa-bridge`
- `discord-bridge`
- `slack-bridge`
- `email-bridge`
- `irc-bridge`
- `matrix-bridge`
- `mattermost-bridge`
- `mcp-bridge`
- `browser-bridge`
- `vericlaw`

The compose file includes:

- env-var driven credentials,
- healthchecks,
- restart policies,
- persisted WhatsApp sessions,
- a localhost-only browser bridge port,
- `no-new-privileges` / dropped capabilities on the browser sidecar.

### 20.3 Metrics and logging

The operations docs highlight:

- `/metrics`
- structured logs to `stderr`
- request IDs
- log levels via `VERICLAW_LOG_LEVEL`

### 20.4 Service packaging

The repo includes deployment material for:

- Linux `systemd`
- macOS `launchd`
- Windows service installation

This is a strong sign that the project is designed to live as a daemonized runtime, not just an interactive shell tool.

---

## 21. Security posture in plain English

If you are evaluating VeriClaw, this is the most important non-marketing reading of the repo.

### 21.1 What the project takes seriously

It clearly takes seriously:

- untrusted inputs,
- prompt injection surfaces,
- credential leakage,
- unsafe tool execution,
- path escape attempts,
- remote exposure of operator interfaces,
- configuration-based misuse,
- unlogged failures.

### 21.2 What the project does about it

It responds with:

- verified policy packages,
- explicit auth and allowlist checks,
- local-only operator endpoints,
- strict workspace scoping,
- encrypted secrets,
- audit trails,
- input validation,
- defensive browser/MCP bridge behavior,
- deployment checklists.

### 21.3 What it does not pretend to solve fully

The security docs also show realism. For example, they note areas such as:

- no certificate pinning,
- some config-driven rather than fully proved controls,
- ongoing fuzzing/readiness work.

That is a sign of a serious engineering culture: strong claims where justified, clear caveats where not.

---

## 22. Known realities and caveats

This repo is impressive, but it is not magic. A fair reading of the docs suggests the following.

### 22.1 It is ambitious

VeriClaw combines:

- formal methods,
- native systems programming,
- AI provider integration,
- multi-channel messaging,
- browser/MCP bridges,
- memory/RAG,
- service operations.

That is a lot of scope for any one project.

### 22.2 It is still evolving

The docs describe active development, and some areas are clearly more mature than others.

Examples:

- source and release installs are more grounded than some package-manager paths,
- gateway streaming is currently buffered SSE rather than full token-by-token streaming end-to-end,
- some docs still lag each other slightly on channel counts or readiness wording.

### 22.3 The strongest value proposition is not “most integrations ever”

The strongest value proposition is better described as:

- **security-aware**,
- **native**,
- **disciplined**,
- **operator-friendly**,
- **proof-minded**.

That is where the repo feels most differentiated.

---

## 23. Who this project is for

VeriClaw looks especially well suited for:

- engineers who care about trust boundaries,
- teams that want a local/native assistant runtime,
- operators who need metrics, logs, and service packaging,
- contributors interested in Ada/SPARK applied to modern AI runtimes,
- people who want multi-channel deployment without surrendering all control to a hosted product.

It is probably less ideal for:

- someone who wants the absolute quickest zero-thinking path through a public package manager today,
- someone who wants the largest possible ecosystem of prebuilt plugins immediately,
- someone who is uncomfortable with Ada/SPARK or native-toolchain workflows.

---

## 24. The project’s engineering personality

One of the clearest things that comes through in the repo is that VeriClaw has a consistent engineering personality.

It values:

- explicitness over magic,
- typed APIs over loose conventions,
- verified policy over hand-wavy security claims,
- safe defaults over convenience defaults,
- native runtime discipline over framework sprawl,
- operational visibility over black-box behavior,
- contributor instructions and docs as part of the codebase.

That coherence is a strength.

---

## 25. Practical quick-start map

If you just want to know where to look next, use this map.

### If you want to use VeriClaw locally

- Read: `docs/getting-started.md`
- Then run: `vericlaw onboard`
- Validate with: `vericlaw doctor`
- Start with: `vericlaw chat`

### If you want to deploy it as a gateway

- Read: `docs/channels.md`
- Read: `docs/operations.md`
- Read: `docs/api.md`
- Then use: `docker compose up` or `vericlaw gateway`

### If you want to understand its security model

- Read: `SECURITY.md`
- Read: `ARCHITECTURE.md`
- Read: `docs/ada-coding-practices.md`

### If you want to contribute

- Read: `CONTRIBUTING.md`
- Read: `docs/testing.md`
- Run: `make validate`

### If you want to understand the code layout

- Start in:
  - `src/agent/`
  - `src/channels/`
  - `src/providers/`
  - `src/tools/`
  - `src/config/`
  - `src/http/`
  - `src/memory/`

---

## 26. Final assessment

VeriClaw is one of the more interesting AI runtime projects you could study if you care about applying serious software engineering techniques to agent systems.

Its biggest ideas are not superficial:

- a formal-verification-backed security core,
- a native Ada runtime with explicit trust layers,
- multi-provider and multi-channel support,
- practical service operations,
- and a contributor story rooted in testing, proofs, and explicit coding discipline.

It is also clearly still becoming itself. Some distribution paths are still maturing, some docs are still converging, and some gateway behaviors are still evolving. But the core design direction is unusually coherent.

If you want to understand VeriClaw in one sentence:

> It is a serious attempt to build an AI assistant runtime like infrastructure software instead of like a thin demo wrapper around an LLM API.

---

## Appendix A: Key commands at a glance

```bash
vericlaw onboard
vericlaw doctor
vericlaw config validate
vericlaw config edit
vericlaw reset
vericlaw chat
vericlaw agent "Summarize this repo"
vericlaw gateway
vericlaw channels login --channel whatsapp
vericlaw status
vericlaw export --session my-session
vericlaw update-check
vericlaw version
```

## Appendix B: Important files to read after this one

- `README.md`
- `ARCHITECTURE.md`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `docs/getting-started.md`
- `docs/installation.md`
- `docs/providers.md`
- `docs/channels.md`
- `docs/tools.md`
- `docs/operations.md`
- `docs/api.md`
- `docs/testing.md`
- `docs/project-overview.md`
- `docs/ada-coding-practices.md`
- `alire.toml`
- `vericlaw.gpr`
- `docker-compose.yml`

## Appendix C: A concise mental model

If you want a final mental model, use this:

- **SPARK layer** decides what is safe.
- **Ada runtime** decides what to do.
- **Sidecars** speak external protocol ecosystems.
- **SQLite** remembers.
- **Providers** answer.
- **Tools** act.
- **Gateway + ops surface** make it deployable.

That is VeriClaw.
