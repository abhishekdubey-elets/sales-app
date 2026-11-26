from abc import ABC, abstractmethod
from collections.abc import AsyncIterator


class TTSProvider(ABC):
    name = "base"
    #: encoding of the audio yielded by `synthesize` (8 kHz mono)
    output_encoding = "mulaw"

    @abstractmethod
    def is_configured(self) -> bool: ...

    @abstractmethod
    def synthesize(self, text: str, *, voice_id: str | None, language: str, speed: float) -> AsyncIterator[bytes]:
        """Yield 8 kHz audio chunks in `output_encoding` as they are produced."""
