"""Twilio Programmable Voice: bridge calls via TwiML <Dial>, AI calls via bidirectional Media Streams."""

import base64
import hashlib
import hmac
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
from app.telephony.media import TwilioMediaAdapter

STATUS_MAP = {
    "queued": CallStatus.INITIATED, "initiated": CallStatus.INITIATED, "ringing": CallStatus.RINGING,
    "in-progress": CallStatus.CONNECTED, "answered": CallStatus.CONNECTED, "completed": CallStatus.COMPLETED,
    "busy": CallStatus.BUSY, "no-answer": CallStatus.NOT_ANSWERED, "failed": CallStatus.FAILED,
    "canceled": CallStatus.REJECTED,
}

_STATUS_EVENTS = ["initiated", "ringing", "answered", "completed"]


def _xml(body: str) -> Response:
    return Response(content=f'<?xml version="1.0" encoding="UTF-8"?><Response>{body}</Response>',
                    media_type="application/xml")


class TwilioProvider(TelephonyProvider):
    name = "twilio"
    supports_ai_streaming = True
    supports_inbound = True
    transfer_mode = "api"

    def is_configured(self) -> bool:
        return bool(settings.TWILIO_ACCOUNT_SID and settings.TWILIO_AUTH_TOKEN and settings.TELEPHONY_CALLER_ID)

    @property
    def _base(self) -> str:
        return f"https://api.twilio.com/2010-04-01/Accounts/{settings.TWILIO_ACCOUNT_SID}"

    @property
    def _auth(self) -> tuple[str, str]:
        return settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN

    async def _post(self, path: str, data: dict) -> dict:
        try:
            async with httpx.AsyncClient(timeout=20, auth=self._auth) as client:
                resp = await client.post(f"{self._base}{path}", data=data)
        except httpx.HTTPError as exc:
            raise TelephonyError(f"Twilio unreachable: {exc}") from exc
        if resp.status_code >= 400:
            raise TelephonyError(f"Twilio rejected the request ({resp.status_code}): {resp.text[:300]}")
        return resp.json()

    async def place_bridge_call(self, *, agent_number, customer_number, caller_id, callbacks, record,
                                time_limit_seconds) -> PlacedCall:
        body = await self._post("/Calls.json", {
            "To": agent_number, "From": caller_id, "Url": callbacks.answer + "&mode=bridge", "Method": "POST",
            "StatusCallback": callbacks.status + "&leg=agent", "StatusCallbackMethod": "POST",
            "StatusCallbackEvent": _STATUS_EVENTS, "TimeLimit": str(time_limit_seconds),
        })
        return PlacedCall(provider_call_id=body["sid"], raw=body)

    async def place_ai_call(self, *, customer_number, caller_id, callbacks, record, time_limit_seconds) -> PlacedCall:
        data = {
            "To": customer_number, "From": caller_id, "Url": callbacks.answer + "&mode=ai", "Method": "POST",
            "StatusCallback": callbacks.status, "StatusCallbackMethod": "POST",
            "StatusCallbackEvent": _STATUS_EVENTS, "TimeLimit": str(time_limit_seconds),
        }
        if record:
            data.update({"Record": "true", "RecordingStatusCallback": callbacks.recording,
                         "RecordingStatusCallbackEvent": "completed"})
        body = await self._post("/Calls.json", data)
        return PlacedCall(provider_call_id=body["sid"], raw=body)

    async def hangup(self, provider_call_id: str) -> None:
        await self._post(f"/Calls/{provider_call_id}.json", {"Status": "completed"})

    async def transfer(self, provider_call_id: str, to_number: str, callbacks: CallbackUrls, caller_id: str) -> bool:
        twiml = (f'<Response><Say>Connecting you to our team now.</Say><Dial callerId={quoteattr(caller_id)}>'
                 f'<Number>{escape(to_number)}</Number></Dial></Response>')
        await self._post(f"/Calls/{provider_call_id}.json", {"Twiml": twiml})
        return True

    def answer_response(self, *, kind, mode, customer_number, callbacks, record, caller_id, agent_number=None,
                        time_limit_seconds=3600) -> Response:
        if mode == "ai":
            return _xml(
                f"<Connect><Stream url={quoteattr(callbacks.media_ws)}>"
                f'<Parameter name="wt" value={quoteattr(callbacks.token)}/></Stream></Connect>'
            )
        if not customer_number:
            return _xml("<Hangup/>")
        rec = ""
        if record:
            rec = (f' record="record-from-answer-dual" recordingStatusCallback={quoteattr(callbacks.recording)}'
                   ' recordingStatusCallbackEvent="completed"')
        return _xml(
            f"<Dial callerId={quoteattr(caller_id)} timeLimit=\"{time_limit_seconds}\""
            f" action={quoteattr(callbacks.status + '&leg=dial')} method=\"POST\"{rec}>"
            f"<Number statusCallbackEvent=\"ringing answered completed\""
            f" statusCallback={quoteattr(callbacks.status + '&leg=customer')} statusCallbackMethod=\"POST\">"
            f"{escape(customer_number)}</Number></Dial>"
        )

    def parse_status(self, params: dict) -> StatusUpdate:
        leg = params.get("leg")
        if leg == "dial":
            raw = (params.get("DialCallStatus") or "").lower()
            return StatusUpdate(provider_call_id=None, status=STATUS_MAP.get(raw), leg="dial", raw_status=raw,
                                talk_seconds=to_int(params.get("DialCallDuration")))
        raw = (params.get("CallStatus") or "").lower()
        duration = to_int(params.get("CallDuration"))
        return StatusUpdate(
            provider_call_id=params.get("CallSid") if leg != "customer" else None,
            status=STATUS_MAP.get(raw), leg=leg, raw_status=raw, duration_seconds=duration,
            talk_seconds=duration if leg in (None, "customer") else None,
        )

    def parse_recording(self, params: dict) -> RecordingInfo | None:
        url = params.get("RecordingUrl")
        if not url:
            return None
        return RecordingInfo(url=url + ".mp3", recording_id=params.get("RecordingSid"),
                             duration_seconds=to_int(params.get("RecordingDuration")))

    def verify_signature(self, url: str, params: dict, headers: dict) -> bool:
        signature = headers.get("x-twilio-signature")
        if not signature:
            return False
        # Twilio signs the full request URL (with query string) + POST params sorted by name.
        payload = url + "".join(f"{k}{params[k]}" for k in sorted(params))
        digest = hmac.new(settings.TWILIO_AUTH_TOKEN.encode(), payload.encode(), hashlib.sha1).digest()
        return hmac.compare_digest(base64.b64encode(digest).decode(), signature)

    def inbound_caller(self, params: dict) -> tuple[str | None, str | None]:
        return params.get("From"), params.get("CallSid")

    def inbound_response(self, agent_number, callbacks, caller_id, record) -> Response:
        if not agent_number or callbacks is None:
            return _xml("<Say>All our team members are busy. We will call you back shortly.</Say><Hangup/>")
        rec = (f' record="record-from-answer-dual" recordingStatusCallback={quoteattr(callbacks.recording)}'
               if record else "")
        return _xml(
            f"<Dial timeout=\"30\" action={quoteattr(callbacks.status + '&leg=dial')} method=\"POST\"{rec}>"
            f"<Number statusCallbackEvent=\"ringing answered completed\""
            f" statusCallback={quoteattr(callbacks.status + '&leg=customer')}>{escape(agent_number)}</Number></Dial>"
        )

    def media_adapter(self):
        return TwilioMediaAdapter()

    async def open_recording(self, url: str) -> tuple[AsyncIterator[bytes], str]:
        client = httpx.AsyncClient(timeout=60, auth=self._auth, follow_redirects=True)
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
