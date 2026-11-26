"""Plivo Voice: bridge calls via <Dial>, AI calls via bidirectional <Stream>.

Plivo request signatures are not verified here; every callback is authenticated with our per-call `wt` token.
"""

from collections.abc import AsyncIterator
from xml.sax.saxutils import escape, quoteattr

import httpx
from fastapi import Response

from app.core.config import settings
from app.models.enums import CallStatus
from app.telephony.base import (
    CallbackUrls,
    PlacedCall,
    RecordingInfo,
    StatusUpdate,
    TelephonyError,
    TelephonyProvider,
    to_int,
)
from app.telephony.media import PlivoMediaAdapter

STATUS_MAP = {
    "queued": CallStatus.INITIATED, "ringing": CallStatus.RINGING, "in-progress": CallStatus.CONNECTED,
    "answer": CallStatus.CONNECTED, "completed": CallStatus.COMPLETED, "busy": CallStatus.BUSY,
    "no-answer": CallStatus.NOT_ANSWERED, "timeout": CallStatus.NOT_ANSWERED, "failed": CallStatus.FAILED,
    "cancel": CallStatus.REJECTED, "rejected": CallStatus.REJECTED,
}


def _xml(body: str) -> Response:
    return Response(content=f'<?xml version="1.0" encoding="UTF-8"?><Response>{body}</Response>',
                    media_type="application/xml")


class PlivoProvider(TelephonyProvider):
    name = "plivo"
    supports_ai_streaming = True
    supports_inbound = True
    transfer_mode = "api"

    def is_configured(self) -> bool:
        return bool(settings.PLIVO_AUTH_ID and settings.PLIVO_AUTH_TOKEN and settings.TELEPHONY_CALLER_ID)

    @property
    def _base(self) -> str:
        return f"https://api.plivo.com/v1/Account/{settings.PLIVO_AUTH_ID}"

    @property
    def _auth(self) -> tuple[str, str]:
        return settings.PLIVO_AUTH_ID, settings.PLIVO_AUTH_TOKEN

    async def _request(self, method: str, path: str, json: dict | None = None) -> dict:
        try:
            async with httpx.AsyncClient(timeout=20, auth=self._auth) as client:
                resp = await client.request(method, f"{self._base}{path}", json=json)
        except httpx.HTTPError as exc:
            raise TelephonyError(f"Plivo unreachable: {exc}") from exc
        if resp.status_code >= 400:
            raise TelephonyError(f"Plivo rejected the request ({resp.status_code}): {resp.text[:300]}")
        return resp.json() if resp.content else {}

    async def place_bridge_call(self, *, agent_number, customer_number, caller_id, callbacks, record,
                                time_limit_seconds) -> PlacedCall:
        body = await self._request("POST", "/Call/", {
            "from": caller_id.lstrip("+"), "to": agent_number.lstrip("+"),
            "answer_url": callbacks.answer + "&mode=bridge", "answer_method": "POST",
            "hangup_url": callbacks.status + "&leg=agent", "hangup_method": "POST",
            "ring_url": callbacks.status + "&leg=agent&ev=ring", "ring_method": "POST",
            "time_limit": time_limit_seconds,
        })
        rid = body.get("request_uuid")
        if not rid:
            raise TelephonyError("Plivo response did not include request_uuid")
        return PlacedCall(provider_call_id=rid if isinstance(rid, str) else rid[0], raw=body)

    async def place_ai_call(self, *, customer_number, caller_id, callbacks, record, time_limit_seconds) -> PlacedCall:
        body = await self._request("POST", "/Call/", {
            "from": caller_id.lstrip("+"), "to": customer_number.lstrip("+"),
            "answer_url": callbacks.answer + "&mode=ai" + ("&rec=1" if record else ""), "answer_method": "POST",
            "hangup_url": callbacks.status, "hangup_method": "POST",
            "ring_url": callbacks.status + "&ev=ring", "ring_method": "POST",
            "time_limit": time_limit_seconds,
        })
        rid = body.get("request_uuid")
        if not rid:
            raise TelephonyError("Plivo response did not include request_uuid")
        return PlacedCall(provider_call_id=rid if isinstance(rid, str) else rid[0], raw=body)

    async def hangup(self, provider_call_id: str) -> None:
        await self._request("DELETE", f"/Call/{provider_call_id}/")

    async def transfer(self, provider_call_id: str, to_number: str, callbacks: CallbackUrls, caller_id: str) -> bool:
        await self._request("POST", f"/Call/{provider_call_id}/", {
            "legs": "aleg", "aleg_url": callbacks.answer + "&mode=transfer", "aleg_method": "POST",
        })
        return True

    def answer_response(self, *, kind, mode, customer_number, callbacks, record, caller_id, agent_number=None,
                        time_limit_seconds=3600) -> Response:
        rec = ""
        if record:
            rec = (f'<Record recordSession="true" startOnDialAnswer="{"true" if mode == "bridge" else "false"}"'
                   f' redirect="false" maxLength="{time_limit_seconds}" callbackUrl={quoteattr(callbacks.recording)}'
                   ' callbackMethod="POST"/>')
        if mode == "ai":
            return _xml(
                rec + '<Stream bidirectional="true" keepCallAlive="true" contentType="audio/x-mulaw;rate=8000"'
                f' extraHeaders={quoteattr("wt=" + callbacks.token)}>'
                f"{escape(callbacks.media_ws + '?wt=' + callbacks.token)}</Stream>"
            )
        if mode == "transfer":
            if not agent_number:
                return _xml("<Speak>Sorry, no one is available right now. We will call you back.</Speak><Hangup/>")
            return _xml(f"<Speak>Connecting you to our team now.</Speak><Dial callerId={quoteattr(caller_id)}>"
                        f"<Number>{escape(agent_number.lstrip('+'))}</Number></Dial>")
        if not customer_number:
            return _xml("<Hangup/>")
        return _xml(
            rec + f"<Dial callerId={quoteattr(caller_id.lstrip('+'))} timeLimit=\"{time_limit_seconds}\""
            f" action={quoteattr(callbacks.status + '&leg=dial')} method=\"POST\""
            f" callbackUrl={quoteattr(callbacks.status + '&leg=customer')} callbackMethod=\"POST\">"
            f"<Number>{escape(customer_number.lstrip('+'))}</Number></Dial>"
        )

    def parse_status(self, params: dict) -> StatusUpdate:
        leg = params.get("leg")
        if leg in ("dial", "customer"):
            action = (params.get("DialAction") or "").lower()
            b_status = (params.get("DialBLegStatus") or params.get("DialStatus") or "").lower()
            if action == "answer" or b_status == "answer":
                status = CallStatus.CONNECTED
            elif action == "hangup" or b_status in ("hangup", "completed"):
                status = CallStatus.COMPLETED if to_int(params.get("DialBLegDuration")) else STATUS_MAP.get(
                    (params.get("DialBLegHangupCause") or "").lower(), CallStatus.NOT_ANSWERED)
            else:
                status = STATUS_MAP.get(b_status)
            return StatusUpdate(status=status, leg="customer", raw_status=b_status or action,
                                talk_seconds=to_int(params.get("DialBLegDuration")))
        raw = (params.get("CallStatus") or "").lower()
        if params.get("ev") == "ring":
            raw = "ringing"
        return StatusUpdate(
            provider_call_id=params.get("CallUUID"), status=STATUS_MAP.get(raw), leg=leg, raw_status=raw,
            duration_seconds=to_int(params.get("Duration")),
            talk_seconds=to_int(params.get("BillDuration")) if leg is None else None,
        )

    def parse_recording(self, params: dict) -> RecordingInfo | None:
        url = params.get("RecordUrl")
        if not url:
            return None
        return RecordingInfo(url=url, recording_id=params.get("RecordingID"),
                             duration_seconds=to_int(params.get("RecordingDuration")))

    def inbound_caller(self, params: dict) -> tuple[str | None, str | None]:
        frm = params.get("From")
        return (("+" + frm) if frm and not frm.startswith("+") else frm), params.get("CallUUID")

    def inbound_response(self, agent_number, callbacks, caller_id, record) -> Response:
        if not agent_number or callbacks is None:
            return _xml("<Speak>All our team members are busy. We will call you back shortly.</Speak><Hangup/>")
        return _xml(
            f"<Dial action={quoteattr(callbacks.status + '&leg=dial')} method=\"POST\""
            f" callbackUrl={quoteattr(callbacks.status + '&leg=customer')} callbackMethod=\"POST\">"
            f"<Number>{escape(agent_number.lstrip('+'))}</Number></Dial>"
        )

    def media_adapter(self):
        return PlivoMediaAdapter()

    async def open_recording(self, url: str) -> tuple[AsyncIterator[bytes], str]:
        client = httpx.AsyncClient(timeout=60, follow_redirects=True)
        resp = await client.send(client.build_request("GET", url), stream=True)
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
