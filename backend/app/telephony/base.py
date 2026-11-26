"""Provider-independent telephony interface.

Adapters translate between our call model and a provider's REST API, webhooks and media streams.
They never invent call state: `place_*` returns only what the provider's API accepted, and every later
status arrives through `parse_status` from a provider webhook.
"""

import uuid
from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass, field
from urllib.parse import urlencode

from fastapi import Response

from app.core.config import settings
from app.core.security import webhook_token
from app.models.enums import CallStatus


class TelephonyError(Exception):
    """The provider rejected a request or could not be reached."""


class TelephonyNotSupported(TelephonyError):
    pass


@dataclass
class CallbackUrls:
    status: str
    answer: str
    recording: str
    media_ws: str
    voicebot: str
    transfer_target: str
    token: str


def build_callbacks(provider: str, kind: str, call_id: uuid.UUID) -> CallbackUrls:
    wt = webhook_token(kind, call_id)
    q = urlencode({"kind": kind, "cid": str(call_id), "wt": wt})
    base = f"{settings.API_PUBLIC_BASE_URL}/api/v1/webhooks/telephony/{provider}"
    return CallbackUrls(
        status=f"{base}/status?{q}",
        answer=f"{base}/answer?{q}",
        recording=f"{base}/recording?{q}",
        media_ws=f"{settings.public_ws_base_url}/api/v1/media/{provider}/{call_id}",
        voicebot=f"{base}/voicebot-url?{q}",
        transfer_target=f"{base}/transfer-target?{q}",
        token=wt,
    )


@dataclass
class PlacedCall:
    provider_call_id: str
    raw: dict = field(default_factory=dict)


@dataclass
class StatusUpdate:
    provider_call_id: str | None = None
    status: CallStatus | None = None
    leg: str | None = None  # agent | customer | dial | None (single-leg)
    duration_seconds: int | None = None
    talk_seconds: int | None = None
    recording_url: str | None = None
    recording_id: str | None = None
    raw_status: str | None = None


@dataclass
class RecordingInfo:
    url: str
    recording_id: str | None = None
    duration_seconds: int | None = None


def to_int(value) -> int | None:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


class TelephonyProvider(ABC):
    name: str = "base"
    supports_ai_streaming: bool = False
    supports_inbound: bool = False
    supports_recording: bool = True
    supports_hangup: bool = True
    # "api": live transfer through the provider API; "flow": provider call flow continues after the media
    # stream closes (Exotel); "none": not supported.
    transfer_mode: str = "none"

    @abstractmethod
    def is_configured(self) -> bool: ...

    @abstractmethod
    async def place_bridge_call(
        self, *, agent_number: str, customer_number: str, caller_id: str, callbacks: CallbackUrls,
        record: bool, time_limit_seconds: int,
    ) -> PlacedCall:
        """Ring `agent_number` first, then bridge to `customer_number`."""

    async def place_ai_call(
        self, *, customer_number: str, caller_id: str, callbacks: CallbackUrls, record: bool, time_limit_seconds: int,
    ) -> PlacedCall:
        raise TelephonyNotSupported(f"{self.name} does not support AI media streaming")

    async def hangup(self, provider_call_id: str) -> None:
        raise TelephonyNotSupported(f"{self.name} does not support ending calls through the API")

    async def transfer(self, provider_call_id: str, to_number: str, callbacks: CallbackUrls, caller_id: str) -> bool:
        return False

    @abstractmethod
    def parse_status(self, params: dict) -> StatusUpdate: ...

    def parse_recording(self, params: dict) -> RecordingInfo | None:
        return None

    def verify_signature(self, url: str, params: dict, headers: dict) -> bool:
        """Provider request signing, where the provider offers it. Our own `wt` token is always checked too."""
        return True

    def answer_response(self, *, kind: str, mode: str, customer_number: str | None, callbacks: CallbackUrls,
                        record: bool, caller_id: str, agent_number: str | None = None,
                        time_limit_seconds: int = 3600) -> Response:
        raise TelephonyNotSupported(f"{self.name} has no answer-URL call flow")

    def inbound_caller(self, params: dict) -> tuple[str | None, str | None]:
        """Return (caller_number, provider_call_id) for an inbound webhook."""
        raise TelephonyNotSupported(f"{self.name} inbound routing is not implemented")

    def inbound_response(self, agent_number: str | None, callbacks: CallbackUrls | None, caller_id: str,
                         record: bool) -> Response:
        raise TelephonyNotSupported(f"{self.name} inbound routing is not implemented")

    def media_adapter(self):
        return None

    async def open_recording(self, url: str) -> tuple[AsyncIterator[bytes], str]:
        raise TelephonyNotSupported("Recording download not supported")
