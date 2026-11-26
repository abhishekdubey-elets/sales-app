"""Bidirectional media-stream message formats per provider (WebSocket JSON frames)."""

import base64
from dataclasses import dataclass


@dataclass
class MediaEvent:
    kind: str  # start | audio | mark | stop | dtmf | other
    audio: bytes = b""
    stream_id: str | None = None
    provider_call_id: str | None = None
    mark: str | None = None
    params: dict | None = None


class MediaAdapter:
    encoding = "mulaw"  # audio encoding on the wire: mulaw | linear16
    sample_rate = 8000
    chunk_bytes = 640

    def __init__(self) -> None:
        self.stream_id: str | None = None

    def parse(self, msg: dict) -> MediaEvent:
        raise NotImplementedError

    def audio_messages(self, audio: bytes) -> list[dict]:
        raise NotImplementedError

    def clear_message(self) -> dict | None:
        return None

    def mark_message(self, name: str) -> dict | None:
        return None


class TwilioMediaAdapter(MediaAdapter):
    encoding = "mulaw"
    chunk_bytes = 320  # 40 ms of 8 kHz µ-law

    def parse(self, msg: dict) -> MediaEvent:
        ev = msg.get("event")
        if ev == "start":
            start = msg.get("start", {})
            self.stream_id = start.get("streamSid") or msg.get("streamSid")
            return MediaEvent("start", stream_id=self.stream_id, provider_call_id=start.get("callSid"),
                              params=start.get("customParameters") or {})
        if ev == "media":
            media = msg.get("media", {})
            if media.get("track", "inbound") != "inbound":
                return MediaEvent("other")
            return MediaEvent("audio", audio=base64.b64decode(media.get("payload", "")))
        if ev == "mark":
            return MediaEvent("mark", mark=msg.get("mark", {}).get("name"))
        if ev == "stop":
            return MediaEvent("stop")
        if ev == "dtmf":
            return MediaEvent("dtmf", params=msg.get("dtmf", {}))
        return MediaEvent("other")

    def audio_messages(self, audio: bytes) -> list[dict]:
        return [
            {"event": "media", "streamSid": self.stream_id,
             "media": {"payload": base64.b64encode(audio[i:i + self.chunk_bytes]).decode()}}
            for i in range(0, len(audio), self.chunk_bytes)
        ]

    def clear_message(self) -> dict | None:
        return {"event": "clear", "streamSid": self.stream_id}

    def mark_message(self, name: str) -> dict | None:
        return {"event": "mark", "streamSid": self.stream_id, "mark": {"name": name}}


class ExotelMediaAdapter(MediaAdapter):
    """Exotel Voicebot applet: raw 16-bit PCM, 8 kHz mono, little-endian, base64 in JSON frames."""

    encoding = "linear16"
    chunk_bytes = 3200  # multiple of 320 bytes as Exotel requires (200 ms)

    def parse(self, msg: dict) -> MediaEvent:
        ev = msg.get("event")
        if ev == "start":
            start = msg.get("start", {})
            self.stream_id = start.get("stream_sid") or msg.get("stream_sid")
            return MediaEvent("start", stream_id=self.stream_id, provider_call_id=start.get("call_sid"),
                              params=start.get("custom_parameters") or {})
        if ev == "media":
            return MediaEvent("audio", audio=base64.b64decode(msg.get("media", {}).get("payload", "")))
        if ev == "mark":
            return MediaEvent("mark", mark=msg.get("mark", {}).get("name"))
        if ev == "stop":
            return MediaEvent("stop")
        if ev == "dtmf":
            return MediaEvent("dtmf", params=msg.get("dtmf", {}))
        return MediaEvent("other")

    def audio_messages(self, audio: bytes) -> list[dict]:
        out = []
        for i in range(0, len(audio), self.chunk_bytes):
            chunk = audio[i:i + self.chunk_bytes]
            if len(chunk) % 320:
                chunk += b"\x00" * (320 - len(chunk) % 320)
            out.append({"event": "media", "stream_sid": self.stream_id,
                        "media": {"payload": base64.b64encode(chunk).decode()}})
        return out

    def clear_message(self) -> dict | None:
        return {"event": "clear", "stream_sid": self.stream_id}

    def mark_message(self, name: str) -> dict | None:
        return {"event": "mark", "stream_sid": self.stream_id, "mark": {"name": name}}


class PlivoMediaAdapter(MediaAdapter):
    encoding = "mulaw"
    chunk_bytes = 1600

    def parse(self, msg: dict) -> MediaEvent:
        ev = msg.get("event")
        if ev == "start":
            start = msg.get("start", {})
            self.stream_id = start.get("streamId")
            return MediaEvent("start", stream_id=self.stream_id, provider_call_id=start.get("callId"),
                              params=msg.get("extra_headers") or {})
        if ev == "media":
            return MediaEvent("audio", audio=base64.b64decode(msg.get("media", {}).get("payload", "")))
        if ev == "playedStream":
            return MediaEvent("mark", mark=msg.get("name"))
        if ev == "stop":
            return MediaEvent("stop")
        if ev == "dtmf":
            return MediaEvent("dtmf", params=msg.get("dtmf", {}))
        return MediaEvent("other")

    def audio_messages(self, audio: bytes) -> list[dict]:
        return [
            {"event": "playAudio", "media": {"contentType": "audio/x-mulaw", "sampleRate": 8000,
                                             "payload": base64.b64encode(audio[i:i + self.chunk_bytes]).decode()}}
            for i in range(0, len(audio), self.chunk_bytes)
        ]

    def clear_message(self) -> dict | None:
        return {"event": "clearAudio", "streamId": self.stream_id}

    def mark_message(self, name: str) -> dict | None:
        return {"event": "checkpoint", "streamId": self.stream_id, "name": name}
