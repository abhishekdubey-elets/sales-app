"""Exotel (India). Bridge calls via Calls/connect; AI calls via a flow containing the Voicebot applet.

Exotel flow setup for AI calls (see docs/DEPLOYMENT.md). Flow URLs are static, so they carry a
provider-level token (`python -m app.cli exotel-urls` prints them) and calls are matched by CallSid:
  1. Voicebot applet → "Dynamic URL" = GET {API}/api/v1/webhooks/telephony/exotel/voicebot-url?wt=…
  2. Connect applet after it → dynamic number URL = {API}/api/v1/webhooks/telephony/exotel/transfer-target?wt=…
     (returns the salesperson's number when the AI agent requested a human handoff, empty otherwise).
  3. Inbound: Connect applet dynamic URL = {API}/api/v1/webhooks/telephony/exotel/inbound?wt=…
Verify parameter names against your Exotel account's API docs before go-live.
"""

from collections.abc import AsyncIterator

import httpx
from fastapi import Response
from fastapi.responses import PlainTextResponse

from app.core.config import settings
from app.models.enums import CallStatus
from app.telephony.base import (
    PlacedCall,
    RecordingInfo,
    StatusUpdate,
    TelephonyError,
    TelephonyProvider,
    to_int,
)
from app.telephony.media import ExotelMediaAdapter

STATUS_MAP = {
    "queued": CallStatus.INITIATED, "initiated": CallStatus.INITIATED, "ringing": CallStatus.RINGING,
    "in-progress": CallStatus.CONNECTED, "answered": CallStatus.CONNECTED, "completed": CallStatus.COMPLETED,
    "busy": CallStatus.BUSY, "no-answer": CallStatus.NOT_ANSWERED, "failed": CallStatus.FAILED,
    "canceled": CallStatus.REJECTED, "cancelled": CallStatus.REJECTED,
}


class ExotelProvider(TelephonyProvider):
    name = "exotel"
    supports_ai_streaming = True
    supports_inbound = True
    supports_hangup = False
    transfer_mode = "flow"

    def is_configured(self) -> bool:
        return bool(settings.EXOTEL_API_KEY and settings.EXOTEL_API_TOKEN and settings.EXOTEL_ACCOUNT_SID
                    and settings.TELEPHONY_CALLER_ID)

    @property
    def _base(self) -> str:
        return f"https://{settings.EXOTEL_SUBDOMAIN}/v1/Accounts/{settings.EXOTEL_ACCOUNT_SID}"

    @property
    def _auth(self) -> tuple[str, str]:
        return settings.EXOTEL_API_KEY, settings.EXOTEL_API_TOKEN

    async def _connect(self, data: dict) -> PlacedCall:
        try:
            async with httpx.AsyncClient(timeout=20, auth=self._auth) as client:
                resp = await client.post(f"{self._base}/Calls/connect.json", data=data)
        except httpx.HTTPError as exc:
            raise TelephonyError(f"Exotel unreachable: {exc}") from exc
        if resp.status_code >= 400:
            raise TelephonyError(f"Exotel rejected the call ({resp.status_code}): {resp.text[:300]}")
        body = resp.json()
        sid = (body.get("Call") or {}).get("Sid")
        if not sid:
            raise TelephonyError("Exotel response did not include a call Sid")
        return PlacedCall(provider_call_id=sid, raw=body)

    async def place_bridge_call(self, *, agent_number, customer_number, caller_id, callbacks, record,
                                time_limit_seconds) -> PlacedCall:
        return await self._connect({
            "From": agent_number, "To": customer_number, "CallerId": caller_id,
            "StatusCallback": callbacks.status,
            "StatusCallbackEvents[0]": "terminal", "StatusCallbackEvents[1]": "answered",
            "Record": "true" if record else "false", "TimeLimit": str(time_limit_seconds),
            "CallType": "trans",
        })

    async def place_ai_call(self, *, customer_number, caller_id, callbacks, record, time_limit_seconds) -> PlacedCall:
        if not settings.EXOTEL_AI_APP_ID:
            raise TelephonyError("EXOTEL_AI_APP_ID (Voicebot flow) is not configured")
        flow_url = f"http://my.exotel.com/{settings.EXOTEL_ACCOUNT_SID}/exoml/start_voice/{settings.EXOTEL_AI_APP_ID}"
        return await self._connect({
            "From": customer_number, "CallerId": caller_id, "Url": flow_url,
            "StatusCallback": callbacks.status,
            "StatusCallbackEvents[0]": "terminal", "StatusCallbackEvents[1]": "answered",
            "Record": "true" if record else "false", "TimeLimit": str(time_limit_seconds),
            "CallType": "trans",
        })

    def parse_status(self, params: dict) -> StatusUpdate:
        event = (params.get("EventType") or "").lower()
        raw = (params.get("Status") or params.get("CallStatus") or "").lower()
        status = CallStatus.CONNECTED if event == "answered" else STATUS_MAP.get(raw)
        return StatusUpdate(
            provider_call_id=params.get("CallSid"), status=status, raw_status=raw or event,
            duration_seconds=to_int(params.get("Duration")),
            talk_seconds=to_int(params.get("ConversationDuration")),
            recording_url=params.get("RecordingUrl") or None,
        )

    def parse_recording(self, params: dict) -> RecordingInfo | None:
        url = params.get("RecordingUrl")
        return RecordingInfo(url=url, duration_seconds=to_int(params.get("ConversationDuration"))) if url else None

    def inbound_caller(self, params: dict) -> tuple[str | None, str | None]:
        return params.get("CallFrom") or params.get("From"), params.get("CallSid")

    def inbound_response(self, agent_number, callbacks, caller_id, record) -> Response:
        # Exotel Connect applet "dynamic URL" expects the destination number(s) as plain text.
        return PlainTextResponse(agent_number or "")

    def media_adapter(self):
        return ExotelMediaAdapter()

    async def open_recording(self, url: str) -> tuple[AsyncIterator[bytes], str]:
        client = httpx.AsyncClient(timeout=60, auth=self._auth, follow_redirects=True)
        req = client.build_request("GET", url)
        resp = await client.send(req, stream=True)
        if resp.status_code >= 400:
            await resp.aclose()
            await client.aclose()
            raise TelephonyError(f"Recording fetch failed ({resp.status_code})")

        async def body():
            try:
                async for chunk in resp.aiter_bytes():
                    yield chunk
            finally:
                await resp.aclose()
                await client.aclose()

        return body(), resp.headers.get("content-type", "audio/mpeg")
