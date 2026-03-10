# MCP (Model Context Protocol) Setup

VeriClaw supports MCP servers via a lightweight bridge sidecar (`mcp-bridge`).
The bridge connects to MCP servers and exposes their tools to VeriClaw over a
simple REST API, so VeriClaw's Ada core only needs to call the HTTP endpoints it
already knows how to use.

## How it works

```
VeriClaw (Ada)  ──REST──▶  mcp-bridge (Node.js)  ──MCP──▶  MCP servers
```

1. On startup, VeriClaw calls `GET /tools` on the bridge to discover all available tools.
2. Those tools are added to the schema sent to the LLM provider, making them callable.
3. When the LLM calls an `mcp__*` tool, VeriClaw calls `POST /tools/{name}/call` on the bridge.
4. The bridge forwards the call to the appropriate MCP server and returns the result.

## Tool naming

Tools are namespaced as `mcp__{server}__{tool}`, e.g.:

- `mcp__filesystem__read_file`
- `mcp__github__search_repositories`

## Configuration

Add `mcp_bridge_url` to your `config.json` tools section:

```json
{
  "tools": {
    "file": true,
    "mcp_bridge_url": "http://localhost:3004"
  }
}
```

See `config/mcp.example.json` for a full example.

## Running with Docker Compose

The `docker-compose.yml` includes an optional `mcp-bridge` service.
Configure the MCP servers via the `MCP_SERVERS` environment variable:

```yaml
# docker-compose.override.yml
services:
  mcp-bridge:
    environment:
      MCP_SERVERS: |
        [
          {
            "name": "filesystem",
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
          }
        ]
```

Then start the stack:

```bash
docker compose --profile mcp up
```

## Supported transports

The bridge supports both MCP transport types:

| Transport | Config field | Example |
|-----------|-------------|---------|
| stdio     | `command` + `args` | `{"name":"fs","command":"npx","args":[...]}` |
| HTTP      | `url`       | `{"name":"remote","url":"http://host:8090"}` |

## Running the bridge locally (without Docker)

```bash
cd mcp-bridge
npm install
MCP_SERVERS='[{"name":"fs","command":"npx","args":["-y","@modelcontextprotocol/server-filesystem","."]}]' \
  node index.js
```

The bridge listens on port `3004` by default (override with `PORT` env var).

## Health check

```bash
curl http://localhost:3004/health
# {"ok":true,"tools":12}
```
