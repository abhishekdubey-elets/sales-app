import uuid
from datetime import date

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import as_utc, get_db
from app.core.deps import require
from app.core.errors import AppError, not_found
from app.core.permissions import P
from app.core.timeranges import resolve_range
from app.models import AIAgent, AICall, AIHandoff, CallRecording, CallTranscript, User
from app.models.enums import ACTIVE_CALL_STATUSES, CallStatus, FollowupSource
from app.schemas.ai import (
    AIAgentCreate,
    AIAgentOut,
    AIAgentUpdate,
    AICallDetail,
    AICallOut,
    AIDashboard,
    StartAICallIn,
    TestReplyIn,
    TestReplyOut,
)
from app.schemas.common import Page
from app.services import ai_calls as svc
from app.services.audit import audit
from app.services.org import get_org_settings
from app.services.scoping import get_visible_ai_call, get_visible_lead, scope_ai_calls
from app.services.serializers import ai_call_out
from app.telephony.base import TelephonyError, TelephonyNotSupported
from app.telephony.registry import get_provider, telephony_status
from app.voice.llm.base import LLMError
from app.voice.prompts import AGENT_TEMPLATES, CALL_TOOLS, live_system_prompt, opening_line
from app.voice.registry import get_llm, voice_status

router = APIRouter(prefix="/ai", tags=["ai"])


async def _agent_out(db: AsyncSession, a: AIAgent) -> dict:
    total, success = (await db.execute(sa.select(
        sa.func.count(), sa.func.count(sa.case((sa.and_(AICall.answered_at.is_not(None), sa.or_(
            AICall.interest_level.in_(["high", "medium"]), AICall.qualification_score >= 60)), 1)))
    ).where(AICall.agent_id == a.id))).one()
    creator = (await db.execute(sa.select(User.full_name).where(User.id == a.created_by_id))).scalar() \
        if a.created_by_id else None
    return {
        "id": a.id, "name": a.name, "description": a.description, "personality": a.personality,
        "language": a.language, "voice_id": a.voice_id, "speaking_speed": a.speaking_speed,
        "system_prompt": a.system_prompt, "knowledge_base": a.knowledge_base, "objectives": a.objectives or [],
        "greeting": a.greeting, "max_call_duration_seconds": a.max_call_duration_seconds,
        "retry_rules": a.retry_rules or {}, "handoff_conditions": a.handoff_conditions or [],
        "recording_enabled": a.recording_enabled, "is_active": a.is_active, "created_by_name": creator,
        "created_at": as_utc(a.created_at), "updated_at": as_utc(a.updated_at), "total_calls": total,
        "successful_conversations": success,
    }


@router.get("/voice-status")
async def get_voice_status(user: User = Depends(require(P.AI_AGENTS_VIEW))):
    return {**voice_status(), "telephony": telephony_status()}


@router.get("/agents", response_model=list[AIAgentOut])
async def list_agents(include_archived: bool = False, user: User = Depends(require(P.AI_AGENTS_VIEW)),
                      db: AsyncSession = Depends(get_db)):
    stmt = sa.select(AIAgent).order_by(AIAgent.created_at)
    if not include_archived:
        stmt = stmt.where(AIAgent.is_active.is_(True))
    return [await _agent_out(db, a) for a in (await db.execute(stmt)).scalars()]


@router.get("/agents/templates", response_model=list[AIAgentCreate])
async def templates(user: User = Depends(require(P.AI_AGENTS_VIEW))):
    return AGENT_TEMPLATES


@router.post("/agents", response_model=AIAgentOut, status_code=201)
async def create_agent(body: AIAgentCreate, request: Request, user: User = Depends(require(P.AI_AGENTS_MANAGE)),
                       db: AsyncSession = Depends(get_db)):
    data = body.model_dump(mode="json")
    a = AIAgent(**data, created_by_id=user.id)
    db.add(a)
    await db.flush()
    await audit(db, user, "ai_agent.created", "ai_agent", a.id, {"name": a.name}, request)
    await db.commit()
    return await _agent_out(db, a)


async def _get_agent(db: AsyncSession, agent_id: uuid.UUID) -> AIAgent:
    a = await db.get(AIAgent, agent_id)
    if a is None:
        raise not_found("AI agent")
    return a


@router.get("/agents/{agent_id}", response_model=AIAgentOut)
async def get_agent(agent_id: uuid.UUID, user: User = Depends(require(P.AI_AGENTS_VIEW)),
                    db: AsyncSession = Depends(get_db)):
    return await _agent_out(db, await _get_agent(db, agent_id))


@router.patch("/agents/{agent_id}", response_model=AIAgentOut)
async def update_agent(agent_id: uuid.UUID, body: AIAgentUpdate, request: Request,
                       user: User = Depends(require(P.AI_AGENTS_MANAGE)), db: AsyncSession = Depends(get_db)):
    a = await _get_agent(db, agent_id)
    data = body.model_dump(exclude_unset=True, mode="json")
    for k, v in data.items():
        setattr(a, k, v)
    await audit(db, user, "ai_agent.updated", "ai_agent", a.id, {"fields": sorted(data)}, request)
    await db.commit()
    return await _agent_out(db, a)


@router.delete("/agents/{agent_id}", response_model=AIAgentOut)
async def archive_agent(agent_id: uuid.UUID, request: Request, user: User = Depends(require(P.AI_AGENTS_MANAGE)),
                        db: AsyncSession = Depends(get_db)):
    a = await _get_agent(db, agent_id)
    a.is_active = False
    await audit(db, user, "ai_agent.archived", "ai_agent", a.id, {"name": a.name}, request)
    await db.commit()
    return await _agent_out(db, a)


@router.post("/agents/{agent_id}/test-reply", response_model=TestReplyOut)
async def test_reply(agent_id: uuid.UUID, body: TestReplyIn, user: User = Depends(require(P.AI_AGENTS_MANAGE)),
                     db: AsyncSession = Depends(get_db)):
    """Text-only rehearsal of the agent prompt (no call is placed)."""
    a = await _get_agent(db, agent_id)
    llm = get_llm()
    if llm is None or not llm.is_configured():
        raise AppError(503, "llm_not_configured", "No LLM provider is configured (set ANTHROPIC_API_KEY)")
    org = await get_org_settings(db)
    opening = opening_line(a, None, org.ai_disclosure_text,
                           org.recording_disclosure_text if org.recording_enabled and a.recording_enabled else None)
    history = [(t.role, t.text) for t in body.history]
    while history and history[0][0] != "user":
        history.pop(0)
    conv = llm.start_conversation(live_system_prompt(a, None, opening), CALL_TOOLS, history)
    try:
        result = await conv.respond(body.message)
    except LLMError as exc:
        raise AppError(502, "llm_error", str(exc)) from exc
    return {"reply": result.text or ("(declined)" if result.refused else ""),
            "actions": [{"name": x.name, "args": x.args} for x in result.actions]}


# ── AI calls ───────────────────────────────────────────────────────────────
@router.get("/dashboard", response_model=AIDashboard)
async def dashboard(range: str | None = "today", date_from: date | None = Query(None, alias="from"),
                    date_to: date | None = Query(None, alias="to"), agent_id: uuid.UUID | None = None,
                    campaign_id: uuid.UUID | None = None, user: User = Depends(require(P.AI_CALLS_VIEW)),
                    db: AsyncSession = Depends(get_db)):
    org = await get_org_settings(db)
    start, end = resolve_range(range, date_from, date_to, org.timezone)
    base = [AICall.started_at >= start, AICall.started_at < end]
    if agent_id:
        base.append(AICall.agent_id == agent_id)
    if campaign_id:
        base.append(AICall.campaign_id == campaign_id)

    def c(cond):
        return sa.func.count(sa.case((cond, 1)))

    from app.models import Followup  # local to keep the import list short

    row = (await db.execute(scope_ai_calls(sa.select(
        sa.func.count(),
        c(AICall.status.in_([s.value for s in ACTIVE_CALL_STATUSES])),
        c(AICall.status == CallStatus.COMPLETED),
        c(sa.and_(AICall.answered_at.is_not(None), sa.or_(AICall.interest_level.in_(["high", "medium"]),
                                                          AICall.qualification_score >= 60))),
        c(sa.or_(AICall.qualification_score >= 60, AICall.interest_level == "high")),
        c(AICall.interest_level.in_(["high", "medium"])),
        sa.func.avg(sa.case((AICall.answered_at.is_not(None), AICall.duration_seconds))),
        c(AICall.handoff_requested.is_(True)),
    ).where(*base), user))).one()
    followups = (await db.execute(sa.select(sa.func.count()).select_from(Followup).join(
        AICall, Followup.ai_call_id == AICall.id).where(Followup.source == FollowupSource.AI_CALL, *base))).scalar_one()
    return {"total_calls": row[0], "in_progress": row[1], "completed": row[2], "successful_conversations": row[3],
            "qualified": row[4], "interested": row[5], "followups_required": followups,
            "avg_duration_seconds": round(float(row[6] or 0), 1), "handoffs": row[7]}


@router.get("/calls", response_model=Page[AICallOut])
async def list_ai_calls(
    agent_id: uuid.UUID | None = None, campaign_id: uuid.UUID | None = None, lead_id: uuid.UUID | None = None,
    status: str | None = None, interest_level: str | None = None, handoff: bool | None = None,
    range: str | None = None, date_from: date | None = Query(None, alias="from"),
    date_to: date | None = Query(None, alias="to"), page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100), user: User = Depends(require(P.AI_CALLS_VIEW)),
    db: AsyncSession = Depends(get_db),
):
    stmt = scope_ai_calls(sa.select(AICall), user)
    for col, val in ((AICall.agent_id, agent_id), (AICall.campaign_id, campaign_id), (AICall.lead_id, lead_id)):
        if val:
            stmt = stmt.where(col == val)
    if status:
        stmt = stmt.where(AICall.status.in_(status.split(",")))
    if interest_level:
        stmt = stmt.where(AICall.interest_level.in_(interest_level.split(",")))
    if handoff is not None:
        stmt = stmt.where(AICall.handoff_requested.is_(handoff))
    if range:
        org = await get_org_settings(db)
        start, end = resolve_range(range, date_from, date_to, org.timezone)
        stmt = stmt.where(AICall.started_at >= start, AICall.started_at < end)
    total = (await db.execute(sa.select(sa.func.count()).select_from(stmt.subquery()))).scalar_one()
    rows = (await db.execute(stmt.order_by(AICall.started_at.desc()).offset((page - 1) * page_size)
                             .limit(page_size))).scalars().unique().all()
    return {"items": [ai_call_out(c) for c in rows], "total": total, "page": page, "page_size": page_size}


@router.get("/calls/{call_id}", response_model=AICallDetail)
async def get_ai_call(call_id: uuid.UUID, user: User = Depends(require(P.AI_CALLS_VIEW)),
                      db: AsyncSession = Depends(get_db)):
    call = await get_visible_ai_call(db, user, call_id)
    transcript = (await db.execute(sa.select(CallTranscript).where(CallTranscript.ai_call_id == call.id))).scalar()
    rec_id = (await db.execute(sa.select(CallRecording.id).where(CallRecording.ai_call_id == call.id))).scalar()
    handoff = (await db.execute(sa.select(AIHandoff).where(AIHandoff.ai_call_id == call.id)
                                .order_by(AIHandoff.created_at.desc()).limit(1))).scalar()
    handoff_out = None
    if handoff:
        name = (await db.execute(sa.select(User.full_name).where(User.id == handoff.notified_user_id))).scalar() \
            if handoff.notified_user_id else None
        handoff_out = {"reason": handoff.reason, "notified_user_id": handoff.notified_user_id,
                       "notified_user_name": name, "transferred": handoff.transferred, "at": as_utc(handoff.created_at)}
    is_supervisor = user.role_name in ("admin", "manager")
    return {**ai_call_out(call), "intelligence": call.intelligence,
            "transcript": transcript.segments if transcript else [],
            "recording_id": rec_id if is_supervisor else None, "handoff": handoff_out}


@router.post("/calls", response_model=AICallOut, status_code=201)
async def test_call(body: StartAICallIn, request: Request, user: User = Depends(require(P.AI_CALLS_MAKE)),
                    db: AsyncSession = Depends(get_db)):
    agent = await _get_agent(db, body.agent_id)
    lead = await get_visible_lead(db, user, body.lead_id)
    call = await svc.start_ai_call(db, agent, lead, initiated_by=user)
    await audit(db, user, "ai_call.started", "ai_call", call.id, {"agent": agent.name, "lead_id": str(lead.id)},
                request)
    await db.commit()
    await db.refresh(call, ["agent", "campaign"])
    return ai_call_out(call)


@router.post("/calls/{call_id}/hangup", response_model=AICallOut)
async def hangup_ai_call(call_id: uuid.UUID, user: User = Depends(require(P.AI_CALLS_MAKE)),
                         db: AsyncSession = Depends(get_db)):
    call = await get_visible_ai_call(db, user, call_id)
    if call.status in ACTIVE_CALL_STATUSES and call.provider_call_id:
        provider = get_provider(call.provider)
        try:
            if provider is None:
                raise TelephonyError("Provider not configured")
            await provider.hangup(call.provider_call_id)
        except TelephonyNotSupported as exc:
            raise AppError(501, "not_supported", str(exc)) from exc
        except TelephonyError as exc:
            raise AppError(502, "telephony_error", str(exc)) from exc
    return ai_call_out(call)
