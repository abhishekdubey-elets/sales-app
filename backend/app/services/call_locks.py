"""One live call per lead across human and AI calling."""

import uuid
from datetime import timedelta

import sqlalchemy as sa
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import as_utc, utcnow
from app.core.errors import AppError
from app.models import LeadCallLock


def _busy() -> AppError:
    return AppError(409, "lead_busy", "This lead is already on a call")


async def acquire_lock(db: AsyncSession, lead_id: uuid.UUID, holder_type: str, holder_id: uuid.UUID) -> None:
    now = utcnow()
    existing = (
        await db.execute(sa.select(LeadCallLock).where(LeadCallLock.lead_id == lead_id))
    ).scalar_one_or_none()
    if existing is not None:
        if as_utc(existing.expires_at) > now:
            raise _busy()
        await db.delete(existing)
        await db.flush()
    try:
        async with db.begin_nested():
            db.add(
                LeadCallLock(
                    lead_id=lead_id, holder_type=holder_type, holder_id=holder_id, acquired_at=now,
                    expires_at=now + timedelta(minutes=settings.CALL_LOCK_TTL_MINUTES),
                )
            )
    except IntegrityError as exc:
        raise _busy() from exc


async def release_lock(db: AsyncSession, lead_id: uuid.UUID | None, holder_id: uuid.UUID) -> None:
    if lead_id is None:
        return
    await db.execute(
        sa.delete(LeadCallLock).where(LeadCallLock.lead_id == lead_id, LeadCallLock.holder_id == holder_id)
    )


async def is_locked(db: AsyncSession, lead_id: uuid.UUID) -> bool:
    row = (
        await db.execute(sa.select(LeadCallLock.expires_at).where(LeadCallLock.lead_id == lead_id))
    ).scalar_one_or_none()
    return row is not None and as_utc(row) > utcnow()
