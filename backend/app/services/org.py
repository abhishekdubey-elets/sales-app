"""Org settings + recipient helpers shared by services."""

import uuid

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.permissions import Role
from app.models import OrgSettings, RoleModel, Team, User


async def get_org_settings(db: AsyncSession) -> OrgSettings:
    row = await db.get(OrgSettings, 1)
    if row is None:
        row = OrgSettings(id=1, timezone=settings.ORG_TIMEZONE)
        db.add(row)
        await db.flush()
    return row


async def admin_ids(db: AsyncSession) -> list[uuid.UUID]:
    rows = await db.execute(
        sa.select(User.id).join(RoleModel, User.role_id == RoleModel.id)
        .where(RoleModel.name == Role.ADMIN.value, User.is_active.is_(True))
    )
    return list(rows.scalars())


async def team_manager_id(db: AsyncSession, team_id: uuid.UUID | None) -> uuid.UUID | None:
    if team_id is None:
        return None
    team = await db.get(Team, team_id)
    return team.manager_id if team else None


async def supervisors_of(db: AsyncSession, user_id: uuid.UUID | None) -> set[uuid.UUID]:
    """The user, their team manager and all admins — the audience for a salesperson's call events."""
    ids: set[uuid.UUID] = set(await admin_ids(db))
    if user_id:
        ids.add(user_id)
        user = await db.get(User, user_id)
        if user and user.team_id:
            mgr = await team_manager_id(db, user.team_id)
            if mgr:
                ids.add(mgr)
    return ids


async def managers_and_admins(db: AsyncSession) -> list[uuid.UUID]:
    rows = await db.execute(
        sa.select(User.id).join(RoleModel, User.role_id == RoleModel.id)
        .where(RoleModel.name.in_([Role.ADMIN.value, Role.MANAGER.value]), User.is_active.is_(True))
    )
    return list(rows.scalars())


async def team_member_ids(db: AsyncSession, team_id: uuid.UUID | None) -> list[uuid.UUID]:
    if team_id is None:
        return []
    rows = await db.execute(sa.select(User.id).where(User.team_id == team_id))
    return list(rows.scalars())
