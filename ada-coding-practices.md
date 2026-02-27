**Best Coding & Security Practices**

**for a CLI-Based AI Agent Project**

Written in Ada/SPARK

Reference Document

Version 1.0 --- February 2026

Table of Contents

1\. Introduction

This document defines the coding standards, security practices, and
development guidelines to be followed when building a CLI-based AI agent
project in Ada/SPARK. Ada's strong type system and SPARK's formal
verification capabilities make them an excellent foundation for building
safety-critical, secure, and reliable software. These practices ensure
the project is maintainable, auditable, and resilient from day one.

The guidelines are organized into logical sections covering project
structure, coding conventions, SPARK-specific formal verification,
security hardening, dependency and build management, testing strategy,
documentation, and operational concerns.

2\. Project Structure & Organization

2.1 Directory Layout

Adopt a clear, consistent directory structure from the start. A
recommended layout:

> project_root/
>
> ├── src/ \-- Ada/SPARK source (.ads, .adb)
>
> │ ├── core/ \-- Core agent logic
>
> │ ├── cli/ \-- CLI parsing and I/O
>
> │ ├── security/ \-- Crypto, auth, sanitization
>
> │ ├── ai/ \-- AI model interface & orchestration
>
> │ └── util/ \-- Shared utilities
>
> ├── tests/ \-- Unit and integration tests
>
> ├── proofs/ \-- SPARK proof artifacts & configs
>
> ├── config/ \-- Configuration files
>
> ├── docs/ \-- Documentation
>
> ├── scripts/ \-- Build, CI, and utility scripts
>
> └── project.gpr \-- GNAT project file

2.2 Module Separation Principles

-   Separate specification (.ads) from body (.adb) for every package.

-   Use child packages (e.g., AI.Inference, AI.Tokenizer) for logical
    grouping.

-   Keep the CLI layer thin: parse arguments, delegate to core, format
    output.

-   Isolate all external-facing I/O (network, file, stdin/stdout) into
    dedicated packages for easy mocking and formal verification
    boundaries.

-   Never embed AI model logic directly in CLI handlers.

2.3 GNAT Project File (.gpr) Conventions

-   Define separate build scenarios: Debug, Release, and SPARK_Prove.

-   Enable maximum warnings in all modes: -gnatwa -gnatyy -gnatwe
    (warnings as errors).

-   Use -gnata to enable assertions in Debug mode.

-   Set -gnatVa for all validity checks in Debug.

-   Enable stack checking (-fstack-check) and overflow checking (-gnato)
    by default.

3\. Ada Coding Standards

3.1 Naming Conventions

  ----------------------- ----------------------- -----------------------
  **Element**             **Convention**          **Example**

  Packages                Mixed_Case with         AI.Model_Loader
                          underscores             

  Types                   Suffix \_Type or        Token_Count_Type
                          descriptive             

  Subtypes                Descriptive constrained Valid_Temperature
                          name                    

  Constants               All_Upper_Case          MAX_CONTEXT_LENGTH

  Variables               Mixed_Case              Current_Token_Index

  Subprograms             Verb_Noun or            Parse_Arguments
                          descriptive             

  Parameters              Descriptive with mode   Input_Text,
                          prefix if helpful       Result_Buffer
  ----------------------- ----------------------- -----------------------

3.2 Type Safety & Strong Typing

Ada's type system is one of its greatest assets. Leverage it
aggressively:

-   **Define constrained types:** Never use Integer or Float directly.
    Create named types with explicit ranges (e.g., type Token_Index is
    range 0 .. 131_072).

-   **Use subtypes for invariants:** subtype Valid_Temperature is Float
    range 0.0 .. 2.0 to enforce model temperature bounds at compile
    time.

-   **Prefer enumerations:** Use enumeration types for states, modes,
    and categories instead of magic numbers or strings.

-   **Avoid unchecked conversions:** Every use of Unchecked_Conversion
    or address overlays must be documented and reviewed. Prefer safe
    alternatives.

-   **Use access types sparingly:** Prefer bounded data structures. When
    access types are necessary, use not null access and ensure clear
    ownership semantics.

3.3 Error Handling

-   Use exceptions for truly exceptional conditions (I/O failure, OS
    errors), not control flow.

-   Define project-specific exception types in a central Exceptions
    package.

-   Every exception handler must either re-raise, log with context, or
    return a meaningful error code. Never silently swallow exceptions.

-   For expected failure modes (invalid input, API timeout), use
    discriminated records or status codes instead of exceptions.

> type Result_Kind is (Success, Failure);
>
> type Operation_Result (Kind : Result_Kind := Failure) is record
>
> case Kind is
>
> when Success =\> Value : Response_Type;
>
> when Failure =\> Error : Error_Info;
>
> end case;
>
> end record;

3.4 Resource Management

-   Use controlled types (Ada.Finalization.Controlled) for RAII-style
    resource management.

-   Every file handle, socket, or memory allocation must have a
    deterministic cleanup path.

-   Use block scope to limit the lifetime of resources where possible.

-   Never allocate unbounded memory based on external input without
    explicit caps.

4\. SPARK Formal Verification Practices

4.1 SPARK Mode Strategy

Not all code can or should be in SPARK. Adopt a layered approach:

  ----------------- -------------------------- --------------------------
  **Layer**         **SPARK Mode**             **Rationale**

  Core agent logic  SPARK_Mode =\> On          Prove absence of runtime
                                               errors, data flow
                                               correctness

  Security modules  SPARK_Mode =\> On          Formal proof of input
                                               validation, no information
                                               leakage

  AI orchestration  SPARK_Mode =\> On          Prove contracts on API
                    (interfaces)               boundaries

  CLI I/O handling  SPARK_Mode =\> Off         I/O has side effects
                                               incompatible with pure
                                               SPARK

  External bindings SPARK_Mode =\> Off         C/FFI interfaces require
                                               Ada-only features
  ----------------- -------------------------- --------------------------

4.2 Contract-Based Design

Use preconditions, postconditions, and type invariants throughout SPARK
code:

-   **Preconditions (Pre):** Express every assumption about inputs. This
    is the caller's responsibility.

-   **Postconditions (Post):** Express guarantees about outputs. This is
    the callee's promise.

-   **Type Invariants:** Use on private types to ensure objects are
    always in a valid state.

-   **Ghost Code:** Use ghost variables and ghost functions for
    specification-only logic that does not affect runtime behavior.

> procedure Process_Token (Input : Token_Type; Output : out
> Response_Type)
>
> with Pre =\> Is_Valid_Token (Input),
>
> Post =\> Output.Length \<= MAX_RESPONSE_LENGTH
>
> and then Is_Well_Formed (Output);

4.3 Proof Obligations

-   Run GNATprove as part of every CI build. No code merges with
    unresolved proof obligations.

-   Aim for zero runtime checks in SPARK modules: prove absence of
    overflow, division by zero, index out of bounds, and null
    dereference.

-   Document any justified proof suppressions with rationale and review
    approval.

-   Track proof coverage metrics: percentage of VCs (Verification
    Conditions) discharged automatically vs. those needing manual
    review.

5\. Security Practices

5.1 Input Validation & Sanitization

As a CLI tool that interfaces with AI models, all external input is
untrusted:

-   **Command-line arguments:** Validate length, character set, and
    structure before processing. Use bounded strings
    (Ada.Strings.Bounded) instead of unbounded.

-   **Configuration files:** Parse with strict schemas. Reject unknown
    keys. Validate all values against expected types and ranges.

-   **AI model responses:** Treat as untrusted. Validate structure,
    length, and content before acting on any model output. Never execute
    model-suggested commands without explicit sanitization.

-   **Environment variables:** Validate and sanitize. Do not blindly
    trust PATH, HOME, or any other env var.

5.2 Memory Safety

Ada and SPARK provide strong memory safety guarantees. Reinforce them:

-   Prefer stack allocation and bounded containers over heap allocation.

-   When using access types, employ SPARK pointer ownership model or
    manual ownership tracking.

-   Zero-fill sensitive data (API keys, tokens, credentials) immediately
    after use using a dedicated Secure_Wipe procedure.

-   Use pragma Restrictions (No_Implicit_Heap_Allocations) where
    feasible to catch unintended allocations.

-   Enable Address Space Layout Randomization (ASLR) and stack canaries
    in compiler flags for the release build.

5.3 Secrets & Credential Management

-   **Never hardcode secrets:** API keys, model endpoints, and
    authentication tokens must come from environment variables or a
    secure vault, never from source code.

-   **Ephemeral storage only:** Load secrets into memory, use them, and
    immediately wipe. Never write secrets to temporary files or logs.

-   **Minimal exposure:** Pass secrets by reference to the narrowest
    scope possible. Do not propagate credentials through the call chain.

-   **.gitignore enforcement:** Maintain a strict .gitignore that
    excludes config files containing secrets, key files, and environment
    files.

-   **Pre-commit hooks:** Use tools like git-secrets or trufflehog in
    pre-commit to scan for accidental secret commits.

5.4 Secure Communication

-   All external API calls (to AI model providers, remote services) must
    use TLS 1.2 or higher.

-   Validate server certificates. Do not disable certificate
    verification, even in development.

-   Pin certificates or public keys for known AI provider endpoints
    where feasible.

-   Implement request timeouts and retry limits to prevent resource
    exhaustion from unresponsive endpoints.

-   Log connection metadata (endpoint, TLS version, cipher) but never
    log request or response payloads containing sensitive data.

5.5 Prompt Injection Defense

Since this project creates an AI agent, prompt injection is a
first-class security concern:

-   Separate system prompts from user input at the data structure level.
    Use tagged types or discriminated records so they can never be
    accidentally concatenated.

-   Apply output filtering on model responses before any action is taken
    (file writes, command execution, data retrieval).

-   Implement an allowlist of permitted agent actions. The agent should
    never have unconstrained capability.

-   Log all agent actions with full context for auditability.

-   Rate-limit agent actions to prevent runaway loops from adversarial
    inputs.

6\. Build, Dependency & CI/CD Practices

6.1 Build Configuration

  ----------------- -------------------------- --------------------------
  **Build Mode**    **Key Flags**              **Purpose**

  Debug             -gnata -gnatVa -gnatwa     All assertions, validity
                    -gnatwe -g -O0             checks, warnings as
                                               errors, full debug info

  Release           -gnatp -O2 -fstack-check   Suppress non-essential
                    -fstack-protector-strong   checks, optimize, harden
                                               stack

  SPARK_Prove       \--mode=prove \--level=2   Full formal verification
                    \--prover=all              pass
  ----------------- -------------------------- --------------------------

6.2 Dependency Management

-   Use Alire (Ada Library Repository) for Ada dependencies. Pin exact
    versions in alire.toml.

-   Vet every dependency: review source, check maintenance status,
    assess security posture.

-   Minimize C/FFI dependencies. When unavoidable, wrap them in thin Ada
    binding packages with full input validation at the boundary.

-   Vendor critical dependencies when upstream stability is uncertain.

-   Maintain a bill of materials (BOM) listing all dependencies,
    versions, and licenses.

6.3 CI/CD Pipeline

Every commit should trigger the following pipeline stages:

-   **Stage 1 --- Compile:** Build in Debug mode with all warnings as
    errors.

-   **Stage 2 --- SPARK Prove:** Run GNATprove. Fail on any unresolved
    verification conditions.

-   **Stage 3 --- Unit Tests:** Run AUnit test suites with coverage
    reporting.

-   **Stage 4 --- Integration Tests:** Test CLI behavior end-to-end with
    mocked AI backends.

-   **Stage 5 --- Security Scan:** Static analysis, secret scanning,
    dependency vulnerability check.

-   **Stage 6 --- Release Build:** Compile in Release mode with
    hardening flags.

7\. Testing Strategy

7.1 Test Pyramid

  ----------------- ----------------- ----------------- -----------------
  **Level**         **Tool**          **Coverage        **Scope**
                                      Target**          

  Unit              AUnit             ≥90% line         Individual
                                      coverage          subprograms

  Contract          GNATprove         100% VC discharge SPARK-annotated
                                                        modules

  Integration       Custom harness    All CLI commands  End-to-end
                                                        workflows

  Fuzz              AFL / libFuzzer   Input parsing     Robustness under
                                      paths             adversarial input

  Security          Manual +          OWASP top risks   Prompt injection,
                    automated                           auth, secrets
  ----------------- ----------------- ----------------- -----------------

7.2 AI-Specific Testing

-   Mock all AI model interactions in unit and integration tests. Never
    call live APIs in CI.

-   Create a corpus of adversarial prompts to test prompt injection
    defenses.

-   Test agent behavior under model failure modes: timeout, malformed
    response, empty response, oversized response.

-   Validate that the agent's action allowlist is enforced under all
    code paths.

-   Regression test every security incident or vulnerability found.

8\. Documentation Standards

8.1 Code Documentation

-   Every package specification must have a header comment describing
    its purpose, responsibilities, and usage.

-   Every public subprogram must document its preconditions,
    postconditions, and side effects in comments (in addition to SPARK
    contracts).

-   Complex algorithms must include a prose explanation of the approach,
    not just inline comments.

-   Document all deviations from SPARK mode, unsafe conversions, and
    suppressed warnings with rationale.

8.2 Project Documentation

-   **README.md:** Project overview, build instructions, quick start
    guide.

-   **ARCHITECTURE.md:** High-level architecture, module
    responsibilities, data flow diagrams.

-   **SECURITY.md:** Threat model, security controls, vulnerability
    reporting process.

-   **CONTRIBUTING.md:** Coding standards summary, PR process, review
    checklist.

-   **CHANGELOG.md:** Versioned history of changes following semantic
    versioning.

9\. Operational & Runtime Practices

9.1 Logging & Observability

-   Use structured logging (key-value pairs) for machine-parseable
    output.

-   Define log levels: Error, Warn, Info, Debug, Trace. Default to Info
    in production.

-   Never log secrets, API keys, full prompts containing user PII, or
    raw model responses containing sensitive data.

-   Include correlation IDs for tracing agent actions across multi-step
    operations.

-   Log all security-relevant events: authentication attempts, action
    execution, input validation failures.

9.2 Configuration Management

-   Support a clear precedence order: command-line flags \> environment
    variables \> config file \> defaults.

-   Validate all configuration at startup. Fail fast with clear error
    messages for invalid config.

-   Document every configuration option with its type, default value,
    valid range, and security implications.

-   Never expose internal configuration (debug flags, verbose modes) in
    release builds unless explicitly intended.

9.3 Graceful Degradation

-   Implement circuit breakers for external API calls to prevent cascade
    failures.

-   Define fallback behavior when AI model endpoints are unreachable.

-   Set hard limits on agent execution time, action count, and memory
    consumption.

-   Ensure the CLI always returns meaningful exit codes (0 = success, 1
    = user error, 2 = system error, etc.).

10\. Project Creation Checklist

Use this checklist when initializing the project to ensure all practices
are in place from the start:

-   [ ] Directory structure created per Section 2.1

-   [ ] GNAT project file (.gpr) configured with Debug, Release, and
    SPARK_Prove scenarios

-   [ ] Compiler warnings set to maximum, treated as errors

-   [ ] SPARK_Mode annotations applied to core and security packages

-   [ ] Naming conventions documented and enforced (Section 3.1)

-   [ ] Custom constrained types defined for all domain values

-   [ ] Result types defined for expected failure modes

-   [ ] Input validation implemented for all CLI arguments and config

-   [ ] Secret management strategy in place (env vars or vault)

-   [ ] .gitignore configured to exclude secrets, keys, build artifacts

-   [ ] Pre-commit hooks installed for secret scanning

-   [ ] TLS configured for all external API calls

-   [ ] Prompt injection defenses implemented (Section 5.5)

-   [ ] Agent action allowlist defined and enforced

-   [ ] CI pipeline configured with all 6 stages (Section 6.3)

-   [ ] AUnit test framework set up with initial test stubs

-   [ ] GNATprove integrated into CI

-   [ ] Fuzz testing harness created for input parsing

-   [ ] README.md, ARCHITECTURE.md, SECURITY.md created

-   [ ] Structured logging framework initialized

-   [ ] Configuration precedence and validation implemented

-   [ ] Exit codes defined and documented

*End of Document*