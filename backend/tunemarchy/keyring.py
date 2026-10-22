"""The refresh token lives in the desktop keyring (GNOME Keyring's Secret
Service on Omarchy) via libsecret's ``secret-tool``. Secrets travel over
stdin, never argv, so they do not show up in ``ps``."""

from __future__ import annotations

import shutil
import subprocess

SERVICE = "tunemarchy"


class KeyringError(RuntimeError):
    pass


class SecretTool:
    def __init__(self, tool: str | None = None) -> None:
        tool = tool or shutil.which("secret-tool")
        if not tool:
            raise KeyringError("secret-tool is missing. Install it with: omarchy pkg add libsecret")
        self.tool = tool

    def _run(self, *args: str, secret: str | None = None) -> subprocess.CompletedProcess:
        try:
            return subprocess.run(
                [self.tool, *args],
                input=secret,
                capture_output=True,
                text=True,
                timeout=60,  # an unlock prompt may be waiting for the user
                check=False,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            raise KeyringError(f"Could not talk to the keyring: {exc.__class__.__name__}") from exc

    @staticmethod
    def _no_match(result: subprocess.CompletedProcess) -> bool:
        # secret-tool's only quiet failure: exit status 1, nothing on stderr.
        return result.returncode == 1 and not result.stderr.strip()

    @staticmethod
    def _failure(action: str, result: subprocess.CompletedProcess) -> KeyringError:
        detail = result.stderr.strip()[:200] or f"secret-tool exited with status {result.returncode}"
        return KeyringError(f"{action}: {detail}")

    def get(self, client_id: str) -> str | None:
        result = self._run("lookup", "service", SERVICE, "client", client_id)
        if result.returncode == 0:
            return result.stdout.rstrip("\n") or None
        if self._no_match(result):
            return None
        raise self._failure("Keyring lookup failed", result)

    def set(self, client_id: str, refresh_token: str) -> None:
        result = self._run(
            "store",
            "--label",
            "Tunemarchy: Spotify sign-in",
            "service",
            SERVICE,
            "client",
            client_id,
            secret=refresh_token,
        )
        if result.returncode != 0:
            raise self._failure("Could not save to the keyring", result)

    def delete(self, client_id: str) -> None:
        result = self._run("clear", "service", SERVICE, "client", client_id)
        if result.returncode != 0 and not self._no_match(result):  # no match: already gone
            raise self._failure("Could not remove the sign-in from the keyring", result)
