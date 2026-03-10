# VeriClaw Gateway HTTP API Reference

## Overview

VeriClaw exposes a lightweight HTTP gateway built on AWS (Ada Web Server).
The server binds to a configurable host and port from the agent configuration.

| Property | Value |
|---|---|
| **Base URL** | `http://127.0.0.1:{port}` (host/port set via `Gateway.Bind_Host` / `Gateway.Bind_Port`) |
| **Content-Type** | `application/json` for most endpoints; `text/event-stream` for SSE; `text/plain` for Prometheus metrics |
| **Authentication** | Localhost-only. Operator endpoints (`/api/*`) reject non-`127.0.0.1` requests with `403 Forbidden`. |
| **Max connections** | 64 (hardcoded) |
| **Sessions** | Disabled at the AWS layer |

---

## Security Headers

Every response includes the following headers:

| Header | Value | Purpose |
|---|---|---|
| `X-Content-Type-Options` | `nosniff` | Prevents MIME-type sniffing |
| `X-Frame-Options` | `DENY` | Prevents clickjacking via iframes |
| `Cache-Control` | `no-store` | Prevents caching of responses |

---

## Endpoints

### GET /health

Public health-check probe. No authentication required.

**Response** `200 OK`

```json
{
  "status": "ok",
  "service": "vericlaw"
}
```

**Example**

```bash
curl http://127.0.0.1:8080/health
```

---

### GET /metrics

Prometheus-compatible metrics export. No authentication required.

**Response** `200 OK` — `text/plain; version=0.0.4`

Returns metrics in Prometheus exposition format as rendered by the internal `Metrics.Render` function.

**Example**

```bash
curl http://127.0.0.1:8080/metrics
```

---

### GET /api/status

Returns server runtime status. **Localhost only.**

**Response** `200 OK`

```json
{
  "status": "running",
  "version": "0.2.0",
  "uptime_s": 3600,
  "channels_active": 3
}
```

| Field | Type | Description |
|---|---|---|
| `status` | string | Always `"running"` |
| `version` | string | Server version |
| `uptime_s` | integer | Seconds since the server started |
| `channels_active` | integer | Number of enabled channel configurations |

**Error Codes**

| Status | Body | Condition |
|---|---|---|
| `403` | `{"error":"forbidden"}` | Request not from `127.0.0.1` |

**Example**

```bash
curl http://127.0.0.1:8080/api/status
```

---

### GET /api/channels

Lists all configured channels and their settings. **Localhost only.**

**Response** `200 OK`

```json
{
  "channels": [
    {
      "kind": "telegram",
      "enabled": true,
      "max_rps": 10
    },
    {
      "kind": "signal",
      "enabled": false,
      "max_rps": 5
    }
  ]
}
```

| Field | Type | Description |
|---|---|---|
| `channels[].kind` | string | One of: `cli`, `telegram`, `signal`, `whatsapp`, `discord`, `slack`, `email`, `irc`, `matrix` |
| `channels[].enabled` | boolean | Whether the channel is active |
| `channels[].max_rps` | integer | Rate-limit (requests per second) for the channel |

**Error Codes**

| Status | Body | Condition |
|---|---|---|
| `403` | `{"error":"forbidden"}` | Request not from `127.0.0.1` |

**Example**

```bash
curl http://127.0.0.1:8080/api/channels
```

---

### GET /api/metrics/summary

Returns a compact summary of key counters. **Localhost only.**

**Response** `200 OK`

```json
{
  "provider_requests_total": 142,
  "provider_errors_total": 3,
  "tool_calls_total": 57
}
```

| Field | Type | Description |
|---|---|---|
| `provider_requests_total` | integer | Total LLM provider requests across all providers |
| `provider_errors_total` | integer | Total provider errors across all providers |
| `tool_calls_total` | integer | Total tool invocations across all tools |

**Error Codes**

| Status | Body | Condition |
|---|---|---|
| `403` | `{"error":"forbidden"}` | Request not from `127.0.0.1` |

**Example**

```bash
curl http://127.0.0.1:8080/api/metrics/summary
```

---

### POST /api/chat

Non-streaming chat completion. Sends a message through the agent loop and returns the full reply. **Localhost only.**

**Request Body**

```json
{
  "message": "Hello, what can you do?",
  "session_id": "my-session"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `message` | string | **yes** | The user message to send to the agent |
| `session_id` | string | no | Conversation session identifier. Defaults to `"gateway"` if omitted. |

**Response** `200 OK`

```json
{
  "content": "I can help you with…"
}
```

**Error Codes**

| Status | Body | Condition |
|---|---|---|
| `400` | `{"error":"missing 'message' field"}` | Request body missing or lacks `message` key |
| `403` | `{"error":"forbidden"}` | Request not from `127.0.0.1` |
| `500` | `{"error":"<detail>"}` | Agent processing failed |

**Example**

```bash
curl -X POST http://127.0.0.1:8080/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"Summarise today'"'"'s alerts","session_id":"ops-1"}'
```

---

### POST /api/chat/stream

SSE streaming chat completion. Same request format as `/api/chat` but returns a `text/event-stream` response. **Localhost only.**

> **Note:** The current implementation builds the full SSE payload in memory
> and returns it as a single HTTP response with the `text/event-stream`
> content type. True chunked streaming is a planned future enhancement.

**Request Body**

Same as [POST /api/chat](#post-apichat).

```json
{
  "message": "Explain this error log",
  "session_id": "debug-42"
}
```

**Response** `200 OK` — `text/event-stream`

See [SSE Stream Format](#sse-stream-format) below.

**Error Codes**

| Status | Body | Condition |
|---|---|---|
| `400` | `{"error":"missing 'message' field"}` | Request body missing or lacks `message` key |
| `403` | `{"error":"forbidden"}` | Request not from `127.0.0.1` |

**Example**

```bash
curl -N -X POST http://127.0.0.1:8080/api/chat/stream \
  -H "Content-Type: application/json" \
  -d '{"message":"What is VeriClaw?"}'
```

---

### POST /webhook/telegram

Receives incoming Telegram Bot API webhook updates. The server processes the
message through the agent loop and sends the reply back via the Telegram
`sendMessage` API using the configured bot token.

**Request Body** — Standard [Telegram Update](https://core.telegram.org/bots/api#update) JSON object as forwarded by Telegram.

**Response** `200 OK`

```json
{
  "ok": true
}
```

**Example**

```bash
curl -X POST http://127.0.0.1:8080/webhook/telegram \
  -H "Content-Type: application/json" \
  -d '{"update_id":123,"message":{"message_id":1,"chat":{"id":456},"text":"hi"}}'
```

---

### POST /webhook/signal

Receives incoming messages from signal-cli's push/webhook mode. The server
processes the message through the agent loop and replies via the Signal bridge.

**Request Body** — signal-cli JSON envelope containing an `envelope` object
with `source` (sender number) and message data.

**Response** `200 OK`

```json
{
  "ok": true
}
```

**Example**

```bash
curl -X POST http://127.0.0.1:8080/webhook/signal \
  -H "Content-Type: application/json" \
  -d '{"envelope":{"source":"+1234567890","dataMessage":{"message":"hello"}}}'
```

---

## Error Handling

All error responses use a consistent JSON envelope:

```json
{
  "error": "<human-readable message>"
}
```

### Standard Error Codes

| HTTP Status | Meaning | When |
|---|---|---|
| `400 Bad Request` | Malformed or missing required fields | Invalid JSON or missing `message` on chat endpoints |
| `403 Forbidden` | Access denied | Non-localhost request to a protected endpoint |
| `404 Not Found` | Unknown route | Request to an undefined URI |
| `500 Internal Server Error` | Server-side failure | Agent loop error during chat processing |

Any unmatched URI/method combination returns:

```json
HTTP/1.1 404 Not Found

{"error":"not found"}
```

---

## SSE Stream Format

The `/api/chat/stream` endpoint returns a `text/event-stream` response using
the [Server-Sent Events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events) protocol.

### Successful response

Each content chunk is delivered as a `data:` line containing a JSON object,
followed by a `[DONE]` sentinel:

```
data: {"content":"The full agent reply text goes here…"}

data: [DONE]

```

- Each `data:` line is followed by **two newlines** (`\n\n`) as per the SSE specification.
- The `content` field contains the agent's response text.
- `[DONE]` signals that the stream is complete and the client should close the connection.

### Error response

If the agent fails, a single error event is emitted (no `[DONE]` sentinel):

```
data: {"error":"description of what went wrong"}

```

### Parsing example (JavaScript)

```javascript
const res = await fetch("http://127.0.0.1:8080/api/chat/stream", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ message: "hello" }),
});

const reader = res.body.getReader();
const decoder = new TextDecoder();
let buffer = "";

while (true) {
  const { done, value } = await reader.read();
  if (done) break;
  buffer += decoder.decode(value, { stream: true });

  const lines = buffer.split("\n");
  buffer = lines.pop(); // keep incomplete line in buffer

  for (const line of lines) {
    if (line.startsWith("data: ")) {
      const payload = line.slice(6);
      if (payload === "[DONE]") {
        console.log("Stream complete");
      } else {
        const json = JSON.parse(payload);
        if (json.error) console.error(json.error);
        else process.stdout.write(json.content);
      }
    }
  }
}
```
