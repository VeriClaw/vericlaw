#!/usr/bin/env python3
"""Minimal OpenAI-compatible mock server for integration testing.
Responds to any POST with a canned assistant message.
Usage: python3 scripts/mock_llm_server.py [port]
"""
import http.server
import json
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 11434

CANNED = json.dumps({
    "choices": [{
        "message": {"role": "assistant", "content": "Hello from mock LLM"}
    }]
}).encode()


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # suppress access log

    def do_POST(self):
        # Drain request body
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(CANNED)


if __name__ == "__main__":
    server = http.server.HTTPServer(("127.0.0.1", PORT), Handler)
    server.serve_forever()
