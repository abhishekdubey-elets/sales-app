"""Provider-independent LLM interface used by the voice engine and post-call analysis."""

from abc import ABC, abstractmethod
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field

from app.schemas.ai import CallIntelligence


class LLMError(Exception):
    pass


@dataclass
class ToolSpec:
    name: str
    description: str
    parameters: dict  # JSON schema (object)


@dataclass
class AgentAction:
    name: str  # transfer_to_human | end_call | record_opt_out | schedule_meeting
    args: dict = field(default_factory=dict)
    id: str | None = None


@dataclass
class TurnResult:
    text: str
    actions: list[AgentAction]
    refused: bool = False
    awaiting_tool_results: bool = False


TextSink = Callable[[str], Awaitable[None]]


class LLMConversation(ABC):
    @abstractmethod
    async def respond(self, user_text: str | None, on_text: TextSink | None = None,
                      tool_results: dict[str, str] | None = None) -> TurnResult:
        """Send the customer's utterance (and/or results for the previous turn's actions), stream the reply
        text to `on_text`, and return the text plus any requested actions."""


class LLMProvider(ABC):
    name = "base"

    @abstractmethod
    def is_configured(self) -> bool: ...

    @property
    @abstractmethod
    def model(self) -> str: ...

    @abstractmethod
    def start_conversation(self, system_prompt: str, tools: list[ToolSpec],
                           history: list[tuple[str, str]] | None = None) -> LLMConversation: ...

    @abstractmethod
    async def analyze_call(self, system_prompt: str, transcript: str) -> CallIntelligence: ...
