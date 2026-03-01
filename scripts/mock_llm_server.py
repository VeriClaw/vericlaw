#!/usr/bin/env python3
"""Minimal OpenAI-compatible mock server for integration testing.
Supports both streaming (SSE) and non-streaming responses.
Usage: python3 scripts/mock_llm_server.py [port]
"""
import http.server
import json
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 11434

CONTENT = "Hello from mock LLM"

CANNED_NON_STREAMING = json.dumps({
    "id": "chatcmpl-test",
    "choices": [{
        "message": {"role": "assistant", "content": CONTENT},
        "finish_reason": "stop",
        "index": 0
    }]
}).encode()


def make_sse_response(content):
    """Generate SSE (streaming) response bytes."""
    lines = []
    lines.append("data: " + json.dumps({
        "id": "chatcmpl-test",
        "choices": [{"delta": {"role": "assistant", "content": ""}, "index": 0, "finish_reason": None}]
    }) + "\n\n")
    lines.append("data: " + json.dumps({
        "id": "chatcmpl-test",
        "choices": [{"delta": {"content": content}, "index": 0, "finish_reason": None}]
    }) + "\n\n")
    lines.append("data: " + json.dumps({
        "id": "chatcmpl-test",
        "choices": [{"delta": {}, "index": 0, "finish_reason": "stop"}]
    }) + "\n\n")
    lines.append("data: [DONE]\n\n")
    return "".join(lines).encode()


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # suppress access log

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        try:
            req = json.loads(body)
            streaming = req.get("stream", False)
        except Exception:
            streaming = False

        if streaming:
            data = make_sse_response(CONTENT)
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(CANNED_NON_STREAMING)


if __name__ == "__main__":
    server = http.server.HTTPServer(("127.0.0.1", PORT), Handler)
    server.serve_forever()
