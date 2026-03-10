# Contributing to VeriClaw

Thank you for contributing. Please read this guide before opening a PR.

---

## Coding Standards

VeriClaw follows the conventions in [`docs/ada-coding-practices.md`](docs/ada-coding-practices.md). Key points:

### Naming Conventions

| Element | Convention | Notes |
|---|---|---|
| Packages | `Mixed_Case` with underscores | e.g. `Gateway_Auth`, `Channels_Security` |
| Type names | `Mixed_Case` | **Approved project deviation**: the `_Type` suffix from the standard is omitted for brevity; rationale: consistent with existing GNAT runtime style |
| Constants | `Mixed_Case` | **Approved project deviation**: the standard specifies `ALL_UPPER_CASE`; this project uses `Mixed_Case` for readability in long names; document with rationale in a comment when deviating |
| Variables | `Mixed_Case` | e.g. `Current_Token_Index` |
| Subprograms | `Verb_Noun` style | e.g. `Parse_Arguments`, `Advance_Pairing_Status` |
| Parameters | Descriptive | e.g. `Input_Text`, `Result_Buffer` |

### Error Handling

- Never use `when others => null` to silently discard exceptions. Call `Metrics.Increment` with an appropriate counter instead (see `metrics.ads`).
- For expected failure modes, use discriminated `Result` records rather than exceptions.

### Resource Management

- Use `Ada.Finalization.Controlled` for RAII-style cleanup of file handles, sockets, and database connections.

---

## SPARK Requirements

- **New security-critical code** (auth, policy, allowlist, secrets, audit) must be in a package with `pragma SPARK_Mode (On)` and must have `Pre` / `Post` contracts on all public subprograms.
- **Runtime / I/O code** (HTTP calls, SQLite bindings, channel polling) must have `pragma SPARK_Mode (Off)` stated explicitly — do not leave it implicit.
- Before submitting, run the blessed validation flow:
  ```sh
  make validate
  ```
  This prefers the local GNAT/SPARK toolchain and falls back to the container
  runner when Docker is available. If you are changing security-critical code and
  have a full host proof toolchain installed, also run:
  ```sh
  make prove-host
  ```
  No new unresolved proof obligations are permitted.

---

## PR Process

1. Fork the repository and branch from `test` (not `main`).
2. Make your changes following the standards above.
3. Run `make validate` — this is the preferred build + proof + test entrypoint (`make check` remains an alias).
4. Run the smallest relevant targeted suites for your change, for example `make runtime-tests`, `make secrets-test`, `make operator-console-check`, or the affected bridge `node --test` command.
5. Verify your diff does not contain:
   - `when others => null` exception handlers
   - Hardcoded secrets, API keys, or tokens
   - Calls that disable TLS certificate verification
6. Add or update documentation if you are adding a new channel, provider, or tool (see sections below).
7. Open the PR against the `test` branch with a clear description of what changed and why.

---

## Adding a New Channel

Use the existing bridge pattern as your reference:

- **Node.js sidecar**: copy `wa-bridge/index.js` as a template. The sidecar must expose a local HTTP REST API and forward messages to/from the Ada runtime.
- **Ada channel package**: copy `src/channels/channels-whatsapp.adb` as a template. The package must call `Channels_Security.Check_Allowlist` and `Gateway_Auth.Validate_Token` before processing any message.
- **SPARK adapter spec**: add a `channels-adapters-<name>.ads` in `src/` following the pattern in `channels-adapters-slack.ads`.
- **`src/config/config-provider_aliases.ad[sb]`** — Provider alias registry (`Config.Provider_Aliases`): maps short names to OpenAI-compatible endpoint configurations.
- **`src/terminal/`** — Terminal styling layer (`Terminal.Style`): ANSI colors, ASCII banner, themed output functions. All user-facing CLI output goes through this module so `--no-color` works consistently.
- Add channel setup documentation in `docs/setup/<name>.md`.
- Register the sidecar port in `docker-compose.yml`.

---

## Adding a New Provider

Use `src/providers/providers-openai.adb` as your template:

- Implement the `Providers` child package interface defined in `src/providers.ads`.
- Use the `http-client` package for all outbound requests (do not call libcurl directly).
- Support streaming SSE where the provider offers it.
- Add a provider guide in `docs/providers/<name>.md`.
- **Shortcut for OpenAI-compatible providers:** If the new provider exposes an OpenAI-compatible API, you can register it as an alias in `src/config/config-provider_aliases.ad[sb]` instead of writing a full provider package. See the existing entries in `Config.Provider_Aliases` for examples.

---

## Test Framework

VeriClaw uses a custom test harness (no AUnit dependency). Add tests to the relevant file in `tests/`:

- Unit tests for a new package go in `tests/<package-name>_test.adb`.
- Run the full Ada runtime suite with `make runtime-tests`.
- Use `make config-test`, `make context-test`, `make memory-test`, or `make tools-test` for faster targeted loops.
- If you touch the operator console or a Node.js sidecar, also run `make operator-console-check` or the relevant bridge `node --test` command.
- Do not call live AI APIs in tests — mock all provider HTTP responses.

---

## Commit Format

```
type: short description (imperative, ≤72 chars)

Longer explanation if needed.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`.
