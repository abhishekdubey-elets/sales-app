from app.core.config import settings
from app.voice.llm.anthropic_llm import AnthropicLLM
from app.voice.llm.base import LLMProvider
from app.voice.stt.base import STTProvider
from app.voice.stt.deepgram import DeepgramSTT
from app.voice.tts.base import TTSProvider
from app.voice.tts.elevenlabs import ElevenLabsTTS

_LLMS = {"anthropic": AnthropicLLM}
_STTS = {"deepgram": DeepgramSTT}
_TTSS = {"elevenlabs": ElevenLabsTTS}

_instances: dict[str, object] = {}
_overrides: dict[str, object] = {}


def _get(kind: str, name: str, table: dict):
    if kind in _overrides:
        return _overrides[kind]
    if not name or name not in table:
        return None
    key = f"{kind}:{name}"
    if key not in _instances:
        _instances[key] = table[name]()
    return _instances[key]


def get_llm() -> LLMProvider | None:
    return _get("llm", settings.LLM_PROVIDER, _LLMS)


def get_stt() -> STTProvider | None:
    return _get("stt", settings.STT_PROVIDER, _STTS)


def get_tts() -> TTSProvider | None:
    return _get("tts", settings.TTS_PROVIDER, _TTSS)


def set_override(kind: str, impl) -> None:
    """Tests only."""
    if impl is None:
        _overrides.pop(kind, None)
    else:
        _overrides[kind] = impl


def voice_ready() -> tuple[bool, str | None]:
    for kind, getter in (("LLM", get_llm), ("speech-to-text", get_stt), ("text-to-speech", get_tts)):
        impl = getter()
        if impl is None or not impl.is_configured():
            return False, f"{kind} provider is not configured"
    return True, None


def voice_status() -> dict:
    llm, stt, tts = get_llm(), get_stt(), get_tts()
    return {
        "llm": {"provider": llm.name if llm else None, "configured": bool(llm and llm.is_configured()),
                "model": llm.model if llm else None},
        "stt": {"provider": stt.name if stt else None, "configured": bool(stt and stt.is_configured())},
        "tts": {"provider": tts.name if tts else None, "configured": bool(tts and tts.is_configured())},
    }
