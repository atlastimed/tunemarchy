"""A one-shot loopback listener for Spotify's sign-in redirect.

It binds 127.0.0.1 only, answers exactly one request to /callback whose
``state`` matches, and stops. Anything else gets a 404.
"""

from __future__ import annotations

import errno
import html
import http.server
import threading
import time
import urllib.parse
from dataclasses import dataclass

PAGE = """<!doctype html><meta charset="utf-8"><title>Tunemarchy</title>
<style>body{{font:16px system-ui,sans-serif;margin:15vh auto;max-width:28em;padding:0 1em;
color:#ddd;background:#111}}</style>
<h1>{title}</h1><p>{body}</p>"""


class PortBusy(RuntimeError):
    pass


class CallbackTimeout(RuntimeError):
    pass


@dataclass
class Result:
    code: str | None = None
    error: str | None = None


def _page(title: str, body: str) -> bytes:
    return PAGE.format(title=html.escape(title), body=html.escape(body)).encode("utf-8")


def wait_for_code(port: int, state: str, timeout: float, on_ready=None) -> str:
    """Serve until Spotify redirects back, then return the authorization code."""
    result = Result()
    done = threading.Event()

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args) -> None:  # keep stderr for our own messages
            pass

        def do_GET(self) -> None:
            url = urllib.parse.urlsplit(self.path)
            params = urllib.parse.parse_qs(url.query)
            if url.path != "/callback" or params.get("state", [""])[0] != state:
                self._reply(404, _page("Not found", "This address only accepts Tunemarchy's sign-in."))
                return
            if "error" in params:
                result.error = params["error"][0][:100]
                self._reply(
                    200, _page("Sign-in cancelled", "Spotify did not grant access. You can close this tab.")
                )
            elif params.get("code", [""])[0]:
                result.code = params["code"][0]
                self._reply(
                    200, _page("Signed in", "Tunemarchy is connected to Spotify. You can close this tab.")
                )
            else:
                self._reply(400, _page("Something went wrong", "Spotify sent no code. Try signing in again."))
                return
            done.set()

        def _reply(self, status: int, body: bytes) -> None:
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

    try:
        server = http.server.HTTPServer(("127.0.0.1", port), Handler)
    except OSError as exc:
        if exc.errno == errno.EADDRINUSE:
            raise PortBusy(
                f"Port {port} is in use by another program, so Spotify cannot hand the sign-in back. "
                "Close that program and try again."
            ) from exc
        raise
    server.timeout = 0.5
    try:
        if on_ready:
            on_ready()
        deadline = time.monotonic() + timeout
        while not done.is_set():
            server.handle_request()
            if time.monotonic() >= deadline and not done.is_set():
                raise CallbackTimeout("Timed out waiting for the browser sign-in")
    finally:
        server.server_close()
    if result.error:
        raise PermissionError(result.error)
    return str(result.code)
