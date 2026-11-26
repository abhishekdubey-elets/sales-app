import uuid
from zoneinfo import ZoneInfo

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Query, Request, Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import as_utc, get_db, utcnow
from app.core.deps import get_current_user, require
from app.core.errors import AppError, not_found
from app.core.permissions import P
from app.models import AuditLog, Notification, User
from app.schemas.common import Count, Page
from app.schemas.misc import AuditLogOut, NotificationOut, OrgSettingsOut, OrgSettingsUpdate, TelephonyStatus
from app.services.audit import audit
from app.services.notifications import notification_out
from app.services.org import get_org_settings
from app.telephony.registry import telephony_status

router = APIRouter(tags=["notifications", "settings"])


@router.get("/notifications", response_model=Page[NotificationOut])
async def list_notifications(unread_only: bool = False, page: int = Query(1, ge=1),
                             page_size: int = Query(30, ge=1, le=100), user: User = Depends(get_current_user),
                             db: AsyncSession = Depends(get_db)):
    stmt = sa.select(Notification).where(Notification.user_id == user.id)
    if unread_only:
        stmt = stmt.where(Notification.read_at.is_(None))
    total = (await db.execute(sa.select(sa.func.count()).select_from(stmt.subquery()))).scalar_one()
    rows = (await db.execute(stmt.order_by(Notification.created_at.desc()).offset((page - 1) * page_size)
                             .limit(page_size))).scalars().all()
    items = []
    for n in rows:
        d = notification_out(n)
        d["created_at"], d["read_at"] = as_utc(d["created_at"]), as_utc(d["read_at"])
        items.append(d)
    return {"items": items, "total": total, "page": page, "page_size": page_size}


@router.get("/notifications/unread-count", response_model=Count)
async def unread_count(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    n = (await db.execute(sa.select(sa.func.count()).where(
        Notification.user_id == user.id, Notification.read_at.is_(None)))).scalar_one()
    return {"count": n}


@router.post("/notifications/read-all", status_code=204)
async def read_all(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await db.execute(sa.update(Notification).where(Notification.user_id == user.id, Notification.read_at.is_(None))
                     .values(read_at=utcnow()))
    await db.commit()
    return Response(status_code=204)


@router.post("/notifications/{notification_id}/read", status_code=204)
async def read_one(notification_id: uuid.UUID, user: User = Depends(get_current_user),
                   db: AsyncSession = Depends(get_db)):
    n = await db.get(Notification, notification_id)
    if n is None or n.user_id != user.id:
        raise not_found("Notification")
    n.read_at = n.read_at or utcnow()
    await db.commit()
    return Response(status_code=204)


def _settings_out(o) -> dict:
    return {k: getattr(o, k) for k in OrgSettingsOut.model_fields}


@router.get("/settings", response_model=OrgSettingsOut)
async def get_settings(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return _settings_out(await get_org_settings(db))


@router.patch("/settings", response_model=OrgSettingsOut)
async def update_settings(body: OrgSettingsUpdate, request: Request, user: User = Depends(require(P.SETTINGS_MANAGE)),
                          db: AsyncSession = Depends(get_db)):
    org = await get_org_settings(db)
    data = body.model_dump(exclude_unset=True)
    if data.pop("reset_credits_used", False):
        org.credits_used_minutes = 0
    if "timezone" in data and data["timezone"]:
        try:
            ZoneInfo(data["timezone"])
        except Exception as exc:  # noqa: BLE001
            raise AppError(422, "validation_error", "Unknown timezone") from exc
    if "calling_days" in data and data["calling_days"] is not None:
        if any(d < 1 or d > 7 for d in data["calling_days"]):
            raise AppError(422, "validation_error", "calling_days must be 1 (Mon) … 7 (Sun)")
    start = data.get("calling_hours_start", org.calling_hours_start)
    end = data.get("calling_hours_end", org.calling_hours_end)
    if start >= end:
        raise AppError(422, "validation_error", "calling_hours_start must be before calling_hours_end")
    for k, v in data.items():
        if v is not None or k == "calling_credits_minutes":
            setattr(org, k, v)
    await audit(db, user, "settings.updated", "org_settings", 1, data, request)
    await db.commit()
    return _settings_out(org)


@router.get("/settings/telephony-status", response_model=TelephonyStatus)
async def get_telephony_status(user: User = Depends(get_current_user)):
    return telephony_status()


@router.get("/audit-logs", response_model=Page[AuditLogOut])
async def audit_logs(actor_id: uuid.UUID | None = None, action: str | None = None, entity_type: str | None = None,
                     page: int = Query(1, ge=1), page_size: int = Query(50, ge=1, le=100),
                     user: User = Depends(require(P.AUDIT_VIEW)), db: AsyncSession = Depends(get_db)):
    stmt = sa.select(AuditLog)
    if actor_id:
        stmt = stmt.where(AuditLog.actor_id == actor_id)
    if action:
        stmt = stmt.where(AuditLog.action.like(f"{action}%"))
    if entity_type:
        stmt = stmt.where(AuditLog.entity_type == entity_type)
    total = (await db.execute(sa.select(sa.func.count()).select_from(stmt.subquery()))).scalar_one()
    rows = (await db.execute(stmt.order_by(AuditLog.created_at.desc()).offset((page - 1) * page_size)
                             .limit(page_size))).scalars().all()
    return {"items": [{"id": r.id, "actor_id": r.actor_id, "actor_name": r.actor_name, "action": r.action,
                       "entity_type": r.entity_type, "entity_id": r.entity_id, "details": r.details or {},
                       "ip_address": r.ip_address, "created_at": as_utc(r.created_at)} for r in rows],
            "total": total, "page": page, "page_size": page_size}
