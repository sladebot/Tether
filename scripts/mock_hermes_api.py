#!/usr/bin/env python3
"""Small Hermes API Server protocol fixture for HermesLink end-to-end testing."""

from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


HOST = os.environ.get("MOCK_HERMES_HOST", "0.0.0.0")
PORT = int(os.environ.get("MOCK_HERMES_PORT", "8642"))
KEY = os.environ.get("MOCK_HERMES_KEY", "test-key")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args: object) -> None:
        print(f"[mock-hermes] {self.address_string()} {format % args}", flush=True)

    def do_GET(self) -> None:
        if self.path in ("/health", "/v1/health"):
            self._json(200, {"status": "ok"})
            return
        if not self._authorized():
            return
        if self.path == "/v1/capabilities":
            self._json(
                200,
                {
                    "object": "hermes.api_server.capabilities",
                    "platform": "hermes-agent",
                    "model": "hermes-agent",
                    "auth": {"type": "bearer", "required": True},
                    "features": {"chat_completions": True},
                },
            )
            return
        if self.path == "/v1/models":
            self._json(200, {"object": "list", "data": [{"id": "hermes-agent"}]})
            return
        self._json(404, {"detail": "Not found"})

    def do_POST(self) -> None:
        if not self._authorized():
            return
        if self.path != "/v1/chat/completions":
            self._json(404, {"detail": "Not found"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            request = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._json(400, {"detail": "Invalid JSON"})
            return
        messages = request.get("messages", [])
        prompt = str(messages[-1].get("content", "")) if messages else ""
        if "Mini App Builder" in prompt:
            output = (
                "<!DOCTYPE html><html><head><meta name=\"viewport\" "
                "content=\"width=device-width,initial-scale=1\"><title>Test App</title>"
                "<style>body{font:17px system-ui;padding:24px}button{font:inherit;padding:12px}</style>"
                "</head><body><h1>HermesLink Test</h1><button onclick=\"this.textContent++\">0</button>"
                "</body></html>"
            )
        else:
            output = f"Hermes API Server received: {prompt}"
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        for piece in (output[index : index + 32] for index in range(0, len(output), 32)):
            event = {"choices": [{"delta": {"content": piece}}]}
            self.wfile.write(f"data: {json.dumps(event)}\n\n".encode())
            self.wfile.flush()
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()
        self.close_connection = True

    def _authorized(self) -> bool:
        if self.headers.get("Authorization") == f"Bearer {KEY}":
            return True
        self._json(401, {"detail": "Invalid API key"})
        return False

    def _json(self, status: int, payload: dict[str, object]) -> None:
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    print(f"Mock Hermes API Server listening on http://{HOST}:{PORT}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
