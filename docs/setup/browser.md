# Browser Tool Setup Guide for VeriClaw

Connect VeriClaw to a real Chromium browser via the `browser-bridge` Puppeteer
sidecar. This enables two agent tools:

- **`browser_browse`** — navigate to a URL and return the page's text content
- **`browser_screenshot`** — navigate to a URL and return a PNG screenshot

## Prerequisites

- Docker and Docker Compose
- A VeriClaw config with a provider API key

## Steps

### 1. Start the browser-bridge service

```bash
docker compose up browser-bridge -d
```

Verify it is healthy:

```bash
curl http://localhost:3007/health
# {"ok":true}
```

### 2. Configure VeriClaw

Add `browser_bridge_url` to the `tools` section of your config (e.g.
`~/.vericlaw/config.json`):

```json
{
  "tools": {
    "browser_bridge_url": "http://browser-bridge:3007"
  }
}
```

When running outside Docker (local development), use:

```json
{
  "tools": {
    "browser_bridge_url": "http://localhost:3007"
  }
}
```

### 3. Start VeriClaw

```bash
docker compose up vericlaw
```

The agent will now offer `browser_browse` and `browser_screenshot` tools to
the LLM.

## Running the bridge locally (without Docker)

```bash
cd browser-bridge
npm install          # downloads Chromium bundled with puppeteer
node index.js
```

## Security notes

- Private IP ranges (`10.x`, `172.16–31.x`, `192.168.x`, `127.x`) are blocked
  to prevent SSRF attacks.
- At most 2 concurrent browser requests are allowed; additional requests receive
  HTTP 429.
- The Docker container drops all Linux capabilities except `SYS_ADMIN`, which
  is required for the Chromium sandbox.

## Troubleshooting

- **"Browser bridge URL not configured"** — ensure `browser_bridge_url` is set
  in your `tools` config section.
- **Container OOM / slow start** — Chromium is memory-hungry; give the container
  at least 512 MB RAM.
- **`--no-sandbox` errors** — the bridge already passes `--no-sandbox` and
  `--disable-setuid-sandbox` flags; the `SYS_ADMIN` capability in the Docker
  config is the preferred alternative for production.
