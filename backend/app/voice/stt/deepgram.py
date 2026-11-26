"""Deepgram live transcription over WebSocket."""

import asyncio
import contextlib
import json
import logging
from collections.abc import AsyncIterator
from urllib.parse import urlencode

from websockets.asyncio.client import ClientConnection, connect

from app.core.config import settings
from app.voice.stt.base import STTEvent, STTProvider, STTSession

log = logging.getLogger(__name__)


class DeepgramSession(STTSession):
    def __init__(self, ws: ClientConnection) -> None:
        self._ws = ws
        self._keepalive = asyncio.create_task(self._ping())

    async def _ping(self) -> None:
        with contextlib.suppress(Exception):
            while True:
                await asyncio.sleep(5)
                await self._ws.send(json.dumps({"type": "KeepAlive"}))

    async def send_audio(self, chunk: bytes) -> None:
        await self._ws.send(chunk)

    async def events(self) -> AsyncIterator[STTEvent]:
        async for raw in self._ws:
            if isinstance(raw, bytes):
                continue
            msg = json.loads(raw)
            kind = msg.get("type")
            if kind == "Results":
                alts = (msg.get("channel") or {}).get("alternatives") or [{}]
                text = (alts[0].get("transcript") or "").strip()
                yield STTEvent("transcript", text=text, is_final=bool(msg.get("is_final")),
                               speech_final=bool(msg.get("speech_final")))
            elif kind == "SpeechStarted":
                yield STTEvent("speech_started")
            elif kind == "UtteranceEnd":
                yield STTEvent("utterance_end")

    async def close(self) -> None:
        self._keepalive.cancel()
        with contextlib.suppress(Exception):
            await self._ws.send(json.dumps({"type": "CloseStream"}))
            await self._ws.close()


class DeepgramSTT(STTProvider):
    name = "deepgram"

    def is_configured(self) -> bool:
        return bool(settings.DEEPGRAM_API_KEY)

    async def start(self, *, language: str, encoding: str, sample_rate: int) -> STTSession:
        params = {
            "model": settings.DEEPGRAM_MODEL, "language": language, "encoding": encoding,
            "sample_rate": sample_rate, "channels": 1, "interim_results": "true", "punctuate": "true",
            "smart_format": "true", "endpointing": 300, "utterance_end_ms": 1000, "vad_events": "true",
        }
        ws = await connect(
            f"wss://api.deepgram.com/v1/listen?{urlencode(params)}",
            additional_headers={"Authorization": f"Token {settings.DEEPGRAM_API_KEY}"},
            max_size=None,
        )
        return DeepgramSession(ws)
