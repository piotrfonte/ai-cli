#!/usr/bin/env python3
"""Stub OpenAI-compatible server on :1234 — records the request body opencode sends."""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

OUT = "/private/tmp/claude-501/-Users-p-Development-ai-cli/aa892a00-453c-4473-930b-8778a9ea29eb/scratchpad/wire.json"


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path.endswith("/models"):
            body = json.dumps({"object": "list", "data": [
                {"id": "zai-org/glm-4.7-flash", "object": "model"},
                {"id": "prism-ml/bonsai-27b", "object": "model"},
            ]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n)
        with open(OUT, "wb") as f:
            f.write(raw)
        print("RECORDED", self.path, len(raw), "bytes", flush=True)

        chunks = [
            {"id": "1", "object": "chat.completion.chunk", "created": 0,
             "model": "stub",
             "choices": [{"index": 0, "delta": {"role": "assistant", "content": "OK"},
                          "finish_reason": None}]},
            {"id": "1", "object": "chat.completion.chunk", "created": 0,
             "model": "stub",
             "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
             "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}},
        ]
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for c in chunks:
            self.wfile.write(b"data: " + json.dumps(c).encode() + b"\n\n")
            self.wfile.flush()
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


HTTPServer(("127.0.0.1", 1234), H).serve_forever()
