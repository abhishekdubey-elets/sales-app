"""ElevenLabs streaming text-to-speech in telephony format (8 kHz µ-law)."""

from collections.abc import AsyncIterator

import httpx

from app.core.config import settings
from app.voice.tts.base import TTSProvider


class TTSError(Exception):
    pass


class ElevenLabsTTS(TTSProvider):
    name = "elevenlabs"
    output_encoding = "mulaw"

    def is_configured(self) -> bool:
        return bool(settings.ELEVENLABS_API_KEY)

    async def synthesize(self, text: str, *, voice_id: str | None, language: str, speed: float) -> AsyncIterator[bytes]:
        voice = voice_id or settings.ELEVENLABS_DEFAULT_VOICE_ID
        if not voice:
            raise TTSError("No voice_id on the agent and ELEVENLABS_DEFAULT_VOICE_ID is empty")
        url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice}/stream"
        body = {
            "text": text,
            "model_id": settings.ELEVENLABS_MODEL,
            "language_code": language,
            # ElevenLabs accepts speed 0.7–1.2; agent config allows 0.5–2.0, so clamp.
            "voice_settings": {"stability": 0.5, "similarity_boost": 0.75, "speed": max(0.7, min(1.2, speed))},
        }
        headers = {"xi-api-key": settings.ELEVENLABS_API_KEY, "accept": "audio/basic"}
        async with httpx.AsyncClient(timeout=httpx.Timeout(30, connect=5)) as client:
            async with client.stream("POST", url, params={"output_format": "ulaw_8000"}, json=body,
                                     headers=headers) as resp:
                if resp.status_code >= 400:
                    detail = (await resp.aread())[:300]
                    raise TTSError(f"ElevenLabs error {resp.status_code}: {detail!r}")
                async for chunk in resp.aiter_bytes():
                    if chunk:
                        yield chunk
