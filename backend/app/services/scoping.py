"""Row-level data scoping: executive → own, manager → own team, admin → all."""

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import not_found
from app.core.permissions import Role
from app.models import AICall, HumanCall, Lead, OrgSettings, User


def _team_members(user: User):
    return sa.select(User.id).where(User.team_id == user.team_id)


def scope_leads(stmt, user: User):
    stmt = stmt.where(Lead.deleted_at.is_(None))
    if user.role_name == Role.ADMIN:
        return stmt
    if user.role_name == Role.MANAGER:
        if user.team_id is None:
            return stmt.where(sa.or_(Lead.assigned_to_id == user.id, Lead.assigned_to_id.is_(None)))
        return stmt.where(sa.or_(Lead.assigned_to_id.in_(_team_members(user)), Lead.assigned_to_id.is_(None)))
    return stmt.where(Lead.assigned_to_id == user.id)


def scope_human_calls(stmt, user: User):
    if user.role_name == Role.ADMIN:
        return stmt
    if user.role_name == Role.MANAGER and user.team_id is not None:
        return stmt.where(HumanCall.salesperson_id.in_(_team_members(user)))
    return stmt.where(HumanCall.salesperson_id == user.id)


def scope_ai_calls(stmt, user: User):
    if user.role_name in (Role.ADMIN, Role.MANAGER):
        return stmt
    return stmt.where(AICall.lead_id.in_(sa.select(Lead.id).where(Lead.assigned_to_id == user.id)))


def scope_users(stmt, user: User):
    if user.role_name == Role.ADMIN:
        return stmt
    if user.role_name == Role.MANAGER and user.team_id is not None:
        return stmt.where(User.team_id == user.team_id)
    return stmt.where(User.id == user.id)


async def get_visible_lead(db: AsyncSession, user: User, lead_id) -> Lead:
    lead = (await db.execute(scope_leads(sa.select(Lead).where(Lead.id == lead_id), user))).scalar_one_or_none()
    if lead is None:
        raise not_found("Lead")
    return lead


async def get_visible_human_call(db: AsyncSession, user: User, call_id) -> HumanCall:
    call = (
        await db.execute(scope_human_calls(sa.select(HumanCall).where(HumanCall.id == call_id), user))
    ).scalar_one_or_none()
    if call is None:
        raise not_found("Call")
    return call


async def get_visible_ai_call(db: AsyncSession, user: User, call_id) -> AICall:
    call = (await db.execute(scope_ai_calls(sa.select(AICall).where(AICall.id == call_id), user))).scalar_one_or_none()
    if call is None:
        raise not_found("AI call")
    return call


def sees_full_numbers(user: User, org: OrgSettings) -> bool:
    return user.role_name in (Role.ADMIN, Role.MANAGER) or not org.mask_numbers_for_executives


def is_supervisor(user: User) -> bool:
    return user.role_name in (Role.ADMIN, Role.MANAGER)
