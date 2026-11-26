"""Periodic jobs: follow-up reminders, stale-call sweep, daily summaries, low-credit alerts."""

import asyncio
import logging
from datetime import timedelta
from zoneinfo import ZoneInfo

import sqlalchemy as sa

from app.core.config import settings
from app.core.database import SessionLocal, utcnow
from app.core.timeranges import local_date, resolve_range
from app.models import Followup, Lead, RoleModel, User
from app.models.enums import FollowupStatus, NotificationType
from app.services import analytics
from app.services.notifications import commit_and_deliver, notify
from app.services.org import admin_ids, get_org_settings
from app.workers import campaign_runner

log = logging.getLogger(__name__)


async def followup_reminders() -> None:
    async with SessionLocal() as db:
        soon = utcnow() + timedelta(minutes=15)
        rows = (await db.execute(sa.select(Followup).where(
            Followup.status == FollowupStatus.PENDING, Followup.reminded_at.is_(None), Followup.due_at <= soon,
            Followup.assigned_to_id.is_not(None),
        ).limit(500))).scalars().all()
        for f in rows:
            lead = await db.get(Lead, f.lead_id)
            await notify(db, [f.assigned_to_id], NotificationType.FOLLOWUP_REMINDER, "Follow-up due",
                         f"{lead.full_name if lead else 'Lead'}{': ' + f.note if f.note else ''}"[:240],
                         {"lead_id": str(f.lead_id), "followup_id": str(f.id)})
            f.reminded_at = utcnow()
        await commit_and_deliver(db)


async def daily_jobs() -> None:
    async with SessionLocal() as db:
        org = await get_org_settings(db)
        now = utcnow()
        today = local_date(now, org.timezone)
        local_hhmm = now.astimezone(ZoneInfo(org.timezone)).strftime("%H:%M")
        if org.last_daily_summary_date == today or local_hhmm < org.daily_summary_time:
            return
        start, end = resolve_range("today", None, None, org.timezone, now)
        users = (await db.execute(sa.select(User).join(RoleModel, User.role_id == RoleModel.id)
                                  .where(User.is_active.is_(True)))).scalars().unique().all()
        for u in users:
            stats = await analytics.dashboard(db, u, start, end)
            mins = stats["total_duration_seconds"] // 60
            body = (f"{stats['total_calls']} calls · {stats['connected_calls']} connected · {mins} min talk time · "
                    f"{stats['pending_followups']} follow-ups pending")
            if u.role_name != "executive":
                body += f" · {stats['ai_calls']} AI calls"
            await notify(db, [u.id], NotificationType.DAILY_SUMMARY, "Today's performance", body,
                         {"date": today.isoformat()})
        if org.calling_credits_minutes is not None:
            remaining = org.calling_credits_minutes - org.credits_used_minutes
            if remaining <= org.low_credit_threshold_minutes:
                await notify(db, await admin_ids(db), NotificationType.SYSTEM, "Calling credits running low",
                             f"{max(remaining, 0)} minutes remaining", {})
        org.last_daily_summary_date = today
        await commit_and_deliver(db)


async def stale_sweep() -> None:
    async with SessionLocal() as db:
        n = await campaign_runner.sweep_stale_calls(db, settings.CALL_LOCK_TTL_MINUTES)
        if n:
            log.warning("marked %d stale calls as failed", n)
        await commit_and_deliver(db)


async def run_forever(stop: asyncio.Event) -> None:
    """Main worker loop (started by the API when RUN_WORKERS=true, or by `python -m app.workers`)."""
    tick = 0
    while not stop.is_set():
        for job in (campaign_runner.tick, followup_reminders) + ((stale_sweep, daily_jobs) if tick % 6 == 0 else ()):
            try:
                await job()
            except Exception:  # noqa: BLE001
                log.exception("worker job %s failed", job.__name__)
        tick += 1
        try:
            await asyncio.wait_for(stop.wait(), timeout=settings.WORKER_TICK_SECONDS)
        except TimeoutError:
            pass
