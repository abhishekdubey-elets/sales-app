"""Real-time AI voice conversation over a provider media stream.

Pipeline per call:  provider audio → STT (streaming) → LLM (streaming, tools) → TTS → provider audio.

* The opening line (AI disclosure + recording notice + greeting) is fixed text, never LLM-generated, so the
  disclosure can't be skipped.
* Barge-in: if the prospect starts talking while the agent is speaking, queued speech is dropped, the provider's
  playback buffer is cleared and the in-flight LLM turn is cancelled.
* Call control (hand-off, meeting request, opt-out, end) arrives as LLM tool calls.
* On exit the transcript is saved and post-call analysis is scheduled.
"""

import asyncio
import contextlib
import json
import logging
import re
import time
import uuid

from app.core.config import settings
from app.core.database import SessionLocal
from app.core.tasks import spawn
from app.models import AIAgent, AICall, Lead
from app.models.enums import TERMINAL_CALL_STATUSES
from app.services import ai_calls as ai_svc
from app.services import compliance
from app.services.leads import add_activity
from app.services.notifications import commit_and_deliver
from app.services.org import get_org_settings
from app.telephony.base import TelephonyError, TelephonyProvider, build_callbacks
from app.telephony.media import MediaAdapter
from app.voice.audio import convert
from app.voice.languages import language
from app.voice.llm.base import LLMConversation, LLMError, LLMProvider, TurnResult
from app.voice.prompts import CALL_TOOLS, live_system_prompt, opening_line
from app.voice.stt.base import STTProvider, STTSession
from app.voice.tts.base import TTSProvider

log = logging.getLogger(__name__)

_SENTENCE = re.compile(r"(.+?[.!?।](?:\s+|$))", re.S)


class WebSocketLike:
    """The subset of starlette's WebSocket the engine uses (lets tests pass a fake)."""

    async def receive_text(self) -> str: ...
    async def send_text(self, data: str) -> None: ...
    async def close(self, code: int = 1000) -> None: ...


class VoiceCallSession:
    def __init__(
        self, *, ws: WebSocketLike, adapter: MediaAdapter, ai_call_id: uuid.UUID, provider: TelephonyProvider,
        llm: LLMProvider, stt: STTProvider, tts: TTSProvider, session_factory=SessionLocal,
        silence_prompt_seconds: float = 20.0, silence_hangup_seconds: float = 35.0,
    ) -> None:
        self.ws, self.adapter, self.ai_call_id = ws, adapter, ai_call_id
        self.provider, self.llm, self.stt, self.tts = provider, llm, stt, tts
        self._sf = session_factory
        self.transcript: list[dict] = []
        self._t0 = time.monotonic()
        self._speak_q: asyncio.Queue[str] = asyncio.Queue()
        self._synthesizing = False
        self._play_until = 0.0
        self._marks: set[str] = set()
        self._mark_seq = 0
        self._ended = asyncio.Event()
        self._closing = False
        self._turn_task: asyncio.Task | None = None
        self._speaker_task: asyncio.Task | None = None
        self._buffer: list[str] = []
        self._last_activity = time.monotonic()
        self._prompted_silence = False
        self._silence_prompt = silence_prompt_seconds
        self._silence_hangup = silence_hangup_seconds
        self.end_reason: str | None = None
        self._hangup_on_end = True
        self.conv: LLMConversation | None = None
        self.stt_session: STTSession | None = None
        self.agent: AIAgent | None = None
        self.lead: Lead | None = None
        self.provider_call_id: str | None = None

    # ── lifecycle ────────────────────────────────────────────────────────────
    async def run(self) -> None:
        tasks: list[asyncio.Task] = []
        try:
            if not await self._load():
                return
            self.lang = language(self.agent.language)
            try:
                self.stt_session = await self.stt.start(
                    language=self.lang.stt_code, encoding=self.adapter.encoding, sample_rate=self.adapter.sample_rate
                )
            except Exception:  # noqa: BLE001
                log.exception("STT unavailable for %s", self.ai_call_id)
                self.stt_session = None
            self._speaker_task = asyncio.create_task(self._speaker())
            tasks = [asyncio.create_task(self._receive()), asyncio.create_task(self._deadline()),
                     asyncio.create_task(self._silence_watchdog())]
            if self.stt_session is not None:
                tasks.append(asyncio.create_task(self._listen()))
            await self._say(self.opening, record=True)
            if self.stt_session is None:
                await self._say(self.lang.error_line, record=True)
                await self._drain()
                await self._finish("stt_unavailable")
            await self._ended.wait()
        finally:
            for t in tasks + [self._turn_task, self._speaker_task]:
                if t and not t.done():
                    t.cancel()
            for t in tasks + [self._turn_task, self._speaker_task]:
                if t:
                    with contextlib.suppress(asyncio.CancelledError, Exception):
                        await t
            if self.stt_session is not None:
                with contextlib.suppress(Exception):
                    await self.stt_session.close()
            await self._persist()
            with contextlib.suppress(Exception):
                await self.ws.close()

    async def _load(self) -> bool:
        async with self._sf() as db:
            call = await db.get(AICall, self.ai_call_id)
            if call is None or call.status in TERMINAL_CALL_STATUSES:
                log.warning("media stream for unknown or finished AI call %s", self.ai_call_id)
                return False
            self.agent = await db.get(AIAgent, call.agent_id)
            self.lead = await db.get(Lead, call.lead_id) if call.lead_id else None
            self.provider_call_id = call.provider_call_id
            org = await get_org_settings(db)
            recording = org.recording_enabled and self.agent.recording_enabled
            self.opening = opening_line(self.agent, self.lead, org.ai_disclosure_text,
                                        org.recording_disclosure_text if recording else None)
            await ai_svc.mark_connected(db, call)
        self.conv = self.llm.start_conversation(live_system_prompt(self.agent, self.lead, self.opening), CALL_TOOLS)
        return True

    async def _persist(self) -> None:
        if self.agent is None:
            return
        try:
            async with self._sf() as db:
                call = await db.get(AICall, self.ai_call_id)
                if call is None:
                    return
                await ai_svc.save_transcript(db, call, self.transcript)
                await commit_and_deliver(db)
            if any(s["speaker"] == "customer" for s in self.transcript):
                await spawn(ai_svc.run_analysis(self.ai_call_id))
        except Exception:  # noqa: BLE001
            log.exception("failed to persist AI call %s", self.ai_call_id)

    async def _finish(self, reason: str, hangup: bool = True) -> None:
        if self._ended.is_set():
            return
        self.end_reason = reason
        if hangup and self._hangup_on_end and self.provider.supports_hangup and self.provider_call_id:
            try:
                await self.provider.hangup(self.provider_call_id)
            except TelephonyError:
                log.warning("hangup failed for %s", self.ai_call_id)
        self._ended.set()

    # ── inbound audio / STT ─────────────────────────────────────────────────
    async def _receive(self) -> None:
        try:
            while not self._ended.is_set():
                raw = await self.ws.receive_text()
                ev = self.adapter.parse(json.loads(raw))
                if ev.kind == "audio" and self.stt_session is not None:
                    await self.stt_session.send_audio(ev.audio)
                elif ev.kind == "mark" and ev.mark:
                    self._marks.discard(ev.mark)
                elif ev.kind == "stop":
                    await self._finish("hangup", hangup=False)
        except Exception:  # noqa: BLE001 - socket closed by provider
            await self._finish("hangup", hangup=False)

    async def _listen(self) -> None:
        try:
            async for e in self.stt_session.events():
                if self._ended.is_set():
                    break
                if e.kind == "transcript":
                    if e.text:
                        self._last_activity = time.monotonic()
                        self._prompted_silence = False
                        if self._agent_busy() and len(e.text.split()) >= 2:
                            await self._barge_in()
                        if e.is_final:
                            self._buffer.append(e.text)
                    if e.speech_final and self._buffer:
                        self._utterance_complete()
                elif e.kind == "utterance_end" and self._buffer:
                    self._utterance_complete()
        except Exception:  # noqa: BLE001
            log.exception("STT stream ended for %s", self.ai_call_id)

    def _utterance_complete(self) -> None:
        text = " ".join(self._buffer).strip()
        self._buffer.clear()
        if not text or self._closing:
            return
        if self._turn_task and not self._turn_task.done():
            self._turn_task.cancel()
        self._turn_task = asyncio.create_task(self._turn(text))

    # ── turns & actions ─────────────────────────────────────────────────────
    async def _turn(self, text: str) -> None:
        self._record("customer", text)
        spoken: list[str] = []
        pending = ""

        async def on_text(delta: str) -> None:
            nonlocal pending
            pending += delta
            while True:
                m = _SENTENCE.match(pending)
                if not m:
                    break
                sentence, pending = m.group(1), pending[m.end():]
                spoken.append(sentence.strip())
                await self._say(sentence)

        try:
            result = await self.conv.respond(text, on_text)
            if pending.strip():
                spoken.append(pending.strip())
                await self._say(pending)
            if spoken:
                self._record("agent", " ".join(spoken))
            await self._handle_actions(result, on_text_factory=lambda: on_text, depth=0)
        except asyncio.CancelledError:
            if spoken:
                self._record("agent", " ".join(spoken) + " [interrupted]")
            raise
        except LLMError:
            log.exception("LLM failure on AI call %s", self.ai_call_id)
            await self._close_with(self.lang.error_line, "llm_error")

    async def _handle_actions(self, result: TurnResult, on_text_factory, depth: int) -> None:
        if result.refused:
            await self._close_with(self.lang.closing_line, "model_refusal")
            return
        terminal = None
        tool_results: dict[str, str] = {}
        for action in result.actions:
            if action.name == "schedule_meeting":
                async with self._sf() as db:
                    call = await db.get(AICall, self.ai_call_id)
                    msg = await ai_svc.record_meeting_request(
                        db, call, action.args.get("preferred_time", ""), action.args.get("preferred_datetime_iso"),
                        action.args.get("notes", ""))
                    await commit_and_deliver(db)
                self._record("system", f"Meeting requested: {action.args.get('preferred_time', '')}")
                if action.id:
                    tool_results[action.id] = msg
            elif action.name in ("transfer_to_human", "record_opt_out"):
                terminal = action
            elif action.name == "end_call" and terminal is None:
                terminal = action

        if terminal is None:
            if result.awaiting_tool_results and tool_results and depth < 2:
                spoken: list[str] = []
                pending = ""

                async def on_text(delta: str) -> None:
                    nonlocal pending
                    pending += delta
                    while (m := _SENTENCE.match(pending)) is not None:
                        sentence, pending = m.group(1), pending[m.end():]
                        spoken.append(sentence.strip())
                        await self._say(sentence)

                follow = await self.conv.respond(None, on_text, tool_results)
                if pending.strip():
                    spoken.append(pending.strip())
                    await self._say(pending)
                if spoken:
                    self._record("agent", " ".join(spoken))
                await self._handle_actions(follow, on_text_factory, depth + 1)
            return

        reason = terminal.args.get("reason", "")
        if terminal.name == "transfer_to_human":
            await self._handoff(reason)
        elif terminal.name == "record_opt_out":
            async with self._sf() as db:
                call = await db.get(AICall, self.ai_call_id)
                await compliance.record_opt_out(db, phone_hash=call.phone_hash, reason=reason or "Requested on AI call",
                                                source="ai_call", lead_id=call.lead_id)
                if call.lead_id:
                    await add_activity(db, call.lead_id, "opt_out", "Opted out on AI call", reason, None, call.id)
                await db.commit()
            self._record("system", "Prospect opted out of future calls")
            await self._close_with(self.lang.opt_out_line, "opted_out")
        else:
            await self._drain()
            await self._finish(reason or "completed")

    async def _handoff(self, reason: str) -> None:
        mode = self.provider.transfer_mode
        async with self._sf() as db:
            call = await db.get(AICall, self.ai_call_id)
            lead = await db.get(Lead, call.lead_id) if call.lead_id else None
            salesperson = await ai_svc.salesperson_for_lead(db, lead)
            number = salesperson.calling_number if salesperson else None
            transferred = False
            if number and mode in ("api", "flow"):
                self._closing = True
                first = salesperson.full_name.split()[0]
                line = (f"Of course. I'm connecting you to {first} now." if self.agent.language != "hi-IN"
                        else f"ज़रूर, मैं आपको अभी {first} से जोड़ रहा हूँ।")
                await self._say(line, record=True)
                await self._drain()
                call.transfer_to_number = number
                await db.commit()  # answer/transfer-target webhooks read this number
                if mode == "api":
                    try:
                        transferred = await self.provider.transfer(
                            call.provider_call_id, number, build_callbacks(self.provider.name, "ai", call.id),
                            settings.TELEPHONY_CALLER_ID)
                    except TelephonyError:
                        log.exception("live transfer failed for %s", call.id)
                else:  # flow: the provider's call flow dials transfer-target after the stream closes
                    transferred = True
            await ai_svc.record_handoff(db, call, reason or "Prospect asked for a salesperson", transferred)
            await commit_and_deliver(db)
        self._record("system", f"Human hand-off requested{' — transferred live' if transferred else ''}: {reason}")
        if transferred:
            self._hangup_on_end = False
            await self._finish("transferred", hangup=False)
        else:
            await self._close_with(self.lang.handoff_line, "handoff")

    async def _close_with(self, line: str, reason: str) -> None:
        self._closing = True
        await self._say(line, record=True)
        await self._drain()
        await self._finish(reason)

    # ── speech output ───────────────────────────────────────────────────────
    async def _say(self, text: str, record: bool = False) -> None:
        text = text.strip()
        if not text:
            return
        if record:
            self._record("agent", text)
        await self._speak_q.put(text)

    async def _speaker(self) -> None:
        bytes_per_second = 8000 if self.adapter.encoding == "mulaw" else 16000
        while True:
            text = await self._speak_q.get()
            self._synthesizing = True
            pending = b""
            try:
                async for chunk in self.tts.synthesize(text, voice_id=self.agent.voice_id,
                                                       language=self.lang.tts_code, speed=self.agent.speaking_speed):
                    pending += convert(chunk, self.tts.output_encoding, self.adapter.encoding)
                    cut = len(pending) - (len(pending) % self.adapter.chunk_bytes)
                    if cut:
                        await self._send_audio(pending[:cut], bytes_per_second)
                        pending = pending[cut:]
                if pending:
                    await self._send_audio(pending, bytes_per_second)
                self._mark_seq += 1
                mark = f"m{self._mark_seq}"
                msg = self.adapter.mark_message(mark)
                if msg:
                    self._marks.add(mark)
                    await self.ws.send_text(json.dumps(msg))
            except asyncio.CancelledError:
                raise
            except Exception:  # noqa: BLE001
                log.exception("TTS failed on AI call %s", self.ai_call_id)
            finally:
                self._synthesizing = False
                self._speak_q.task_done()

    async def _send_audio(self, audio: bytes, bytes_per_second: int) -> None:
        for msg in self.adapter.audio_messages(audio):
            await self.ws.send_text(json.dumps(msg))
        now = time.monotonic()
        self._play_until = max(self._play_until, now) + len(audio) / bytes_per_second

    def _agent_busy(self) -> bool:
        return (
            not self._speak_q.empty() or self._synthesizing or time.monotonic() < self._play_until
            or bool(self._marks) or bool(self._turn_task and not self._turn_task.done())
        )

    async def _barge_in(self) -> None:
        if self._closing:
            return
        while not self._speak_q.empty():
            self._speak_q.get_nowait()
            self._speak_q.task_done()
        if self._speaker_task and self._synthesizing:
            self._speaker_task.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await self._speaker_task
            self._synthesizing = False
            self._speaker_task = asyncio.create_task(self._speaker())
        clear = self.adapter.clear_message()
        if clear:
            with contextlib.suppress(Exception):
                await self.ws.send_text(json.dumps(clear))
        self._marks.clear()
        self._play_until = 0.0
        if self._turn_task and not self._turn_task.done() and self._turn_task is not asyncio.current_task():
            self._turn_task.cancel()

    async def _drain(self, timeout: float = 20.0) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            idle = self._speak_q.empty() and not self._synthesizing
            played = not self._marks or time.monotonic() > self._play_until + 0.5
            if idle and played and time.monotonic() >= self._play_until:
                return
            await asyncio.sleep(0.05)

    # ── timers ──────────────────────────────────────────────────────────────
    async def _deadline(self) -> None:
        await asyncio.sleep(self.agent.max_call_duration_seconds)
        if not self._ended.is_set():
            await self._barge_in()
            await self._close_with(self.lang.timeout_line, "max_duration")

    async def _silence_watchdog(self) -> None:
        while not self._ended.is_set():
            await asyncio.sleep(1)
            if self._agent_busy() or self._closing:
                self._last_activity = max(self._last_activity, time.monotonic() - 1)
                continue
            idle = time.monotonic() - self._last_activity
            if idle > self._silence_hangup:
                await self._close_with(self.lang.closing_line, "silence")
            elif idle > self._silence_prompt and not self._prompted_silence:
                self._prompted_silence = True
                await self._say(self.lang.still_there_line, record=True)

    def _record(self, speaker: str, text: str) -> None:
        self.transcript.append({"speaker": speaker, "text": text,
                                "offset_ms": int((time.monotonic() - self._t0) * 1000)})
