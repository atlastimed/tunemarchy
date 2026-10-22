"""Command line for the shell service.

Every command prints exactly one JSON object on stdout, which the QML
service parses; human-readable detail goes to stderr. Exit codes:

  0 ok, 1 error, 2 signed out, 3 offline, 4 keyring, 5 port busy, 6 cancelled
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
from collections.abc import Iterator
from pathlib import Path

from . import __version__, callback, spotify
from .keyring import KeyringError, SecretTool

EXIT_OK, EXIT_ERROR, EXIT_SIGNED_OUT, EXIT_OFFLINE, EXIT_KEYRING, EXIT_PORT, EXIT_CANCELLED = range(7)
CLIENT_ID = re.compile(r"^[0-9a-f]{32}$")
LOGIN_TIMEOUT = 300.0


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def fail(code: int, kind: str, message: str) -> int:
    print(f"tunemarchy: {message}", file=sys.stderr)
    emit({"ok": False, "error": kind, "message": message})
    return code


def token_payload(tokens: spotify.Tokens, warning: str | None = None) -> dict:
    payload = {"ok": True, "accessToken": tokens.access_token, "expiresIn": tokens.expires_in}
    if warning:
        payload["warning"] = warning
    return payload


@contextlib.contextmanager
def refresh_lock() -> Iterator[None]:
    """Serialise refreshes: refresh tokens rotate, so two overlapping
    refreshes could each spend the same token and lose the sign-in."""
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/tunemarchy-{os.getuid()}"  # noqa: S108
    Path(base).mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(os.path.join(base, "tunemarchy.lock"), os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def open_browser(url: str) -> None:
    opener = shutil.which("xdg-open")
    print(f"Open this address to sign in to Spotify:\n  {url}", file=sys.stderr)
    if opener:
        subprocess.Popen(  # noqa: S603 - fixed argv, no shell
            [opener, url], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )


def cmd_login(client_id: str, keyring: SecretTool, post: spotify.Poster, browser=open_browser) -> int:
    verifier = spotify.make_verifier()
    state = secrets.token_urlsafe(24)
    url = spotify.authorize_url(client_id, state, spotify.challenge_for(verifier))
    try:
        code = callback.wait_for_code(
            spotify.CALLBACK_PORT, state, LOGIN_TIMEOUT, on_ready=lambda: browser(url)
        )
    except callback.PortBusy as exc:
        return fail(EXIT_PORT, "port-busy", str(exc))
    except callback.CallbackTimeout as exc:
        return fail(EXIT_CANCELLED, "timeout", str(exc))
    except PermissionError as exc:
        return fail(EXIT_CANCELLED, "denied", f"Spotify sign-in was not approved ({exc})")
    try:
        tokens = spotify.exchange_code(client_id, code, verifier, post)
    except spotify.NetworkError as exc:
        return fail(EXIT_OFFLINE, "offline", str(exc))
    except spotify.SpotifyError as exc:
        return fail(EXIT_ERROR, "spotify", f"Spotify refused the sign-in: {exc}")
    with refresh_lock():
        try:
            keyring.set(client_id, str(tokens.refresh_token))
        except KeyringError as exc:
            # Still usable for this session; it just will not survive a restart.
            emit(token_payload(tokens, warning=f"Signed in, but the keyring would not save it: {exc}"))
            return EXIT_OK
    emit(token_payload(tokens))
    return EXIT_OK


def cmd_token(client_id: str, keyring: SecretTool, post: spotify.Poster) -> int:
    with refresh_lock():
        try:
            stored = keyring.get(client_id)
        except KeyringError as exc:
            return fail(EXIT_KEYRING, "keyring", str(exc))
        if not stored:
            return fail(EXIT_SIGNED_OUT, "signed-out", "Not signed in to Spotify")
        try:
            tokens = spotify.refresh(client_id, stored, post)
        except spotify.SignedOut as exc:
            # Spotify said the grant is gone (revoked, expired after six
            # months, or a different app). Forget it so the UI offers sign-in.
            with contextlib.suppress(KeyringError):
                keyring.delete(client_id)
            return fail(EXIT_SIGNED_OUT, "signed-out", f"Spotify sign-in expired: {exc}")
        except spotify.NetworkError as exc:
            return fail(EXIT_OFFLINE, "offline", str(exc))
        except spotify.SpotifyError as exc:
            return fail(EXIT_ERROR, "spotify", str(exc))
        warning = None
        if tokens.refresh_token and tokens.refresh_token != stored:
            try:
                keyring.set(client_id, tokens.refresh_token)
            except KeyringError as exc:
                warning = f"Could not save Spotify's new refresh token: {exc}"
    emit(token_payload(tokens, warning))
    return EXIT_OK


def cmd_logout(client_id: str, keyring: SecretTool) -> int:
    try:
        keyring.delete(client_id)
    except KeyringError as exc:
        return fail(EXIT_KEYRING, "keyring", str(exc))
    emit({"ok": True})
    return EXIT_OK


def cmd_status(client_id: str, keyring: SecretTool) -> int:
    try:
        signed_in = keyring.get(client_id) is not None
    except KeyringError as exc:
        return fail(EXIT_KEYRING, "keyring", str(exc))
    emit({"ok": True, "signedIn": signed_in})
    return EXIT_OK


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="tunemarchyctl", description="Spotify sign-in for Tunemarchy")
    p.add_argument("--version", action="version", version=f"tunemarchy {__version__}")
    sub = p.add_subparsers(dest="command", required=True)
    for name, text in (
        ("login", "sign in through the browser"),
        ("token", "print a fresh access token"),
        ("logout", "forget the stored sign-in"),
        ("status", "report whether a sign-in is stored"),
    ):
        cmd = sub.add_parser(name, help=text)
        cmd.add_argument("--client-id", required=True, help="your Spotify app's Client ID")
    return p


def main(
    argv: list[str] | None = None, keyring: SecretTool | None = None, post: spotify.Poster | None = None
) -> int:
    args = parser().parse_args(argv)
    client_id = args.client_id.strip().lower()
    if not CLIENT_ID.match(client_id):
        return fail(EXIT_ERROR, "client-id", "The Client ID should be 32 hexadecimal characters")
    try:
        keyring = keyring or SecretTool()
    except KeyringError as exc:
        return fail(EXIT_KEYRING, "keyring", str(exc))
    post = post or spotify.http_post
    if args.command == "login":
        return cmd_login(client_id, keyring, post)
    if args.command == "token":
        return cmd_token(client_id, keyring, post)
    if args.command == "logout":
        return cmd_logout(client_id, keyring)
    return cmd_status(client_id, keyring)
