# VeriClaw Browser Bridge

A lightweight Express + Puppeteer sidecar that gives VeriClaw real-browser
page-fetch and screenshot capabilities.

## Endpoints

| Method | Path          | Body                                   | Response                                              |
|--------|---------------|----------------------------------------|-------------------------------------------------------|
| GET    | `/health`     | —                                      | `{"ok":true}`                                         |
| POST   | `/browse`     | `{"url":"...","timeout_ms":15000}`     | `{"ok":true,"text":"...","title":"..."}`              |
| POST   | `/screenshot` | `{"url":"...","timeout_ms":15000}`     | `{"ok":true,"png_base64":"...","title":"..."}`        |

Error responses: `{"ok":false,"error":"<message>"}`

## Running locally

```bash
cd browser-bridge
npm install
node index.js
```

## Running via Docker Compose

```bash
docker compose up browser-bridge
```

## Configuration

Set `browser_bridge_url` in your VeriClaw config `tools` section:

```json
{
  "tools": {
    "browser_bridge_url": "http://browser-bridge:3007"
  }
}
```

## Security

- Private IP ranges (10.x, 172.16-31.x, 192.168.x, 127.x) are blocked.
- Maximum 2 concurrent browser requests (returns 429 when exceeded).
- Container runs with dropped capabilities; `SYS_ADMIN` is added only for the
  Chromium sandbox.
