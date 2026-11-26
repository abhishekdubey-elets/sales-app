import logging
import uuid
from collections.abc import Iterable

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import SessionLocal, utcnow
from app.core.tasks import spawn
from app.models import DeviceToken, Notification
from app.models.enums import NotificationType
from app.realtime.hub import hub
from app.services.push import fcm

log = logging.getLogger(__name__)


def notification_out(n: Notification) -> dict:
    return {
        "id": n.id, "type": n.type, "title": n.title, "body": n.body, "data": n.data or {},
        "read_at": n.read_at, "created_at": n.created_at,
    }


async def notify(
    db: AsyncSession,
    user_ids: Iterable[uuid.UUID],
    type_: NotificationType,
    title: str,
    body: str = "",
    data: dict | None = None,
) -> list[Notification]:
    """Persist notifications. Delivery (WS + FCM) happens after the caller commits — see `deliver`."""
    rows = []
    for uid in {u for u in user_ids if u}:
        n = Notification(user_id=uid, type=type_.value, title=title, body=body, data=data or {})
        db.add(n)
        rows.append(n)
    await db.flush()
    pending = db.info.setdefault("pending_notifications", [])
    pending.extend(n.id for n in rows)
    return rows


async def deliver_pending(db: AsyncSession) -> None:
    """Call after commit: pushes the notifications created in this session over WS and FCM."""
    ids = db.info.pop("pending_notifications", [])
    if ids:
        await spawn(_deliver(ids))


async def _deliver(ids: list[uuid.UUID]) -> None:
    try:
        async with SessionLocal() as db:
            rows = (await db.execute(sa.select(Notification).where(Notification.id.in_(ids)))).scalars().all()
            for n in rows:
                await hub.publish([n.user_id], "notification", notification_out(n))
            if fcm.enabled:
                for n in rows:
                    tokens = (
                        await db.execute(sa.select(DeviceToken.token).where(DeviceToken.user_id == n.user_id))
                    ).scalars().all()
                    dead = await fcm.send(list(tokens), n.title, n.body, {"type": n.type, "id": str(n.id),
                                                                          **{k: str(v) for k, v in (n.data or {}).items()}})
                    if dead:
                        await db.execute(sa.delete(DeviceToken).where(DeviceToken.token.in_(dead)))
                    n.pushed_at = utcnow()
                await db.commit()
    except Exception:  # noqa: BLE001
        log.exception("notification delivery failed")


async def commit_and_deliver(db: AsyncSession) -> None:
    await db.commit()
    await deliver_pending(db)
