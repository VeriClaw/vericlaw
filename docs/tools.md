# Tools

[← Back to README](../README.md)

VeriClaw ships 13 built-in tools plus unlimited extensibility via MCP (Model Context Protocol).

## Tool Reference

| Tool | Config Key | Default | Description |
|---|---|---|---|
| File I/O | `file: true` | **on** | Read/write/list files in `~/.vericlaw/workspace/` |
| Shell | `shell: true` | off | Execute shell commands via popen |
| Web fetch | `web_fetch: true` | off | Fetch and parse web pages |
| Brave Search | `brave_search: true` + `brave_api_key` | off | Web search via Brave Search API |
| Git operations | `git: true` | **on** | `status`, `log`, `diff`, `add`, `commit`, `push`, `pull`, `branch`, `checkout` |
| Cron scheduler | always available | — | `cron_add`, `cron_list`, `cron_remove` — schedule recurring AI tasks |
| Spawn | always available | — | Delegate a subtask to an isolated sub-agent |
| Delegate | always available | — | Delegate a task to a role-specialized sub-agent |
| Plugin registry | always available | — | Inspect discovered local plugin manifests and MCP-first extensibility state |
| Browser browse | `browser_bridge_url` | off | Fetch JS-rendered page text via headless Chromium |
| Browser screenshot | `browser_bridge_url` | off | Screenshot any URL as PNG (base64) |
| Memory search | `rag_enabled: true` | off | Semantic similarity search over conversation history |
| MCP tools | `mcp_bridge_url` | off | Auto-discovered from any MCP server via mcp-bridge |

---

## Built-in Tools

### File I/O

Read, write, and list files in `~/.vericlaw/workspace/`. Workspace-scoped — `../` and NUL path-traversal attacks are blocked at the policy level (proved in SPARK).

Config key: `file: true` (enabled by default).

Three operations are available:

| Operation | Description |
|---|---|
| `file_read` | Read the contents of a file |
| `file_write` | Write or overwrite a file |
| `file_list` | List directory contents |

All paths are resolved relative to the workspace root. Absolute paths outside the workspace and symlink escapes are rejected.

### Shell

Execute shell commands via popen. Disabled by default for security; enable with an explicit allowlist of permitted commands.

Config key: `shell: true`.

When enabled, only commands matching the configured allowlist patterns are permitted. All shell invocations are logged to the audit trail.

```json
{
  "tools": {
    "shell": true,
    "shell_allowlist": ["ls", "cat", "grep", "git *"]
  }
}
```

### Web Fetch

Fetch and parse web pages into plain text suitable for LLM consumption. HTML is cleaned of scripts, styles, and navigation chrome, then converted to readable text.

Config key: `web_fetch: true`.

### Brave Search

Web search via the Brave Search API. Returns structured search results with titles, URLs, and snippets.

Config keys: `brave_search: true` and `brave_api_key: "<key>"`.

You can obtain a Brave Search API key at <https://brave.com/search/api/>.

### Git Operations

Nine actions: `status`, `log`, `diff`, `add`, `commit`, `push`, `pull`, `branch`, `checkout`.

Config key: `git: true` (enabled by default).

| Action | Description |
|---|---|
| `status` | Show working tree status |
| `log` | View commit history |
| `diff` | Show uncommitted changes |
| `add` | Stage files for commit |
| `commit` | Create a commit with a message |
| `push` | Push commits to remote |
| `pull` | Pull changes from remote |
| `branch` | List or create branches |
| `checkout` | Switch branches or restore files |

Git operations run against the repository at `~/.vericlaw/workspace/` (or a configured `git_repo_path`).

### Cron Scheduler

Schedule recurring tasks that run automatically:

```
you: cron_add daily-summary every 24h — "Give me a briefing on what happened today"
bot: Scheduled 'daily-summary' to run every 24h. Next run: 2026-02-28T14:00:00Z
```

Supported intervals: `5m`, `1h`, `24h`, `7d`.

Jobs are stored in SQLite and survive restarts. A background Ada task checks for due jobs every 60 seconds and runs them autonomously.

Three sub-tools are exposed to the LLM:

| Sub-tool | Purpose |
|---|---|
| `cron_add` | Create a new scheduled job |
| `cron_list` | List all registered jobs |
| `cron_remove` | Delete a job by name |

### Spawn / Sub-agent

The LLM can delegate focused subtasks to an isolated sub-agent:

```
you: Research the top 5 Rust async runtimes and compare them
bot: [calls spawn("Research top 5 Rust async runtimes: Tokio, async-std, ...")]
bot: Here's a comparison based on the research: ...
```

Sub-agents run with a clean conversation (system prompt + single prompt, no tools, depth cap = 1). This keeps the parent conversation focused while offloading research or analysis to a dedicated context.

The depth cap of 1 prevents infinite recursion — a spawned sub-agent cannot itself call `spawn`.

### Delegate

Hand work to a role-specialized sub-agent. Available roles:

| Role | Purpose |
|---|---|
| `researcher` | Information gathering and synthesis |
| `coder` | Code generation and editing |
| `reviewer` | Code review and quality checks |
| `general` | General-purpose assistance |

Each role receives a tailored system prompt optimized for its specialization. Multi-agent orchestration uses SPARK-proved depth limits to prevent runaway delegation chains.

```
you: Review this pull request for security issues
bot: [calls delegate(role="reviewer", task="Audit PR #42 for security vulnerabilities")]
bot: The reviewer found two issues: ...
```

### Browser Tools

Two tools — `browser_browse` and `browser_screenshot` — powered by a Puppeteer sidecar that bundles headless Chromium.

**Setup:**

```bash
docker compose up browser-bridge vericlaw
```

**Config:**

```json
{ "tools": { "browser_bridge_url": "http://browser-bridge:3007" } }
```

**Usage:**

```
you: What does the VeriClaw homepage say?
bot: [calls browser_browse("https://example.com")]
bot: The page title is "Example Domain" and the body reads: ...

you: Screenshot the GitHub trending page
bot: [calls browser_screenshot("https://github.com/trending")]
bot: [returns base64 PNG]
```

**Security:** Private IP addresses (10.x, 192.168.x, 127.x, 172.16–31.x) are blocked at the bridge level. Max 2 concurrent requests. The bridge enforces a 30-second page-load timeout.

| Tool | Returns |
|---|---|
| `browser_browse` | Extracted page text (JavaScript-rendered) |
| `browser_screenshot` | Base64-encoded PNG image |

See [setup/browser.md](setup/browser.md) for full installation instructions.

### Vector RAG Memory

Semantic search over your conversation history using [sqlite-vec](https://github.com/asg017/sqlite-vec) embeddings. The agent automatically retrieves relevant past context before answering.

**Requirements:** sqlite-vec shared library installed, and an OpenAI-compatible embeddings endpoint.

**Install sqlite-vec:**

```bash
# macOS
brew install sqlite-vec

# Ubuntu / Debian
apt-get install libsqlite-vec-dev
```

**Config:**

```json
{
  "tools": {
    "rag_enabled": true,
    "rag_embed_base_url": "https://api.openai.com/v1"
  }
}
```

The `memory_search` tool is then available to the LLM:

```
you: What did we discuss about Rust last week?
bot: [calls memory_search("Rust async runtimes", k=5)]
bot: Based on our earlier conversations, you asked about Tokio vs async-std. Here's a summary...
```

See [setup/rag.md](setup/rag.md) for full setup, including using Ollama's `nomic-embed-text` as a free local embedding model.

**How it works:**
1. Each conversation turn is embedded and stored in a local sqlite-vec database.
2. When the LLM calls `memory_search`, the query is embedded and compared via cosine similarity.
3. The top-*k* matching conversation fragments are returned as context.

### Plugin Registry

Discovery-only today. Point `tools.plugin_directory` at a folder of manifests, then inspect the runtime registry via the built-in `plugin_registry` tool or the HTTP API:

```json
{
  "tools": {
    "plugin_directory": "~/.vericlaw/plugins"
  }
}
```

Only manifests with `signature_state: "signed_trusted_key"` are surfaced in the runtime registry. The loader does not execute arbitrary local plugin code at startup.

All plugin capabilities are governed by a SPARK-verified capability policy — ensuring that no plugin can escalate beyond its declared permissions.

---

## MCP (Model Context Protocol)

Connect any [Model Context Protocol](https://modelcontextprotocol.io) tool server to extend VeriClaw with unlimited external tools.

**Config:**

```json
{
  "tools": { "mcp_bridge_url": "http://mcp-bridge:3004" }
}
```

**docker-compose.yml:**

```yaml
mcp-bridge:
  build: ./mcp-bridge
  environment:
    MCP_SERVERS: '[{"name":"filesystem","command":"npx","args":["-y","@modelcontextprotocol/server-filesystem","/workspace"]}]'
  profiles: [mcp]
```

On startup, VeriClaw fetches the tool list from the bridge and exposes them to the LLM as `mcp__{server}__{tool}` — transparently alongside built-in tools.

**Naming convention:** MCP tools appear as `mcp__{server}__{tool}`. For example, a tool called `read_file` from the `filesystem` server becomes `mcp__filesystem__read_file`.

You can register multiple MCP servers by adding entries to the `MCP_SERVERS` JSON array. Each server is started and managed independently by the bridge.

See [setup/mcp.md](setup/mcp.md) for detailed configuration.

---

## Parallel Tool Execution

When an LLM response includes multiple tool calls, VeriClaw executes them concurrently via Ada tasks and collects results in order. Ordering-sensitive tools (`cron_*`, `spawn`) always run sequentially.

This means a single LLM turn that requests, say, three web fetches and a file read will complete in roughly the time of the slowest call rather than the sum of all four.

**Sequential exceptions:**

| Tool | Reason |
|---|---|
| `cron_*` | Job mutations must be serialized |
| `spawn` | Sub-agent depth tracking requires ordering |

All other tools — including `file`, `web_fetch`, `brave_search`, `git`, `browser_*`, `memory_search`, and MCP tools — are safe for concurrent dispatch.
