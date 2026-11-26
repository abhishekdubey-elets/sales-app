from app.core.config import settings
from app.telephony.base import TelephonyProvider
from app.telephony.exotel import ExotelProvider
from app.telephony.knowlarity import KnowlarityProvider
from app.telephony.plivo import PlivoProvider
from app.telephony.twilio import TwilioProvider

PROVIDERS: dict[str, type[TelephonyProvider]] = {
    "exotel": ExotelProvider,
    "twilio": TwilioProvider,
    "plivo": PlivoProvider,
    "knowlarity": KnowlarityProvider,
}

_override: TelephonyProvider | None = None
_instances: dict[str, TelephonyProvider] = {}


def get_provider(name: str | None = None) -> TelephonyProvider | None:
    """The active provider (TELEPHONY_PROVIDER), or a named one for webhook routing."""
    if _override is not None and (name is None or name == _override.name):
        return _override
    key = name or settings.TELEPHONY_PROVIDER
    if not key or key not in PROVIDERS:
        return None
    if key not in _instances:
        _instances[key] = PROVIDERS[key]()
    return _instances[key]


def set_provider_override(provider: TelephonyProvider | None) -> None:
    """Tests only: inject a fake provider."""
    global _override
    _override = provider


def telephony_status() -> dict:
    p = get_provider()
    configured = bool(p and p.is_configured())
    return {
        "provider": p.name if p else None,
        "configured": configured,
        # Without a provider, salespeople call from their own phone (SIM) and report the result.
        "call_mode": "bridge" if configured else "device",
        "supports_ai_streaming": bool(p and p.supports_ai_streaming),
        "supports_recording": bool(p and p.supports_recording),
        "supports_inbound": bool(p and p.supports_inbound),
    }
