from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass


@dataclass
class STTEvent:
    kind: str  # transcript | speech_started | utterance_end
    text: str = ""
    is_final: bool = False
    speech_final: bool = False


class STTSession(ABC):
    @abstractmethod
    async def send_audio(self, chunk: bytes) -> None: ...

    @abstractmethod
    def events(self) -> AsyncIterator[STTEvent]: ...

    @abstractmethod
    async def close(self) -> None: ...


class STTProvider(ABC):
    name = "base"

    @abstractmethod
    def is_configured(self) -> bool: ...

    @abstractmethod
    async def start(self, *, language: str, encoding: str, sample_rate: int) -> STTSession: ...
