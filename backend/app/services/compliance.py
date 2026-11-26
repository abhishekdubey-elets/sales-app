"""Pre-call compliance gates shared by human and AI calling.

Covers: do-not-call / opt-out list, permitted calling hours, AI-call consent and calling credits.
External DND registry scrubbing (e.g. NCPR via your telephony provider) plugs in through `DndChecker`.
"""

import math
import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import utcnow
from app.core.errors import AppError
from app.core.timeranges import within_daily_window
from app.models import Lead, OptOut, OrgSettings
from app.models.enums import ConsentStatus


class DndChecker:
    """Override `is_registered` to consult an external DND registry. Default: none configured."""

    async def is_registered(self, phone_e164: str) -> bool:  # pragma: no cover - extension point
        return False


dnd_checker = DndChecker()


async def is_opted_out(db: AsyncSession, phone_hash: str) -> bool:
    row = await db.execute(sa.select(OptOut.id).where(OptOut.phone_hash == phone_hash).limit(1))
    return row.scalar_one_or_none() is not None


def check_calling_hours(org: OrgSettings, now: datetime | None = None) -> None:
    if not within_daily_window(
        now or utcnow(), org.timezone, org.calling_hours_start, org.calling_hours_end, org.calling_days
    ):
        raise AppError(
            403, "outside_calling_hours",
            f"Calls are only permitted {org.calling_hours_start}–{org.calling_hours_end} ({org.timezone}) "
            "on configured calling days",
        )


async def ensure_callable(
    db: AsyncSession,
    org: OrgSettings,
    *,
    phone_e164: str,
    phone_hash: str,
    lead: Lead | None,
    kind: str,
    now: datetime | None = None,
) -> None:
    if (lead is not None and lead.opted_out) or await is_opted_out(db, phone_hash):
        raise AppError(403, "opted_out", "This number has opted out of calls")
    if await dnd_checker.is_registered(phone_e164):
        raise AppError(403, "opted_out", "This number is on the DND registry")
    check_calling_hours(org, now)
    if kind == "ai":
        if org.require_consent_for_ai_calls and (lead is None or lead.consent_status != ConsentStatus.GRANTED):
            raise AppError(403, "consent_required", "AI calls require recorded consent for this lead")
        if org.calling_credits_minutes is not None and org.credits_used_minutes >= org.calling_credits_minutes:
            raise AppError(402, "credits_exhausted", "Calling credits are exhausted")


async def record_opt_out(
    db: AsyncSession,
    *,
    phone_hash: str,
    reason: str | None,
    source: str,
    lead_id: uuid.UUID | None = None,
    user_id: uuid.UUID | None = None,
) -> None:
    if not await is_opted_out(db, phone_hash):
        db.add(OptOut(phone_hash=phone_hash, reason=reason, source=source, lead_id=lead_id, created_by_id=user_id))
    await db.execute(
        sa.update(Lead).where(sa.or_(Lead.phone_hash == phone_hash, Lead.alternate_phone_hash == phone_hash))
        .values(opted_out=True)
    )


def consume_credits(org: OrgSettings, duration_seconds: int) -> None:
    if duration_seconds > 0:
        org.credits_used_minutes = (org.credits_used_minutes or 0) + math.ceil(duration_seconds / 60)
