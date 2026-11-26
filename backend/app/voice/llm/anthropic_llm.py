"""Claude (Anthropic API) implementation of the LLM interface.

* Live turns stream text so TTS can start speaking at the first sentence; tools carry call-control actions.
* Post-call analysis uses structured outputs (`messages.parse`) into the CallIntelligence schema.
* Server-side refusal fallback is enabled (`fallbacks="default"`), and refusals are handled explicitly.
"""

import json
import logging

import anthropic

from app.core.config import settings
from app.schemas.ai import CallIntelligence
from app.voice.llm.base import AgentAction, LLMConversation, LLMError, LLMProvider, TextSink, ToolSpec, TurnResult

log = logging.getLogger(__name__)

FALLBACK_BETA = "server-side-fallback-2026-07-01"
REALTIME_MAX_TOKENS = 4096
ANALYSIS_MAX_TOKENS = 16000


class AnthropicConversation(LLMConversation):
    def __init__(self, client: anthropic.AsyncAnthropic, model: str, system_prompt: str, tools: list[ToolSpec],
                 history: list[tuple[str, str]] | None = None) -> None:
        self._client = client
        self._model = model
        # Stable prefix → prompt caching keeps per-turn latency and cost down across a call.
        self._system = [{"type": "text", "text": system_prompt, "cache_control": {"type": "ephemeral"}}]
        self._tools = [
            {"name": t.name, "description": t.description, "input_schema": t.parameters, "strict": True}
            for t in tools
        ]
        self._messages: list[dict] = []
        for role, text in history or []:
            self._messages.append({"role": role, "content": text})
        self._pending_tool_ids: list[str] = []

    async def respond(self, user_text: str | None, on_text: TextSink | None = None,
                      tool_results: dict[str, str] | None = None) -> TurnResult:
        results = tool_results or {}
        content: list[dict] = [
            {"type": "tool_result", "tool_use_id": tid, "content": results.get(tid, "done")}
            for tid in self._pending_tool_ids
        ]
        if user_text:
            content.append({"type": "text", "text": user_text})
        if not content:
            raise LLMError("respond() needs user text or pending tool results")
        self._pending_tool_ids = []
        self._messages.append({"role": "user", "content": content})

        try:
            async with self._client.beta.messages.stream(
                model=self._model,
                max_tokens=REALTIME_MAX_TOKENS,
                system=self._system,
                messages=self._messages,
                tools=self._tools or anthropic.omit,
                output_config={"effort": settings.LLM_REALTIME_EFFORT},
                betas=[FALLBACK_BETA],
                fallbacks="default",
            ) as stream:
                async for text in stream.text_stream:
                    if on_text:
                        await on_text(text)
                final = await stream.get_final_message()
        except anthropic.RateLimitError as exc:
            raise LLMError("LLM rate limited") from exc
        except anthropic.APIStatusError as exc:
            raise LLMError(f"LLM error {exc.status_code}: {exc.message}") from exc
        except anthropic.APIConnectionError as exc:
            raise LLMError("LLM unreachable") from exc

        # Keep the full assistant content (thinking + tool_use blocks) so the next turn is valid.
        self._messages.append({"role": "assistant", "content": final.content})
        if final.stop_reason == "refusal":
            return TurnResult(text="", actions=[AgentAction("end_call", {"reason": "model_refusal"})], refused=True)

        text_parts, actions = [], []
        for block in final.content:
            if block.type == "text":
                text_parts.append(block.text)
            elif block.type == "tool_use":
                args = block.input if isinstance(block.input, dict) else json.loads(block.input or "{}")
                actions.append(AgentAction(block.name, args, block.id))
                self._pending_tool_ids.append(block.id)
        return TurnResult(text="".join(text_parts).strip(), actions=actions,
                          awaiting_tool_results=final.stop_reason == "tool_use")


class AnthropicLLM(LLMProvider):
    name = "anthropic"

    def __init__(self) -> None:
        self._client: anthropic.AsyncAnthropic | None = None

    def is_configured(self) -> bool:
        import os

        return bool(settings.ANTHROPIC_API_KEY or os.environ.get("ANTHROPIC_API_KEY")
                    or os.environ.get("ANTHROPIC_AUTH_TOKEN"))

    @property
    def model(self) -> str:
        return settings.LLM_MODEL

    @property
    def client(self) -> anthropic.AsyncAnthropic:
        if self._client is None:
            kwargs = {"api_key": settings.ANTHROPIC_API_KEY} if settings.ANTHROPIC_API_KEY else {}
            self._client = anthropic.AsyncAnthropic(max_retries=2, **kwargs)
        return self._client

    def start_conversation(self, system_prompt: str, tools: list[ToolSpec],
                           history: list[tuple[str, str]] | None = None) -> LLMConversation:
        return AnthropicConversation(self.client, self.model, system_prompt, tools, history)

    async def analyze_call(self, system_prompt: str, transcript: str) -> CallIntelligence:
        try:
            response = await self.client.beta.messages.parse(
                model=self.model,
                max_tokens=ANALYSIS_MAX_TOKENS,
                system=system_prompt,
                messages=[{"role": "user", "content": transcript}],
                output_format=CallIntelligence,
                output_config={"effort": settings.LLM_ANALYSIS_EFFORT},
                betas=[FALLBACK_BETA],
                fallbacks="default",
            )
        except anthropic.APIStatusError as exc:
            raise LLMError(f"LLM error {exc.status_code}: {exc.message}") from exc
        except anthropic.APIConnectionError as exc:
            raise LLMError("LLM unreachable") from exc
        if response.stop_reason == "refusal":
            category = getattr(response.stop_details, "category", None) if response.stop_details else None
            raise LLMError(f"Analysis declined by the model (category: {category})")
        if response.parsed_output is None:
            raise LLMError(f"Analysis returned no structured output (stop_reason={response.stop_reason})")
        return response.parsed_output
