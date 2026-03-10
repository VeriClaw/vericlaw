# future/sandbox/

Process sandboxing module — not included in v1.0-minimal.

## What it is

`sandbox.ads/adb` — Runtime process isolation for tool execution. Adds a layer of OS-level sandboxing (seccomp/AppArmor on Linux, sandbox-exec on macOS) around shell tool invocations, beyond the SPARK allowlist policy in the security core.

## Returns at

v1.2 — together with the formal sandbox policy proofs.

## Current state

In v1.0-minimal, the shell tool security model relies on:
1. The SPARK-verified allowlist check in `channels-security` (allowlist is a formally verified policy decision, not application code)
2. Direct execution without shell expansion (`execve` semantics, not `sh -c`)
3. Workspace boundary enforcement via `security-policy`
4. Configurable timeout and output truncation

The sandbox module adds OS-level process isolation on top of this. It's valuable but not required for the "formally verified allowlist" security claim.
