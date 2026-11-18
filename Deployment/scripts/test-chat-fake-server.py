#!/usr/bin/env python3
"""Black-box tests for the loopback ChatServer fault-injection fixture."""
from __future__ import annotations

import json
import socket
import subprocess
import sys
import time
import unittest
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from http.client import RemoteDisconnected

SCRIPT = Path(__file__).with_name("chat-fake-server.py")


class FakeChatServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            cls.port = sock.getsockname()[1]
        cls.base = f"http://127.0.0.1:{cls.port}"
        cls.process = subprocess.Popen(
            [sys.executable, str(SCRIPT), "--host", "127.0.0.1", "--port", str(cls.port)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                with urlopen(cls.base + "/health", timeout=0.2) as response:
                    if response.status == 200:
                        return
            except (OSError, URLError):
                time.sleep(0.05)
        cls.process.terminate()
        raise RuntimeError("fake ChatServer did not start")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.process.terminate()
        try:
            cls.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            cls.process.kill()
            cls.process.wait(timeout=3)

    def configure(self, code: int = 201, delay_ms: int = 0, drop: bool = False) -> None:
        url = f"{self.base}/__admin/status?code={code}&delay_ms={delay_ms}&drop={int(drop)}"
        with urlopen(url, timeout=2) as response:
            self.assertEqual(response.status, 200)

    def post_message(self, client_id: str, timeout: float = 2) -> dict:
        body = json.dumps({"client_message_id": client_id, "content": "test"}).encode()
        request = Request(
            self.base + "/api/v1/servers/chat/messages",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(request, timeout=timeout) as response:
            return json.loads(response.read())

    def test_success_is_idempotent_by_client_message_id(self) -> None:
        self.configure()
        first = self.post_message("stable-id-1")
        second = self.post_message("stable-id-1")
        self.assertEqual(first["message"]["id"], second["message"]["id"])

    def test_http_error_responses_are_injectable(self) -> None:
        for code in (401, 429, 503):
            with self.subTest(code=code):
                self.configure(code=code)
                with self.assertRaises(HTTPError) as caught:
                    self.post_message(f"status-{code}")
                self.assertEqual(caught.exception.code, code)

    def test_slow_response_can_trigger_client_timeout(self) -> None:
        self.configure(delay_ms=300)
        with self.assertRaises((TimeoutError, URLError)):
            self.post_message("timeout-id", timeout=0.05)

    def test_server_can_drop_connection_without_http_response(self) -> None:
        self.configure(drop=True)
        with self.assertRaises((RemoteDisconnected, URLError, OSError)):
            self.post_message("dropped-id")

    def test_invalid_control_values_are_rejected(self) -> None:
        with self.assertRaises(HTTPError) as caught:
            urlopen(self.base + "/__admin/status?code=2000", timeout=2)
        self.assertEqual(caught.exception.code, 400)


if __name__ == "__main__":
    unittest.main(verbosity=2)
