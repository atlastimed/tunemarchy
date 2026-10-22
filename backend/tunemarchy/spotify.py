"""Spotify's Authorization Code flow with PKCE.

PKCE needs no client secret, so a personal Client ID is all a user has to
paste. Refresh tokens rotate: every refresh may return a new one, which must
replace the old one in the keyring.
"""

from __future__ import annotations

import base64
import hashlib
import json
import secrets
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass

AUTHORIZE_URL = "https://accounts.spotify.com/authorize"
TOKEN_URL = "https://accounts.spotify.com/api/token"  # noqa: S105 - a URL, not a password
CALLBACK_PORT = 43117
REDIRECT_URI = f"http://127.0.0.1:{CALLBACK_PORT}/callback"
SCOPES = (
    "user-library-read",
    "user-library-modify",
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-read-currently-playing",
)


class SpotifyError(RuntimeError):
    pass


class SignedOut(SpotifyError):
    """Spotify rejected the refresh token: the user must sign in again."""


class NetworkError(SpotifyError):
    """Spotify could not be reached; the stored sign-in is still good."""


@dataclass(frozen=True)
class Tokens:
    access_token: str
    expires_in: int
    refresh_token: str | None  # None when Spotify kept the old one


def make_verifier() -> str:
    # 64 random bytes -> 86 URL-safe characters, inside PKCE's 43..128 range.
    return secrets.token_urlsafe(64)


def challenge_for(verifier: str) -> str:
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")


def authorize_url(client_id: str, state: str, challenge: str) -> str:
    query = urllib.parse.urlencode(
        {
            "client_id": client_id,
            "response_type": "code",
            "redirect_uri": REDIRECT_URI,
            "code_challenge_method": "S256",
            "code_challenge": challenge,
            "state": state,
            "scope": " ".join(SCOPES),
        }
    )
    return f"{AUTHORIZE_URL}?{query}"


Poster = Callable[[str, dict[str, str]], tuple[int, str]]


def http_post(url: str, form: dict[str, str]) -> tuple[int, str]:
    data = urllib.parse.urlencode(form).encode("ascii")
    request = urllib.request.Request(  # noqa: S310 - callers pass the fixed https TOKEN_URL
        url, data=data, headers={"Content-Type": "application/x-www-form-urlencoded"}, method="POST"
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:  # noqa: S310 - fixed https URL
            return response.status, response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")
    except (urllib.error.URLError, OSError, TimeoutError) as exc:
        raise NetworkError(f"Could not reach Spotify: {exc.__class__.__name__}") from exc


def _parse_tokens(status: int, body: str) -> Tokens:
    try:
        payload = json.loads(body or "{}")
    except ValueError:
        payload = {}
    if status == 200 and isinstance(payload.get("access_token"), str):
        return Tokens(
            access_token=payload["access_token"],
            expires_in=int(payload.get("expires_in") or 3600),
            refresh_token=payload.get("refresh_token") or None,
        )
    error = str(payload.get("error") or "")
    description = str(payload.get("error_description") or "")[:200]
    # Only an explicit verdict on the grant means the sign-in is gone. A 5xx,
    # a proxy page or an unknown error must not delete a working token.
    if error in ("invalid_grant", "invalid_client"):
        raise SignedOut(description or error)
    if status >= 500 or status == 0:
        raise NetworkError(f"Spotify is unavailable (HTTP {status})")
    raise SpotifyError(description or error or f"HTTP {status}")


def exchange_code(client_id: str, code: str, verifier: str, post: Poster = http_post) -> Tokens:
    status, body = post(
        TOKEN_URL,
        {
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": REDIRECT_URI,
            "client_id": client_id,
            "code_verifier": verifier,
        },
    )
    tokens = _parse_tokens(status, body)
    if not tokens.refresh_token:
        raise SpotifyError("Spotify did not return a refresh token")
    return tokens


def refresh(client_id: str, refresh_token: str, post: Poster = http_post) -> Tokens:
    status, body = post(
        TOKEN_URL,
        {"grant_type": "refresh_token", "refresh_token": refresh_token, "client_id": client_id},
    )
    return _parse_tokens(status, body)
