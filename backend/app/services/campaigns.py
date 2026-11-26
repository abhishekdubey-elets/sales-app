import uuid

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import as_utc, utcnow
from app.core.errors import AppError, not_found
from app.models import AIAgent, AICall, AICampaign, AICampaignLead, Followup, Lead, User
from app.models.enums import CampaignLeadStatus, CampaignStatus, LeadStatus
from app.realtime.hub import hub
from app.schemas.ai import CampaignCreate, CampaignUpdate, LeadFilter
from app.services.ai_calls import campaign_log
from app.services.org import managers_and_admins
from app.telephony.registry import get_provider
from app.voice.registry import voice_ready


async def campaign_stats(db: AsyncSession, campaign_id: uuid.UUID) -> dict:
    cl_counts = dict((await db.execute(
        sa.select(AICampaignLead.status, sa.func.count()).where(AICampaignLead.campaign_id == campaign_id)
        .group_by(AICampaignLead.status)
    )).all())
    attempted = (await db.execute(
        sa.select(sa.func.count()).where(AICampaignLead.campaign_id == campaign_id, AICampaignLead.attempts > 0)
    )).scalar_one()
    calls = (await db.execute(
        sa.select(
            sa.func.count(sa.case((AICall.answered_at.is_not(None), 1))),
            sa.func.count(sa.case((AICall.status.in_(["not_answered", "busy"]), 1))),
            sa.func.count(sa.case((AICall.status.in_(["failed", "rejected"]), 1))),
            sa.func.count(sa.case((AICall.handoff_requested.is_(True), 1))),
        ).where(AICall.campaign_id == campaign_id)
    )).one()
    interested = (await db.execute(
        sa.select(sa.func.count()).where(AICampaignLead.campaign_id == campaign_id,
                                         AICampaignLead.interest_level.in_(["high", "medium"]))
    )).scalar_one()
    qualified = (await db.execute(
        sa.select(sa.func.count(sa.distinct(AICall.lead_id))).where(
            AICall.campaign_id == campaign_id,
            sa.or_(AICall.qualification_score >= 60, AICall.interest_level == "high"))
    )).scalar_one()
    followups = (await db.execute(
        sa.select(sa.func.count()).select_from(Followup).join(AICall, Followup.ai_call_id == AICall.id)
        .where(AICall.campaign_id == campaign_id)
    )).scalar_one()
    conversions = (await db.execute(
        sa.select(sa.func.count()).select_from(AICampaignLead).join(Lead, Lead.id == AICampaignLead.lead_id)
        .where(AICampaignLead.campaign_id == campaign_id, Lead.status == LeadStatus.CONVERTED)
    )).scalar_one()
    return {
        "total_leads": sum(cl_counts.values()),
        "pending": cl_counts.get(CampaignLeadStatus.PENDING, 0),
        "in_progress": cl_counts.get(CampaignLeadStatus.IN_PROGRESS, 0),
        "attempted": attempted, "connected": calls[0], "not_answered": calls[1], "failed": calls[2],
        "interested": interested, "qualified": qualified, "followups": followups, "conversions": conversions,
        "handoffs": calls[3], "opted_out": cl_counts.get(CampaignLeadStatus.OPTED_OUT, 0),
    }


async def campaign_out(db: AsyncSession, c: AICampaign) -> dict:
    return {
        "id": c.id, "name": c.name, "description": c.description, "agent_id": c.agent_id,
        "agent_name": c.agent.name if c.agent else "", "status": c.status, "schedule": c.schedule,
        "max_attempts": c.max_attempts, "retry_delay_minutes": c.retry_delay_minutes,
        "max_concurrent_calls": c.max_concurrent_calls, "calls_per_minute": c.calls_per_minute,
        "created_at": as_utc(c.created_at), "started_at": as_utc(c.started_at),
        "completed_at": as_utc(c.completed_at), "stats": await campaign_stats(db, c.id),
    }


async def publish_progress(db: AsyncSession, c: AICampaign) -> None:
    await hub.publish(await managers_and_admins(db), "campaign.progress",
                      {"campaign_id": c.id, "status": c.status, "stats": await campaign_stats(db, c.id)})


async def get_campaign(db: AsyncSession, campaign_id: uuid.UUID) -> AICampaign:
    c = await db.get(AICampaign, campaign_id)
    if c is None:
        raise not_found("Campaign")
    return c


async def _active_agent(db: AsyncSession, agent_id: uuid.UUID) -> AIAgent:
    agent = await db.get(AIAgent, agent_id)
    if agent is None or not agent.is_active:
        raise AppError(422, "validation_error", "Select an active AI agent")
    return agent


async def create_campaign(db: AsyncSession, actor: User, data: CampaignCreate) -> AICampaign:
    await _active_agent(db, data.agent_id)
    c = AICampaign(
        name=data.name, description=data.description, agent_id=data.agent_id,
        schedule=data.schedule.model_dump(mode="json"), max_attempts=data.max_attempts,
        retry_delay_minutes=data.retry_delay_minutes, max_concurrent_calls=data.max_concurrent_calls,
        calls_per_minute=data.calls_per_minute, created_by_id=actor.id, status=CampaignStatus.DRAFT,
    )
    db.add(c)
    await db.flush()
    await campaign_log(db, c.id, "created", f"Campaign created by {actor.full_name}")
    await db.refresh(c, ["agent"])
    return c


async def update_campaign(db: AsyncSession, c: AICampaign, data: CampaignUpdate) -> AICampaign:
    if c.status not in (CampaignStatus.DRAFT, CampaignStatus.PAUSED):
        raise AppError(409, "invalid_state", "Only draft or paused campaigns can be edited")
    fields = data.model_dump(exclude_unset=True)
    if "agent_id" in fields:
        await _active_agent(db, fields["agent_id"])
    if "schedule" in fields and data.schedule is not None:
        fields["schedule"] = data.schedule.model_dump(mode="json")
    for k, v in fields.items():
        setattr(c, k, v)
    await db.flush()
    await db.refresh(c, ["agent"])
    return c


async def add_leads(db: AsyncSession, c: AICampaign, lead_ids: list[uuid.UUID] | None,
                    flt: LeadFilter | None) -> dict:
    if c.status in (CampaignStatus.COMPLETED, CampaignStatus.STOPPED):
        raise AppError(409, "invalid_state", "Leads cannot be added to a finished campaign")
    stmt = sa.select(Lead.id, Lead.opted_out).where(Lead.deleted_at.is_(None))
    if lead_ids:
        stmt = stmt.where(Lead.id.in_(lead_ids))
    if flt:
        if flt.status:
            stmt = stmt.where(Lead.status.in_(flt.status.split(",")))
        if flt.source:
            stmt = stmt.where(Lead.source == flt.source)
        if flt.industry:
            stmt = stmt.where(Lead.industry == flt.industry)
        if flt.assigned_to:
            stmt = stmt.where(Lead.assigned_to_id == flt.assigned_to)
    candidates = (await db.execute(stmt)).all()
    existing = set((await db.execute(
        sa.select(AICampaignLead.lead_id).where(AICampaignLead.campaign_id == c.id)
    )).scalars())
    added = skipped = 0
    for lead_id, opted_out in candidates:
        if lead_id in existing or opted_out:
            skipped += 1
            continue
        db.add(AICampaignLead(campaign_id=c.id, lead_id=lead_id, status=CampaignLeadStatus.PENDING))
        existing.add(lead_id)
        added += 1
    if lead_ids:
        skipped += len(set(lead_ids)) - len(candidates)
    if added:
        await campaign_log(db, c.id, "leads_added", f"{added} lead(s) added ({skipped} skipped)")
    await db.flush()
    return {"added": added, "skipped": skipped}


async def transition(db: AsyncSession, actor: User, c: AICampaign, action: str) -> AICampaign:
    allowed = {
        "start": {CampaignStatus.DRAFT},
        "pause": {CampaignStatus.RUNNING},
        "resume": {CampaignStatus.PAUSED},
        "stop": {CampaignStatus.DRAFT, CampaignStatus.RUNNING, CampaignStatus.PAUSED},
    }
    if c.status not in allowed[action]:
        raise AppError(409, "invalid_state", f"Cannot {action} a {c.status} campaign")
    if action in ("start", "resume"):
        provider = get_provider()
        if provider is None or not provider.is_configured():
            raise AppError(503, "telephony_not_configured", "No telephony provider is configured")
        if not provider.supports_ai_streaming:
            raise AppError(503, "telephony_not_supported", f"{provider.name} does not support AI voice calls")
        ok, why = voice_ready()
        if not ok:
            raise AppError(503, "voice_not_configured", f"AI voice is not ready: {why}")
        await _active_agent(db, c.agent_id)
        pending = (await db.execute(sa.select(sa.func.count()).where(
            AICampaignLead.campaign_id == c.id, AICampaignLead.status == CampaignLeadStatus.PENDING))).scalar_one()
        if pending == 0:
            raise AppError(409, "no_leads", "Add leads before starting the campaign")
        c.status = CampaignStatus.RUNNING
        if action == "start":
            c.started_at = utcnow()
    elif action == "pause":
        c.status = CampaignStatus.PAUSED
    else:
        c.status = CampaignStatus.STOPPED
        c.completed_at = utcnow()
        await db.execute(
            sa.update(AICampaignLead)
            .where(AICampaignLead.campaign_id == c.id, AICampaignLead.status == CampaignLeadStatus.PENDING)
            .values(status=CampaignLeadStatus.SKIPPED)
        )
    past = {"start": "started", "pause": "paused", "resume": "resumed", "stop": "stopped"}[action]
    await campaign_log(db, c.id, action, f"Campaign {past} by {actor.full_name}")
    await db.flush()
    return c


async def campaign_leads_out(db: AsyncSession, rows: list[AICampaignLead]) -> list[dict]:
    if not rows:
        return []
    leads = {lead.id: lead for lead in (await db.execute(
        sa.select(Lead).where(Lead.id.in_([r.lead_id for r in rows])))).scalars().unique()}
    out = []
    for r in rows:
        lead = leads.get(r.lead_id)
        out.append({
            "id": r.id, "lead_id": r.lead_id, "lead_name": lead.full_name if lead else None,
            "company_name": lead.company_name if lead else None, "status": r.status, "attempts": r.attempts,
            "next_attempt_at": as_utc(r.next_attempt_at), "last_call_status": r.last_call_status,
            "outcome": r.outcome, "interest_level": r.interest_level, "last_ai_call_id": r.last_ai_call_id,
        })
    return out
