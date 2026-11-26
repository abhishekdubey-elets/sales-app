import asyncio
import json

import sqlalchemy as sa

from app.core.database import SessionLocal
from app.core.security import webhook_token
from app.models import AIAgent, AICall, AICampaignLead, Followup, Lead, Notification
from app.schemas.ai import CallIntelligence
from app.voice import registry as voice_registry
from app.voice.audio import pcm16_to_ulaw, ulaw_to_pcm16
from app.voice.engine import VoiceCallSession
from app.voice.llm.base import AgentAction, LLMConversation, LLMProvider, TurnResult
from app.voice.prompts import AGENT_TEMPLATES
from app.voice.stt.base import STTEvent, STTProvider, STTSession
from app.voice.tts.base import TTSProvider
from app.workers import campaign_runner
from tests.conftest import login, make_lead

# ── fakes ──────────────────────────────────────────────────────────────────


class FakeSTTSession(STTSession):
    def __init__(self):
        self.q: asyncio.Queue = asyncio.Queue()
        self.audio = 0

    async def send_audio(self, chunk):
        self.audio += len(chunk)

    async def events(self):
        while True:
            ev = await self.q.get()
            if ev is None:
                return
            yield ev

    async def close(self):
        await self.q.put(None)


class FakeSTT(STTProvider):
    name = "fake-stt"

    def __init__(self):
        self.session = FakeSTTSession()

    def is_configured(self):
        return True

    async def start(self, **kw):
        return self.session


class FakeTTS(TTSProvider):
    name = "fake-tts"
    output_encoding = "mulaw"

    def __init__(self):
        self.spoken: list[str] = []

    def is_configured(self):
        return True

    async def synthesize(self, text, **kw):
        self.spoken.append(text)
        yield b"\xff" * 320


class ScriptedConversation(LLMConversation):
    def __init__(self, script):
        self.script = list(script)
        self.calls = []

    async def respond(self, user_text, on_text=None, tool_results=None):
        self.calls.append((user_text, tool_results))
        text, actions, awaiting = self.script.pop(0)
        if on_text and text:
            for word in text.split(" "):
                await on_text(word + " ")
        return TurnResult(text=text, actions=actions, awaiting_tool_results=awaiting)


class FakeLLM(LLMProvider):
    name = "fake-llm"

    def __init__(self, script=None, intel=None):
        self.script = script or []
        self.intel = intel
        self.systems = []
        self.conv = None

    def is_configured(self):
        return True

    @property
    def model(self):
        return "fake"

    def start_conversation(self, system_prompt, tools, history=None):
        self.systems.append(system_prompt)
        self.conv = ScriptedConversation(self.script)
        return self.conv

    async def analyze_call(self, system_prompt, transcript):
        return self.intel


class FakeWS:
    def __init__(self):
        self.inbox: asyncio.Queue = asyncio.Queue()
        self.sent: list[dict] = []
        self.closed = False

    async def receive_text(self):
        msg = await self.inbox.get()
        if msg is None:
            raise RuntimeError("closed")
        return msg

    async def send_text(self, data):
        self.sent.append(json.loads(data))

    async def close(self, code=1000):
        self.closed = True


def intel(**kw) -> CallIntelligence:
    base = dict(summary="Interested in sponsoring the summit.", customer_requirements=["Sponsorship deck"],
                interest_level="high", budget_information=None, decision_maker_information="Is the decision maker",
                next_action="Send deck", followup_recommendation="Call on Friday", followup_date=None,
                qualification_score=85, sentiment="positive", lead_status_suggestion="interested")
    base.update(kw)
    return CallIntelligence(**base)


def enable_voice(llm=None, stt=None, tts=None):
    llm, stt, tts = llm or FakeLLM(), stt or FakeSTT(), tts or FakeTTS()
    voice_registry.set_override("llm", llm)
    voice_registry.set_override("stt", stt)
    voice_registry.set_override("tts", tts)
    return llm, stt, tts


async def create_agent(client, headers, **overrides) -> dict:
    body = {**AGENT_TEMPLATES[1], **overrides}
    r = await client.post("/api/v1/ai/agents", headers=headers, json=body)
    assert r.status_code == 201, r.text
    return r.json()


# ── tests ──────────────────────────────────────────────────────────────────


def test_mulaw_roundtrip():
    pcm = b"".join(int(v).to_bytes(2, "little", signed=True) for v in (0, 1000, -1000, 8000, -32000, 32000))
    back = ulaw_to_pcm16(pcm16_to_ulaw(pcm))
    for a, b in zip(memoryview(pcm).cast("h"), memoryview(back).cast("h"), strict=True):
        assert abs(a - b) <= max(64, abs(a) // 16)


async def test_agents_and_permissions(client, org):
    admin = await login(client, "admin@test.local")
    templates = (await client.get("/api/v1/ai/agents/templates", headers=admin)).json()
    assert [t["name"] for t in templates] == [t["name"] for t in AGENT_TEMPLATES]
    agent = await create_agent(client, admin, language="hi-IN")
    assert agent["language"] == "hi-IN" and agent["total_calls"] == 0
    mgr = await login(client, "mgr.a@test.local")
    assert (await client.get("/api/v1/ai/agents", headers=mgr)).status_code == 200
    assert (await client.patch(f"/api/v1/ai/agents/{agent['id']}", headers=mgr, json={"name": "x"})).status_code == 403
    ex = await login(client, "ex1@test.local")
    assert (await client.get("/api/v1/ai/agents", headers=ex)).status_code == 403
    r = await client.post(f"/api/v1/ai/agents/{agent['id']}/test-reply", headers=admin, json={"message": "Hi"})
    assert r.status_code == 503 and r.json()["code"] == "llm_not_configured"


async def test_campaign_requires_voice_and_telephony(client, org, provider):
    admin = await login(client, "admin@test.local")
    agent = await create_agent(client, admin)
    c = (await client.post("/api/v1/ai/campaigns", headers=admin, json={"name": "Q1", "agent_id": agent["id"]})).json()
    lead = await make_lead("L", "+919000000201", org["ex1"].id)
    await client.post(f"/api/v1/ai/campaigns/{c['id']}/leads", headers=admin, json={"lead_ids": [str(lead.id)]})
    r = await client.post(f"/api/v1/ai/campaigns/{c['id']}/start", headers=admin)
    assert r.status_code == 503 and r.json()["code"] == "voice_not_configured"
    assert provider.ai_placed == []


async def test_campaign_runner_retries_and_concurrency(client, org, provider):
    enable_voice()
    admin = await login(client, "admin@test.local")
    agent = await create_agent(client, admin)
    c = (await client.post("/api/v1/ai/campaigns", headers=admin, json={
        "name": "Outreach", "agent_id": agent["id"], "max_concurrent_calls": 2, "max_attempts": 2,
        "retry_delay_minutes": 30,
        "schedule": {"timezone": "Asia/Kolkata", "days_of_week": [1, 2, 3, 4, 5, 6, 7], "start_time": "00:00",
                     "end_time": "23:59"}})).json()
    leads = [await make_lead(f"L{i}", f"+91900000030{i}", org["ex1"].id) for i in range(3)]
    opted = await make_lead("Opted", "+919000000309", org["ex1"].id, opted_out=True)
    added = (await client.post(f"/api/v1/ai/campaigns/{c['id']}/leads", headers=admin,
                               json={"lead_ids": [str(x.id) for x in leads + [opted]]})).json()
    assert added == {"added": 3, "skipped": 1}
    assert (await client.post(f"/api/v1/ai/campaigns/{c['id']}/start", headers=admin)).json()["status"] == "running"

    await campaign_runner.tick()
    assert len(provider.ai_placed) == 2  # max_concurrent_calls
    async with SessionLocal() as db:
        calls = (await db.execute(sa.select(AICall).order_by(AICall.created_at))).scalars().unique().all()
    assert all(x.campaign_id is not None and str(x.agent_id) == agent["id"] for x in calls)

    first, second = calls
    hook = "/api/v1/webhooks/telephony/fake/status"
    await client.post(hook, params={"kind": "ai", "cid": str(first.id), "wt": webhook_token("ai", first.id),
                                    "status": "not_answered"})
    await client.post(hook, params={"kind": "ai", "cid": str(second.id), "wt": webhook_token("ai", second.id),
                                    "status": "connected"})
    await client.post(hook, params={"kind": "ai", "cid": str(second.id), "wt": webhook_token("ai", second.id),
                                    "status": "completed", "duration": "75"})
    async with SessionLocal() as db:
        cl = {x.lead_id: x for x in (await db.execute(sa.select(AICampaignLead))).scalars()}
    assert cl[first.lead_id].status == "pending" and cl[first.lead_id].next_attempt_at is not None
    assert cl[second.lead_id].status == "completed"

    await campaign_runner.tick()  # third lead now; the retry is not due yet
    assert len(provider.ai_placed) == 3
    stats = (await client.get(f"/api/v1/ai/campaigns/{c['id']}", headers=admin)).json()["stats"]
    assert stats["total_leads"] == 3 and stats["connected"] == 1 and stats["not_answered"] == 1
    logs = (await client.get(f"/api/v1/ai/campaigns/{c['id']}/logs", headers=admin)).json()
    assert any(entry["event"] == "retry_scheduled" for entry in logs["items"])
    dash = (await client.get("/api/v1/ai/dashboard", headers=admin)).json()
    assert dash["total_calls"] == 3 and dash["in_progress"] == 1


async def test_voice_engine_conversation(client, org, provider):
    script = [
        ("Great, I'll note a meeting for tomorrow at 11.",
         [AgentAction("schedule_meeting", {"preferred_time": "tomorrow 11am", "preferred_datetime_iso": None,
                                           "notes": "Sponsorship"}, "t1")], True),
        ("Done. Thank you, goodbye!", [AgentAction("end_call", {"reason": "done"}, "t2")], False),
    ]
    llm, stt, tts = enable_voice(FakeLLM(script, intel()))
    admin = await login(client, "admin@test.local")
    agent = await create_agent(client, admin, greeting="Am I speaking with {first_name}?")
    lead = await make_lead("Meera Gupta", "+919000000401", org["ex1"].id, company_name="Apex")
    r = await client.post("/api/v1/ai/calls", headers=admin, json={"agent_id": agent["id"], "lead_id": str(lead.id)})
    assert r.status_code == 201, r.text
    call_id = r.json()["id"]

    ws = FakeWS()
    async with SessionLocal() as db:
        call = await db.get(AICall, __import__("uuid").UUID(call_id))
    from app.telephony.media import TwilioMediaAdapter

    adapter = TwilioMediaAdapter()
    adapter.stream_id = "MZ1"
    session = VoiceCallSession(ws=ws, adapter=adapter, ai_call_id=call.id, provider=provider, llm=llm, stt=stt,
                               tts=tts, silence_prompt_seconds=999, silence_hangup_seconds=999)
    task = asyncio.create_task(session.run())
    await asyncio.sleep(0.3)
    await stt.session.q.put(STTEvent("transcript", text="Yes, I'd like a meeting tomorrow", is_final=True,
                                     speech_final=True))
    await asyncio.wait_for(task, timeout=10)

    # the fixed AI disclosure is spoken first, before anything the LLM says
    assert tts.spoken[0].startswith("Hello, this is an AI assistant calling on behalf of Elets Technomedia.")
    assert "Am I speaking with Meera?" in tts.spoken[0]
    assert any(m["event"] == "media" for m in ws.sent)
    assert llm.conv.calls[1] == (None, {"t1": llm.conv.calls[1][1]["t1"]})  # tool result sent back
    assert session.end_reason == "done" and provider.hungup == ["FAKE-A1"]

    async with SessionLocal() as db:
        saved = await db.get(AICall, call.id)
        lead_row = await db.get(Lead, lead.id)
        fups = (await db.execute(sa.select(Followup).where(Followup.lead_id == lead.id))).scalars().all()
        notes = (await db.execute(sa.select(Notification).where(Notification.user_id == org["ex1"].id))
                 ).scalars().all()
    assert saved.status == "connected"  # media started; the terminal status comes from the provider webhook
    assert saved.intelligence["interest_level"] == "high" and saved.qualification_score == 85
    assert lead_row.status == "meeting_scheduled"  # AI analysis never downgrades a scheduled meeting
    assert any(f.source == "ai_call" for f in fups)
    assert {n.type for n in notes} >= {"ai_qualified_lead"}

    detail = (await client.get(f"/api/v1/ai/calls/{call_id}", headers=admin)).json()
    speakers = [s["speaker"] for s in detail["transcript"]]
    assert speakers[0] == "agent" and "customer" in speakers
    assert detail["intelligence"]["summary"].startswith("Interested")


async def test_voice_engine_handoff_transfers(client, org, provider):
    script = [("Sure, one moment.", [AgentAction("transfer_to_human", {"reason": "wants pricing"}, "t1")], True)]
    llm, stt, tts = enable_voice(FakeLLM(script, intel(interest_level="medium", qualification_score=55)))
    admin = await login(client, "admin@test.local")
    agent = await create_agent(client, admin)
    lead = await make_lead("Vikram Rao", "+919000000402", org["ex2"].id)
    call_id = (await client.post("/api/v1/ai/calls", headers=admin,
                                 json={"agent_id": agent["id"], "lead_id": str(lead.id)})).json()["id"]
    import uuid

    from app.telephony.media import TwilioMediaAdapter

    session = VoiceCallSession(ws=FakeWS(), adapter=TwilioMediaAdapter(), ai_call_id=uuid.UUID(call_id),
                               provider=provider, llm=llm, stt=stt, tts=tts, silence_prompt_seconds=999,
                               silence_hangup_seconds=999)
    task = asyncio.create_task(session.run())
    await asyncio.sleep(0.3)
    await stt.session.q.put(STTEvent("transcript", text="Can I talk to a person about pricing", is_final=True,
                                     speech_final=True))
    await asyncio.wait_for(task, timeout=10)
    assert provider.transfers == [("FAKE-A1", "+919811100002")]  # the lead owner's calling number
    assert provider.hungup == []  # transferred calls are not hung up
    detail = (await client.get(f"/api/v1/ai/calls/{call_id}", headers=admin)).json()
    assert detail["handoff_requested"] and detail["handoff"]["transferred"]
    assert detail["handoff"]["notified_user_name"] == "Exec Two"


async def test_executive_sees_only_ai_calls_for_own_leads(client, org, provider):
    enable_voice()
    admin = await login(client, "admin@test.local")
    agent = await create_agent(client, admin)
    mine = await make_lead("Mine", "+919000000501", org["ex1"].id)
    other = await make_lead("Other", "+919000000502", org["ex3"].id)
    for lead in (mine, other):
        await client.post("/api/v1/ai/calls", headers=admin, json={"agent_id": agent["id"], "lead_id": str(lead.id)})
    ex = await login(client, "ex1@test.local")
    items = (await client.get("/api/v1/ai/calls", headers=ex)).json()["items"]
    assert [i["lead_name"] for i in items] == ["Mine"]
    async with SessionLocal() as db:
        assert (await db.execute(sa.select(sa.func.count()).select_from(AIAgent))).scalar_one() == 1
