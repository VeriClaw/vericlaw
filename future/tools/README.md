# future/tools/

Ada tool implementations not included in the v1.0-minimal tool set.

v1.0-minimal ships five tools: `file`, `web_fetch`, `shell`, `cron`, `export`. More capable but higher-risk tools are preserved here.

## Contents

| Directory | Tool | Ada files | Returns at |
|-----------|------|-----------|------------|
| `git/` | Dedicated git tool (beyond the shell allowlist) | `tools-git.*` | v1.1 |
| `brave/` | Brave Search API integration | `tools-brave_search.*` | v1.2 |
| `browser/` | Puppeteer-backed web browsing with JavaScript rendering | `tools-browser.*` | v1.3 |
| `subagents/` | spawn/delegate sub-agent tools | `tools-spawn.*` | v1.3 |
| `mcp/` | Model Context Protocol tool integration | `tools-mcp.*` | v1.3 |

## v1.0-minimal tool set (stays in src/)

| Tool | Capability | Security |
|------|-----------|----------|
| `file` | Read/write files in workspace | Path traversal blocked by SPARK policy |
| `web_fetch` | HTTP GET for web content | URL validated against egress policy |
| `shell` | Execute allowlisted commands | Allowlist formally verified in SPARK security core |
| `cron` | Schedule recurring/one-shot tasks | Rate-limited; runs through normal agent loop |
| `export` | Export session to markdown | Read-only; writes to workspace exports/ dir |

## Note on git

In v1.0-minimal, `git` is in the shell allowlist by default. The dedicated `tools-git` adapter adds structured git operations (commit, diff, log, branch management) beyond what raw shell allows. It returns at v1.1.
