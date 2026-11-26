"""Firebase Cloud Messaging (HTTP v1). Disabled unless FCM_PROJECT_ID and FCM_SERVICE_ACCOUNT_FILE are set."""

import json
import logging
import time
from pathlib import Path

import httpx
from jose import jwt

from app.core.config import settings

log = logging.getLogger(__name__)

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"


class FCMClient:
    def __init__(self) -> None:
        self._token: str | None = None
        self._token_exp = 0.0
        self._sa: dict | None = None

    @property
    def enabled(self) -> bool:
        return bool(settings.FCM_PROJECT_ID and settings.FCM_SERVICE_ACCOUNT_FILE)

    def _service_account(self) -> dict:
        if self._sa is None:
            self._sa = json.loads(Path(settings.FCM_SERVICE_ACCOUNT_FILE).read_text(encoding="utf-8"))
        return self._sa

    async def _access_token(self, client: httpx.AsyncClient) -> str:
        if self._token and time.time() < self._token_exp - 60:
            return self._token
        sa_info = self._service_account()
        now = int(time.time())
        assertion = jwt.encode(
            {
                "iss": sa_info["client_email"],
                "scope": _SCOPE,
                "aud": sa_info.get("token_uri", "https://oauth2.googleapis.com/token"),
                "iat": now,
                "exp": now + 3600,
            },
            sa_info["private_key"],
            algorithm="RS256",
        )
        resp = await client.post(
            sa_info.get("token_uri", "https://oauth2.googleapis.com/token"),
            data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion},
        )
        resp.raise_for_status()
        body = resp.json()
        self._token = body["access_token"]
        self._token_exp = time.time() + int(body.get("expires_in", 3600))
        return self._token

    async def send(self, tokens: list[str], title: str, body: str, data: dict[str, str]) -> list[str]:
        """Send to each token. Returns tokens FCM reports as unregistered (caller should delete them)."""
        if not self.enabled or not tokens:
            return []
        dead: list[str] = []
        url = f"https://fcm.googleapis.com/v1/projects/{settings.FCM_PROJECT_ID}/messages:send"
        async with httpx.AsyncClient(timeout=10) as client:
            try:
                access = await self._access_token(client)
            except Exception:  # noqa: BLE001
                log.exception("FCM auth failed")
                return []
            for token in tokens:
                msg = {
                    "message": {
                        "token": token,
                        "notification": {"title": title, "body": body},
                        "data": {k: str(v) for k, v in data.items()},
                        "android": {"priority": "high"},
                    }
                }
                try:
                    r = await client.post(url, json=msg, headers={"Authorization": f"Bearer {access}"})
                    if r.status_code == 404 or "UNREGISTERED" in r.text:
                        dead.append(token)
                    elif r.status_code >= 400:
                        log.warning("FCM send failed %s: %s", r.status_code, r.text[:200])
                except httpx.HTTPError:
                    log.exception("FCM send error")
        return dead


fcm = FCMClient()
