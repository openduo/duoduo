#!/usr/bin/env python3
"""Lightweight HTTP API for saving files from the dashboard.

Runs on the host (not in container). Since aladuo/ and .aladuo/ are
bind-mounted, writes are immediately visible inside the container.

Usage:
    python3 scripts/save-api.py          # foreground
    python3 scripts/save-api.py &        # background

Listens on 127.0.0.1:20234. Only writes to approved path prefixes.
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import os

ALLOWED_PREFIXES = [
    os.path.expanduser("~/ENG/openduo/openduo/aladuo/config/"),
    os.path.expanduser("~/ENG/openduo/openduo/aladuo/memory/entities/"),
    os.path.expanduser("~/ENG/openduo/openduo/.aladuo/var/channels/"),
]

CHANNELS_DIR = os.path.expanduser("~/ENG/openduo/openduo/.aladuo/var/channels/")

class Handler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if self.path == "/channels":
            # List channel directories (feishu-oc_xxx...)
            dirs = []
            if os.path.isdir(CHANNELS_DIR):
                for name in sorted(os.listdir(CHANNELS_DIR)):
                    if name.startswith("feishu-oc_") and os.path.isdir(os.path.join(CHANNELS_DIR, name)):
                        dirs.append(name.replace("feishu-", ""))
            self.send_response(200)
            self._cors()
            self.end_headers()
            self.wfile.write(json.dumps({"channels": dirs}).encode())
        else:
            self.send_response(404)
            self._cors()
            self.end_headers()
            self.wfile.write(b'{"error":"not found"}')

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length))
        path = body.get("path", "")
        content = body.get("content", "")

        # Resolve symlinks / relative components
        path = os.path.realpath(path)

        if not any(path.startswith(p) for p in ALLOWED_PREFIXES):
            self.send_response(403)
            self._cors()
            self.end_headers()
            self.wfile.write(json.dumps({"error": "forbidden path"}).encode())
            return

        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)

        self.send_response(200)
        self._cors()
        self.end_headers()
        self.wfile.write(json.dumps({"ok": True}).encode())

    def _cors(self):
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def log_message(self, fmt, *args):
        print(f"[save-api] {args[0]}")

if __name__ == "__main__":
    addr = ("127.0.0.1", 20234)
    print(f"[save-api] listening on {addr[0]}:{addr[1]}")
    print(f"[save-api] allowed prefixes: {ALLOWED_PREFIXES}")
    HTTPServer(addr, Handler).serve_forever()
