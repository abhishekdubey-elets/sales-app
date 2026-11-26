"""Knowlarity SuperReceptionist click-to-call (bridge calls only).

Knowlarity posts call events to a webhook configured in its panel rather than a per-call URL, so callbacks
are matched by Knowlarity's call id and authenticated with a provider-level `wt` token. Field names below
follow Knowlarity's click-to-call / call-log payloads; confirm them with your account before go-live.
"""

import httpx

from app.core.config import settings
from app.models.enums import CallStatus
from app.telephony.base import PlacedCall, RecordingInfo, StatusUpdate, TelephonyError, TelephonyProvider, to_int

STATUS_MAP = {
    "initiated": CallStatus.INITIATED, "ringing": CallStatus.RINGING, "connected": CallStatus.CONNECTED,
    "answered": CallStatus.CONNECTED, "completed": CallStatus.COMPLETED, "busy": CallStatus.BUSY,
    "missed": CallStatus.NOT_ANSWERED, "no answer": CallStatus.NOT_ANSWERED, "noanswer": CallStatus.NOT_ANSWERED,
    "failed": CallStatus.FAILED, "rejected": CallStatus.REJECTED,
}


class KnowlarityProvider(TelephonyProvider):
    name = "knowlarity"
    supports_ai_streaming = False
    supports_inbound = False
    supports_hangup = False

    def is_configured(self) -> bool:
        return bool(settings.KNOWLARITY_API_KEY and settings.KNOWLARITY_AUTH_TOKEN and settings.KNOWLARITY_K_NUMBER)

    async def place_bridge_call(self, *, agent_number, customer_number, caller_id, callbacks, record,
                                time_limit_seconds) -> PlacedCall:
        headers = {"x-api-key": settings.KNOWLARITY_API_KEY, "Authorization": settings.KNOWLARITY_AUTH_TOKEN,
                   "content-type": "application/json"}
        payload = {"k_number": settings.KNOWLARITY_K_NUMBER, "agent_number": agent_number,
                   "customer_number": customer_number}
        if caller_id:
            payload["caller_id"] = caller_id
        try:
            async with httpx.AsyncClient(timeout=20) as client:
                resp = await client.post(f"{settings.KNOWLARITY_BASE_URL}/call/makecall", json=payload, headers=headers)
        except httpx.HTTPError as exc:
            raise TelephonyError(f"Knowlarity unreachable: {exc}") from exc
        if resp.status_code >= 400:
            raise TelephonyError(f"Knowlarity rejected the call ({resp.status_code}): {resp.text[:300]}")
        body = resp.json()
        success = body.get("success") or {}
        call_id = success.get("call_id") or body.get("call_id")
        if not call_id:
            raise TelephonyError(f"Knowlarity did not confirm the call: {str(body)[:300]}")
        return PlacedCall(provider_call_id=str(call_id), raw=body)

    def parse_status(self, params: dict) -> StatusUpdate:
        raw = str(params.get("call_status") or params.get("status") or params.get("Status") or "").lower()
        duration = to_int(params.get("call_duration") or params.get("duration"))
        return StatusUpdate(
            provider_call_id=str(params.get("call_id") or params.get("uuid") or "") or None,
            status=STATUS_MAP.get(raw), raw_status=raw, duration_seconds=duration, talk_seconds=duration,
            recording_url=params.get("call_recording") or params.get("recording_url") or None,
        )

    def parse_recording(self, params: dict) -> RecordingInfo | None:
        url = params.get("call_recording") or params.get("recording_url")
        return RecordingInfo(url=url) if url else None
