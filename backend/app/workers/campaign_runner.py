"""Dials due campaign leads within each campaign's schedule, concurrency and rate limits."""

import logging
from datetime import date, datetime, timedelta

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import SessionLocal, utcnow
from app.core.errors import AppError
from app.core.timeranges import local_date, within_daily_window
from app.models import AIAgent, AICall, AICampaign, AICampaignLead, Lead
from app.models.enums import ACTIVE_CALL_STATUSES, CampaignLeadStatus, CampaignStatus, NotificationType
from app.services import call_locks
from app.services.ai_calls import campaign_log, start_ai_call
from app.services.campaigns import publish_progress
from app.services.compliance import check_calling_hours
from app.services.notifications import commit_and_deliver, notify
from app.services.org import admin_ids, get_org_settings

log = logging.getLogger(__name__)

_PAUSE_CODES = {"telephony_not_configured", "telephony_not_supported", "voice_not_configured", "credits_exhausted",
                "agent_inactive"}


def _in_schedule(c: AICampaign, now: datetime) -> bool:
    s = c.schedule or {}
    tz = s.get("timezone", "Asia/Kolkata")
    today = local_date(now, tz)
    if s.get("start_date") and today < date.fromisoformat(s["start_date"]):
        return False
    return within_daily_window(now, tz, s.get("start_time", "10:00"), s.get("end_time", "18:00"),
                               s.get("days_of_week", [1, 2, 3, 4, 5]))


def _past_end(c: AICampaign, now: datetime) -> bool:
    end = (c.schedule or {}).get("end_date")
    return bool(end) and local_date(now, (c.schedule or {}).get("timezone", "Asia/Kolkata")) > date.fromisoformat(end)


async def _complete(db: AsyncSession, c: AICampaign, reason: str) -> None:
    c.status = CampaignStatus.COMPLETED
    c.completed_at = utcnow()
    await db.execute(sa.update(AICampaignLead).where(
        AICampaignLead.campaign_id == c.id, AICampaignLead.status == CampaignLeadStatus.PENDING
    ).values(status=CampaignLeadStatus.SKIPPED))
    await campaign_log(db, c.id, "completed", reason)
    recipients = set(await admin_ids(db))
    if c.created_by_id:
        recipients.add(c.created_by_id)
    await notify(db, recipients, NotificationType.CAMPAIGN_COMPLETED, f"Campaign completed: {c.name}", reason,
                 {"campaign_id": str(c.id)})


async def tick(now: datetime | None = None) -> None:
    now = now or utcnow()
    async with SessionLocal() as db:
        campaigns = (await db.execute(
            sa.select(AICampaign).where(AICampaign.status == CampaignStatus.RUNNING)
        )).scalars().unique().all()
        if not campaigns:
            return
        org = await get_org_settings(db)
        for c in campaigns:
            try:
                await _run_campaign(db, c, org, now)
            except Exception:  # noqa: BLE001
                log.exception("campaign %s tick failed", c.id)
                await db.rollback()
            await commit_and_deliver(db)
            await publish_progress(db, c)


async def _run_campaign(db: AsyncSession, c: AICampaign, org, now: datetime) -> None:
    if _past_end(c, now):
        await _complete(db, c, "Campaign end date reached")
        return
    remaining = (await db.execute(sa.select(sa.func.count()).where(
        AICampaignLead.campaign_id == c.id,
        AICampaignLead.status.in_([CampaignLeadStatus.PENDING, CampaignLeadStatus.IN_PROGRESS]),
    ))).scalar_one()
    if remaining == 0:
        await _complete(db, c, "All leads have been processed")
        return
    if not _in_schedule(c, now):
        return
    try:
        check_calling_hours(org, now)
    except AppError:
        return

    active = (await db.execute(sa.select(sa.func.count()).where(
        AICall.campaign_id == c.id, AICall.status.in_([s.value for s in ACTIVE_CALL_STATUSES])))).scalar_one()
    recent = (await db.execute(sa.select(sa.func.count()).where(
        AICall.campaign_id == c.id, AICall.created_at >= now - timedelta(seconds=60)))).scalar_one()
    slots = min(c.max_concurrent_calls - active, c.calls_per_minute - recent)
    if slots <= 0:
        return

    due = (await db.execute(
        sa.select(AICampaignLead).where(
            AICampaignLead.campaign_id == c.id, AICampaignLead.status == CampaignLeadStatus.PENDING,
            sa.or_(AICampaignLead.next_attempt_at.is_(None), AICampaignLead.next_attempt_at <= now),
        ).order_by(AICampaignLead.next_attempt_at.asc().nulls_first(), AICampaignLead.created_at).limit(slots * 3)
    )).scalars().all()
    agent = await db.get(AIAgent, c.agent_id)
    launched = 0
    for cl in due:
        if launched >= slots:
            break
        lead = await db.get(Lead, cl.lead_id)
        if lead is None or lead.deleted_at is not None:
            cl.status = CampaignLeadStatus.SKIPPED
            await campaign_log(db, c.id, "lead_skipped", "Lead was deleted", "warning", cl.lead_id)
            continue
        if await call_locks.is_locked(db, lead.id):
            continue  # on another call right now — try on a later tick
        try:
            await start_ai_call(db, agent, lead, campaign=c, campaign_lead=cl)
            launched += 1
        except AppError as exc:
            if exc.code == "opted_out":
                cl.status = CampaignLeadStatus.OPTED_OUT
                await campaign_log(db, c.id, "lead_opted_out", f"{lead.full_name}: {exc.detail}", "warning", lead.id)
            elif exc.code == "consent_required":
                cl.status = CampaignLeadStatus.SKIPPED
                await campaign_log(db, c.id, "lead_skipped", f"{lead.full_name}: {exc.detail}", "warning", lead.id)
            elif exc.code in _PAUSE_CODES:
                c.status = CampaignStatus.PAUSED
                await campaign_log(db, c.id, "auto_paused", f"Paused: {exc.detail}", "error")
                await notify(db, await admin_ids(db), NotificationType.SYSTEM, f"Campaign paused: {c.name}",
                             exc.detail, {"campaign_id": str(c.id)})
                break
            elif exc.code == "outside_calling_hours":
                break
            elif exc.code == "telephony_error":
                launched += 1  # attempt consumed; bookkeeping already done
            elif exc.code == "lead_busy":
                continue
            else:
                await campaign_log(db, c.id, "call_error", f"{lead.full_name}: {exc.detail}", "error", lead.id)
        await db.commit()


async def sweep_stale_calls(db: AsyncSession, max_age_minutes: int) -> int:
    """Calls with no terminal webhook after `max_age_minutes` are marked failed (never assumed successful)."""
    from app.models import HumanCall
    from app.services.ai_calls import _on_terminal as ai_terminal
    from app.services.calls import _on_terminal as human_terminal

    cutoff = utcnow() - timedelta(minutes=max_age_minutes)
    n = 0
    for model, on_terminal in ((HumanCall, human_terminal), (AICall, ai_terminal)):
        stale = (await db.execute(sa.select(model).where(
            model.status.in_([s.value for s in ACTIVE_CALL_STATUSES]), model.started_at < cutoff
        ))).scalars().unique().all()
        for call in stale:
            call.status = "failed"
            call.failure_reason = "No final status received from the telephony provider"
            call.ended_at = utcnow()
            await on_terminal(db, call)
            n += 1
    return n

