"""Tests for the sign-in helper. Standard library only, so they run with
``python3 -m unittest`` on a stock system and under pytest in CI."""

from __future__ import annotations

import contextlib
import io
import json
import os
import socket
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "backend"))

from tunemarchy import callback, cli, spotify  # noqa: E402
from tunemarchy.keyring import KeyringError  # noqa: E402

CLIENT = "0123456789abcdef0123456789abcdef"


class FakeKeyring:
    def __init__(self, stored: str | None = None, fail_set: bool = False, fail_get: bool = False):
        self.items: dict[str, str] = {CLIENT: stored} if stored else {}
        self.fail_set = fail_set
        self.fail_get = fail_get

    def get(self, client_id):
        if self.fail_get:
            raise KeyringError("locked")
        return self.items.get(client_id)

    def set(self, client_id, value):
        if self.fail_set:
            raise KeyringError("refused")
        self.items[client_id] = value

    def delete(self, client_id):
        self.items.pop(client_id, None)


class FakePoster:
    def __init__(self, *responses):
        self.responses = list(responses)
        self.calls: list[tuple[str, dict]] = []

    def __call__(self, url, form):
        self.calls.append((url, form))
        result = self.responses.pop(0)
        if isinstance(result, Exception):
            raise result
        return result


def token_body(access="at", refresh=None, expires=3600):
    body = {"access_token": access, "token_type": "Bearer", "expires_in": expires}
    if refresh:
        body["refresh_token"] = refresh
    return json.dumps(body)


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def run(argv, keyring, post):
    out = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
        code = cli.main(argv, keyring=keyring, post=post)
    lines = [line for line in out.getvalue().splitlines() if line.strip()]
    return code, json.loads(lines[-1]) if lines else None, len(lines)


class HelperTestCase(unittest.TestCase):
    def setUp(self):
        self.runtime = tempfile.TemporaryDirectory()
        patcher = mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": self.runtime.name})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self.runtime.cleanup)


class TokenTests(HelperTestCase):
    def test_refresh_returns_token_and_stores_rotated_refresh_token(self):
        keyring = FakeKeyring("old")
        post = FakePoster((200, token_body("fresh", refresh="new", expires=3600)))
        code, payload, lines = run(["token", "--client-id", CLIENT], keyring, post)
        self.assertEqual(code, cli.EXIT_OK)
        self.assertEqual(lines, 1)
        self.assertEqual(payload, {"ok": True, "accessToken": "fresh", "expiresIn": 3600})
        self.assertEqual(keyring.items[CLIENT], "new")
        url, form = post.calls[0]
        self.assertEqual(url, spotify.TOKEN_URL)
        self.assertEqual(form, {"grant_type": "refresh_token", "refresh_token": "old", "client_id": CLIENT})

    def test_refresh_without_rotation_keeps_the_stored_token(self):
        keyring = FakeKeyring("old")
        code, payload, _ = run(["token", "--client-id", CLIENT], keyring, FakePoster((200, token_body())))
        self.assertEqual(code, cli.EXIT_OK)
        self.assertEqual(keyring.items[CLIENT], "old")

    def test_no_stored_sign_in_is_signed_out(self):
        code, payload, _ = run(["token", "--client-id", CLIENT], FakeKeyring(), FakePoster())
        self.assertEqual(code, cli.EXIT_SIGNED_OUT)
        self.assertEqual(payload["error"], "signed-out")

    def test_invalid_grant_forgets_the_sign_in(self):
        keyring = FakeKeyring("old")
        post = FakePoster((400, '{"error":"invalid_grant","error_description":"Refresh token revoked"}'))
        code, payload, _ = run(["token", "--client-id", CLIENT], keyring, post)
        self.assertEqual(code, cli.EXIT_SIGNED_OUT)
        self.assertIn("revoked", payload["message"])
        self.assertNotIn(CLIENT, keyring.items)

    def test_network_failure_keeps_the_sign_in(self):
        keyring = FakeKeyring("old")
        post = FakePoster(spotify.NetworkError("Could not reach Spotify: URLError"))
        code, payload, _ = run(["token", "--client-id", CLIENT], keyring, post)
        self.assertEqual(code, cli.EXIT_OFFLINE)
        self.assertEqual(payload["error"], "offline")
        self.assertEqual(keyring.items[CLIENT], "old")

    def test_server_error_keeps_the_sign_in(self):
        keyring = FakeKeyring("old")
        code, payload, _ = run(
            ["token", "--client-id", CLIENT], keyring, FakePoster((503, "<html>busy</html>"))
        )
        self.assertEqual(code, cli.EXIT_OFFLINE)
        self.assertEqual(keyring.items[CLIENT], "old")

    def test_unknown_error_keeps_the_sign_in(self):
        keyring = FakeKeyring("old")
        code, payload, _ = run(
            ["token", "--client-id", CLIENT], keyring, FakePoster((400, '{"error":"weird"}'))
        )
        self.assertEqual(code, cli.EXIT_ERROR)
        self.assertEqual(keyring.items[CLIENT], "old")

    def test_keyring_refusing_the_rotated_token_still_returns_access(self):
        keyring = FakeKeyring("old")
        keyring.fail_set = True
        code, payload, _ = run(
            ["token", "--client-id", CLIENT], keyring, FakePoster((200, token_body(refresh="new")))
        )
        self.assertEqual(code, cli.EXIT_OK)
        self.assertTrue(payload["accessToken"])
        self.assertIn("warning", payload)

    def test_locked_keyring(self):
        code, payload, _ = run(["token", "--client-id", CLIENT], FakeKeyring(fail_get=True), FakePoster())
        self.assertEqual(code, cli.EXIT_KEYRING)

    def test_client_id_is_validated_and_normalised(self):
        code, payload, _ = run(["token", "--client-id", "nope"], FakeKeyring(), FakePoster())
        self.assertEqual(code, cli.EXIT_ERROR)
        self.assertEqual(payload["error"], "client-id")
        keyring = FakeKeyring("old")
        code, _, _ = run(["token", "--client-id", CLIENT.upper()], keyring, FakePoster((200, token_body())))
        self.assertEqual(code, cli.EXIT_OK)


class StatusAndLogoutTests(HelperTestCase):
    def test_status(self):
        _, payload, _ = run(["status", "--client-id", CLIENT], FakeKeyring("x"), FakePoster())
        self.assertEqual(payload, {"ok": True, "signedIn": True})
        _, payload, _ = run(["status", "--client-id", CLIENT], FakeKeyring(), FakePoster())
        self.assertEqual(payload, {"ok": True, "signedIn": False})

    def test_logout_clears(self):
        keyring = FakeKeyring("x")
        code, payload, _ = run(["logout", "--client-id", CLIENT], keyring, FakePoster())
        self.assertEqual(code, cli.EXIT_OK)
        self.assertEqual(keyring.items, {})


class PkceTests(unittest.TestCase):
    def test_challenge_is_unpadded_base64url_sha256(self):
        # Expected value from: printf %s VERIFIER | openssl dgst -sha256 -binary | base64url
        verifier = "dBjftJeZ4CVP-mJ92K27uhbUJU1p1r_wW1gFWFOEjXk"
        self.assertEqual(spotify.challenge_for(verifier), "ngF5GsXcbwljx6u133FFr3Xht9xooA_DuaX_3QwODtc")

    def test_verifier_length(self):
        self.assertTrue(43 <= len(spotify.make_verifier()) <= 128)

    def test_authorize_url(self):
        url = urllib.parse.urlsplit(spotify.authorize_url(CLIENT, "st", "ch"))
        query = dict(urllib.parse.parse_qsl(url.query))
        self.assertEqual(url.netloc, "accounts.spotify.com")
        self.assertEqual(query["redirect_uri"], "http://127.0.0.1:43117/callback")
        self.assertEqual(query["code_challenge_method"], "S256")
        self.assertEqual(query["state"], "st")
        self.assertIn("user-library-modify", query["scope"].split())


def visit(url):
    try:
        with urllib.request.urlopen(url, timeout=5) as response:  # noqa: S310 - loopback test server
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code


class LoginTests(HelperTestCase):
    def setUp(self):
        super().setUp()
        self.port = free_port()
        patcher = mock.patch.object(spotify, "CALLBACK_PORT", self.port)
        patcher.start()
        self.addCleanup(patcher.stop)

    def browser_that_redirects(self, *, code="authcode", error=None, tamper_state=False, probes=()):
        statuses = []

        def browser(url):
            state = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(url).query))["state"]

            def go():
                for path in probes:
                    statuses.append(visit(f"http://127.0.0.1:{self.port}{path}"))
                params = {"state": "forged" if tamper_state else state}
                if error:
                    params["error"] = error
                else:
                    params["code"] = code
                statuses.append(
                    visit(f"http://127.0.0.1:{self.port}/callback?{urllib.parse.urlencode(params)}")
                )
                if tamper_state:  # the real redirect still arrives afterwards
                    params["state"] = state
                    statuses.append(
                        visit(f"http://127.0.0.1:{self.port}/callback?{urllib.parse.urlencode(params)}")
                    )

            threading.Thread(target=go, daemon=True).start()

        return browser, statuses

    def login(self, keyring, post, browser):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            code = cli.cmd_login(CLIENT, keyring, post, browser=browser)
        return code, json.loads(out.getvalue().strip().splitlines()[-1])

    def test_login_exchanges_the_code_and_stores_the_refresh_token(self):
        keyring = FakeKeyring()
        post = FakePoster((200, token_body("at", refresh="rt")))
        browser, statuses = self.browser_that_redirects(probes=("/favicon.ico",))
        code, payload = self.login(keyring, post, browser)
        self.assertEqual(code, cli.EXIT_OK)
        self.assertEqual(payload["accessToken"], "at")
        self.assertEqual(keyring.items[CLIENT], "rt")
        self.assertEqual(statuses, [404, 200])
        form = post.calls[0][1]
        self.assertEqual(form["grant_type"], "authorization_code")
        self.assertEqual(form["code"], "authcode")
        self.assertTrue(form["code_verifier"])

    def test_a_forged_state_is_ignored(self):
        keyring = FakeKeyring()
        browser, statuses = self.browser_that_redirects(tamper_state=True)
        code, _ = self.login(keyring, FakePoster((200, token_body(refresh="rt"))), browser)
        self.assertEqual(code, cli.EXIT_OK)
        self.assertEqual(statuses, [404, 200])

    def test_denied_consent(self):
        browser, _ = self.browser_that_redirects(error="access_denied")
        code, payload = self.login(FakeKeyring(), FakePoster(), browser)
        self.assertEqual(code, cli.EXIT_CANCELLED)
        self.assertEqual(payload["error"], "denied")

    def test_port_in_use_is_reported_clearly(self):
        with socket.socket() as blocker:
            blocker.bind(("127.0.0.1", self.port))
            blocker.listen()
            code, payload = self.login(FakeKeyring(), FakePoster(), browser=lambda url: None)
        self.assertEqual(code, cli.EXIT_PORT)
        self.assertIn(str(self.port), payload["message"])

    def test_timeout(self):
        with mock.patch.object(cli, "LOGIN_TIMEOUT", 0.6):
            code, payload = self.login(FakeKeyring(), FakePoster(), browser=lambda url: None)
        self.assertEqual(code, cli.EXIT_CANCELLED)
        self.assertEqual(payload["error"], "timeout")

    def test_keyring_failure_after_login_still_signs_in_for_now(self):
        keyring = FakeKeyring(fail_set=True)
        browser, _ = self.browser_that_redirects()
        code, payload = self.login(keyring, FakePoster((200, token_body(refresh="rt"))), browser)
        self.assertEqual(code, cli.EXIT_OK)
        self.assertIn("warning", payload)


class CallbackTests(unittest.TestCase):
    def test_wait_for_code_rejects_other_paths(self):
        port = free_port()
        statuses = []
        visits = []

        def ready():
            def go():
                statuses.append(visit(f"http://127.0.0.1:{port}/other?state=s&code=c"))
                statuses.append(visit(f"http://127.0.0.1:{port}/callback?state=s"))
                statuses.append(visit(f"http://127.0.0.1:{port}/callback?state=s&code=c"))

            visits.append(threading.Thread(target=go, daemon=True))
            visits[0].start()

        self.assertEqual(callback.wait_for_code(port, "s", 10, on_ready=ready), "c")
        # The server answers the last visit before the client has read the
        # response: wait for the client to record it.
        visits[0].join(5)
        self.assertEqual(statuses, [404, 400, 200])


if __name__ == "__main__":
    unittest.main()
