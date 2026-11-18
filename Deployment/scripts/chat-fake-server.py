#!/usr/bin/env python3
"""Local-only fake ChatServer for WorldServer nearby-chat reliability checks.

Binds to 127.0.0.1 by default. It never persists message bodies.
"""
from __future__ import annotations

import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


class State:
    status = 201
    accepted: dict[str, str] = {}
    requests = 0
    delay_ms = 0
    drop_connection = False


class Handler(BaseHTTPRequestHandler):
    server_version = "HongHuangChatMock/1.0"

    def _json(self, status: int, value: dict) -> None:
        payload = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json(200, {"status": "ok", "mock": True})
            return
        if parsed.path == "/__admin/status":
            params = parse_qs(parsed.query)
            try:
                code = int(params.get("code", ["201"])[0])
            except ValueError:
                self._json(400, {"error": "code must be an integer"})
                return
            if code not in (201, 400, 401, 403, 404, 408, 409, 425, 429, 500, 502, 503, 504):
                self._json(400, {"error": "unsupported status code"})
                return
            try:
                delay_ms = int(params.get("delay_ms", ["0"])[0])
            except ValueError:
                self._json(400, {"error": "delay_ms must be an integer"})
                return
            if delay_ms < 0 or delay_ms > 30000:
                self._json(400, {"error": "delay_ms must be between 0 and 30000"})
                return
            State.status = code
            State.delay_ms = delay_ms
            State.drop_connection = params.get("drop", ["0"])[0] == "1"
            self._json(200, {
                "status": State.status,
                "delay_ms": State.delay_ms,
                "drop_connection": State.drop_connection,
            })
            return
        if parsed.path == "/__admin/stats":
            self._json(200, {
                "status": State.status,
                "requests": State.requests,
                "unique_messages": len(State.accepted),
            })
            return
        self._json(404, {"error": "not found"})

    def do_POST(self) -> None:
        if urlparse(self.path).path != "/api/v1/servers/chat/messages":
            self._json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 65536:
                self._json(413, {"error": "invalid request size"})
                return
            body = json.loads(self.rfile.read(length))
            client_id = str(body.get("client_message_id", "")).strip()
            if not client_id:
                self._json(400, {"error": "client_message_id required"})
                return
        except (ValueError, json.JSONDecodeError):
            self._json(400, {"error": "invalid JSON"})
            return

        State.requests += 1
        if State.delay_ms:
            time.sleep(State.delay_ms / 1000.0)
        if State.drop_connection:
            self.close_connection = True
            self.connection.shutdown(1)
            self.connection.close()
            return
        if State.status != 201:
            self._json(State.status, {"error": "mock ChatServer rejection"})
            return

        message_id = State.accepted.setdefault(client_id, "mock-" + client_id)
        self._json(201, {"message": {"id": message_id}})

    def log_message(self, fmt: str, *args) -> None:
        # Avoid logging chat text or authorization headers.
        print("[chat-mock]", fmt % args, flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8788)
    args = parser.parse_args()
    if args.host not in ("127.0.0.1", "localhost", "::1"):
        parser.error("the mock server must bind to loopback only")
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Fake ChatServer listening on http://{args.host}:{args.port}", flush=True)
    print("Configure: GET /__admin/status?code=503&delay_ms=0&drop=0", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
