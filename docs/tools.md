# Tools

[← Back to README](../README.md)

VeriClaw v0.3.0 ships **3 built-in tools**. Additional tools (Git, Brave Search, Browser, Spawn/Delegate, MCP, RAG) are in [`future/tools/`](../future/tools/) and return in v1.1.

## Tool Reference

| Tool | Config Key | Default | Description |
|------|-----------|---------|-------------|
| File I/O | `file: true` | **on** | Read/write/list files in `~/.vericlaw/workspace/` |
| Shell | `shell: true` | off | Execute shell commands (requires allowlist) |
| Cron scheduler | always available | — | Schedule recurring AI tasks |

---

## File I/O

Read, write, and list files within `~/.vericlaw/workspace/`. Path traversal (`../`) and symlink escapes are blocked at the security policy level (SPARK-proved).

```json
{ "tools": { "file": true } }
```

Three operations exposed to the LLM:

| Operation | Description |
|-----------|-------------|
| `file_read` | Read the contents of a file |
| `file_write` | Write or overwrite a file |
| `file_list` | List directory contents |

All paths are resolved relative to the workspace root. Absolute paths outside the workspace are rejected.

---

## Shell

Execute shell commands via popen. Disabled by default. When enabled, only commands matching the configured allowlist are permitted — all invocations are logged to the audit trail.

```json
{
  "tools": {
    "shell": true,
    "shell_allowlist": ["ls", "cat", "grep", "git *"]
  }
}
```

> ⚠️ Enable with care — the shell tool gives the LLM access to your local environment. Keep the allowlist narrow.

---

## Cron Scheduler

Schedule recurring tasks that run automatically. Jobs survive restarts (stored in SQLite) and are checked every 60 seconds by a background Ada task.

```
you: Remind me every morning to review my tasks
bot: [calls cron_add("morning-reminder", "24h", "Remind me to review my task list")]
bot: Scheduled. Next run: tomorrow at 09:00.
```

Three sub-tools:

| Sub-tool | Purpose |
|----------|---------|
| `cron_add` | Create a new scheduled job |
| `cron_list` | List all registered jobs |
| `cron_remove` | Delete a job by name |

Supported intervals: `5m`, `1h`, `24h`, `7d`.

---

## Coming in v1.1

Git operations, Brave Search, Browser automation, Spawn/Delegate sub-agents, MCP tool server integration, and vector RAG memory are all implemented in `future/tools/` and return in the v1.1 milestone.
