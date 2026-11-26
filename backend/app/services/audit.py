from typing import Any

from fastapi import Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import client_ip
from app.models import AuditLog, User


async def audit(
    db: AsyncSession,
    actor: User | None,
    action: str,
    entity_type: str | None = None,
    entity_id: Any = None,
    details: dict | None = None,
    request: Request | None = None,
) -> None:
    db.add(
        AuditLog(
            actor_id=actor.id if actor else None,
            actor_name=actor.full_name if actor else "system",
            action=action,
            entity_type=entity_type,
            entity_id=str(entity_id) if entity_id is not None else None,
            details=details or {},
            ip_address=client_ip(request) if request else None,
        )
    )
