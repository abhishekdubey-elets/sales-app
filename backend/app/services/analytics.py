"""Role-scoped reporting over human and AI calls (kept in separate tables, reported side by side)."""

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import utcnow
from app.core.permissions import Role
from app.core.timeranges import resolve_range
from app.models import AIAgent, AICall, AICampaign, Followup, HumanCall, Lead, RoleModel, Team, User
from app.models.enums import (
    NOT_CONNECTED_STATUSES,
    SUCCESSFUL_OUTCOMES,
    CallDirection,
    CallOutcome,
    CallStatus,
    FollowupStatus,
    LeadStatus,
)
from app.services.campaigns import campaign_stats
from app.services.scoping import scope_ai_calls, scope_human_calls, scope_leads

_CONNECTED_H = HumanCall.answered_at.is_not(None)
_CONNECTED_A = AICall.answered_at.is_not(None)
_AI_SUCCESS = sa.and_(_CONNECTED_A, sa.or_(AICall.interest_level.in_(["high", "medium"]),
                                           AICall.qualification_score >= 60))


def _count(cond) -> sa.ColumnElement:
    return sa.func.count(sa.case((cond, 1)))


def scope_name(user: User) -> str:
    return {Role.ADMIN: "organization", Role.MANAGER: "team"}.get(user.role_name, "personal")


def _followup_scope(stmt, user: User):
    if user.role_name == Role.ADMIN:
        return stmt
    if user.role_name == Role.MANAGER and user.team_id:
        return stmt.where(Followup.assigned_to_id.in_(sa.select(User.id).where(User.team_id == user.team_id)))
    return stmt.where(Followup.assigned_to_id == user.id)


async def dashboard(db: AsyncSession, user: User, start: datetime, end: datetime) -> dict:
    h = scope_human_calls(
        sa.select(
            sa.func.count(),
            _count(sa.and_(_CONNECTED_H, HumanCall.outcome.in_([o.value for o in SUCCESSFUL_OUTCOMES]))),
            _count(sa.and_(HumanCall.direction == CallDirection.INBOUND, HumanCall.status != CallStatus.COMPLETED)),
            _count(_CONNECTED_H),
            _count(sa.and_(HumanCall.direction == CallDirection.OUTBOUND,
                           HumanCall.status.in_([s.value for s in NOT_CONNECTED_STATUSES]))),
            sa.func.coalesce(sa.func.sum(HumanCall.talk_seconds), 0),
        ).where(HumanCall.started_at >= start, HumanCall.started_at < end),
        user,
    )
    total, successful, missed, connected, not_connected, duration = (await db.execute(h)).one()
    total_leads = (await db.execute(sa.select(sa.func.count()).select_from(
        scope_leads(sa.select(Lead.id), user).subquery()))).scalar_one()
    converted = (await db.execute(sa.select(sa.func.count()).select_from(
        scope_leads(sa.select(Lead.id).where(Lead.status == LeadStatus.CONVERTED, Lead.updated_at >= start,
                                             Lead.updated_at < end), user).subquery()))).scalar_one()
    pending_fu = (await db.execute(_followup_scope(
        sa.select(sa.func.count()).select_from(Followup).where(Followup.status == FollowupStatus.PENDING), user)
    )).scalar_one()
    ai_total, ai_success = (await db.execute(scope_ai_calls(
        sa.select(sa.func.count(), _count(_AI_SUCCESS)).where(AICall.started_at >= start, AICall.started_at < end),
        user))).one()
    return {
        "scope": scope_name(user), "total_leads": total_leads, "total_calls": total, "successful_calls": successful,
        "missed_calls": missed, "connected_calls": connected, "not_connected": not_connected,
        "total_duration_seconds": int(duration or 0), "pending_followups": pending_fu, "leads_converted": converted,
        "ai_calls": ai_total, "ai_successful_conversations": ai_success,
    }


async def leaderboard(db: AsyncSession, user: User, start: datetime, end: datetime, team_id=None) -> list[dict]:
    people = sa.select(User).join(RoleModel, User.role_id == RoleModel.id).where(
        User.is_active.is_(True), RoleModel.name.in_([Role.EXECUTIVE.value, Role.MANAGER.value]))
    if user.role_name == Role.MANAGER and user.team_id:
        people = people.where(User.team_id == user.team_id)
    elif user.role_name == Role.EXECUTIVE:
        people = people.where(User.team_id == user.team_id) if user.team_id else people.where(User.id == user.id)
    if team_id:
        people = people.where(User.team_id == team_id)
    users = (await db.execute(people)).scalars().unique().all()
    agg = dict(
        (row[0], row[1:]) for row in (await db.execute(
            sa.select(
                HumanCall.salesperson_id, sa.func.count(), _count(_CONNECTED_H),
                sa.func.coalesce(sa.func.sum(HumanCall.talk_seconds), 0),
                _count(HumanCall.outcome == CallOutcome.CONVERTED),
            ).where(HumanCall.started_at >= start, HumanCall.started_at < end,
                    HumanCall.salesperson_id.in_([u.id for u in users]))
            .group_by(HumanCall.salesperson_id)
        )).all()
    )
    rows = []
    for u in users:
        calls, connected, duration, conversions = agg.get(u.id, (0, 0, 0, 0))
        rows.append({"user_id": u.id, "name": u.full_name, "team_name": u.team.name if u.team else None,
                     "calls": calls, "connected": connected, "duration_seconds": int(duration or 0),
                     "conversions": conversions})
    rows.sort(key=lambda r: (-r["calls"], -r["connected"], r["name"]))
    return rows


def _local_date(col, dialect: str, tz: str):
    if dialect == "postgresql":
        return sa.func.to_char(sa.func.timezone(tz, col), "YYYY-MM-DD")
    offset = ZoneInfo(tz).utcoffset(datetime.now()) or timedelta()
    minutes = int(offset.total_seconds() // 60)
    return sa.func.date(col, f"{'+' if minutes >= 0 else '-'}{abs(minutes)} minutes")


async def calls_by_date(db: AsyncSession, user: User, start: datetime, end: datetime, tz: str) -> list[dict]:
    dialect = db.bind.dialect.name
    hd = _local_date(HumanCall.started_at, dialect, tz)
    ad = _local_date(AICall.started_at, dialect, tz)
    human = dict((d, (n, c)) for d, n, c in (await db.execute(scope_human_calls(
        sa.select(hd, sa.func.count(), _count(_CONNECTED_H))
        .where(HumanCall.started_at >= start, HumanCall.started_at < end).group_by(hd), user))).all())
    ai = dict((d, (n, c)) for d, n, c in (await db.execute(scope_ai_calls(
        sa.select(ad, sa.func.count(), _count(_CONNECTED_A))
        .where(AICall.started_at >= start, AICall.started_at < end).group_by(ad), user))).all())
    out = []
    zone = ZoneInfo(tz)
    day = start.astimezone(zone).date()
    last = (end - timedelta(seconds=1)).astimezone(zone).date()
    while day <= last:
        key = day.isoformat()
        hn, hc = human.get(key, (0, 0))
        an, ac = ai.get(key, (0, 0))
        out.append({"date": key, "human": hn, "ai": an, "human_connected": hc, "ai_connected": ac})
        day += timedelta(days=1)
    return out


async def calls_by_department(db: AsyncSession, user: User, start: datetime, end: datetime) -> list[dict]:
    dept = sa.func.coalesce(Team.department, Team.name, "Unassigned")
    rows = (await db.execute(scope_human_calls(
        sa.select(dept, sa.func.count(), _count(_CONNECTED_H), sa.func.coalesce(sa.func.sum(HumanCall.talk_seconds), 0),
                  _count(HumanCall.outcome == CallOutcome.CONVERTED))
        .select_from(HumanCall).outerjoin(Team, Team.id == HumanCall.team_id)
        .where(HumanCall.started_at >= start, HumanCall.started_at < end).group_by(dept), user))).all()
    return [{"department": d or "Unassigned", "calls": n, "connected": c, "duration_seconds": int(s or 0),
             "conversions": conv} for d, n, c, s, conv in rows]


async def human_vs_ai(db: AsyncSession, user: User, start: datetime, end: datetime) -> dict:
    h = (await db.execute(scope_human_calls(
        sa.select(sa.func.count(), _count(_CONNECTED_H),
                  sa.func.avg(sa.case((_CONNECTED_H, HumanCall.talk_seconds))),
                  _count(HumanCall.outcome == CallOutcome.INTERESTED),
                  _count(HumanCall.outcome == CallOutcome.CONVERTED),
                  _count(HumanCall.outcome.in_([CallOutcome.MEETING_SCHEDULED.value, CallOutcome.CONVERTED.value])))
        .where(HumanCall.started_at >= start, HumanCall.started_at < end), user))).one()
    a = (await db.execute(scope_ai_calls(
        sa.select(sa.func.count(), _count(_CONNECTED_A),
                  sa.func.avg(sa.case((_CONNECTED_A, AICall.duration_seconds))),
                  _count(AICall.interest_level.in_(["high", "medium"])),
                  _count(sa.or_(AICall.qualification_score >= 60, AICall.interest_level == "high")))
        .where(AICall.started_at >= start, AICall.started_at < end), user))).one()
    ai_converted = (await db.execute(scope_ai_calls(
        sa.select(sa.func.count(sa.distinct(AICall.lead_id))).join(Lead, Lead.id == AICall.lead_id)
        .where(AICall.started_at >= start, AICall.started_at < end, Lead.status == LeadStatus.CONVERTED), user)
    )).scalar_one()

    def pack(r, converted, qualified):
        return {"calls": r[0], "connected": r[1], "avg_duration_seconds": round(float(r[2] or 0), 1),
                "interested": r[3], "converted": converted, "qualified": qualified}

    return {"human": pack(h, h[4], h[5]), "ai": pack(a, ai_converted, a[4])}


async def agent_performance(db: AsyncSession, user: User, start: datetime, end: datetime) -> list[dict]:
    rows = (await db.execute(scope_ai_calls(
        sa.select(AIAgent.id, AIAgent.name, sa.func.count(AICall.id), _count(_CONNECTED_A), _count(_AI_SUCCESS),
                  _count(sa.or_(AICall.qualification_score >= 60, AICall.interest_level == "high")),
                  sa.func.avg(sa.case((_CONNECTED_A, AICall.duration_seconds))),
                  _count(AICall.handoff_requested.is_(True)))
        .select_from(AIAgent).outerjoin(AICall, sa.and_(AICall.agent_id == AIAgent.id, AICall.started_at >= start,
                                                        AICall.started_at < end))
        .group_by(AIAgent.id, AIAgent.name), user))).all()
    return [{"agent_id": r[0], "agent_name": r[1], "calls": r[2], "connected": r[3], "successful": r[4],
             "qualified": r[5], "avg_duration_seconds": round(float(r[6] or 0), 1), "handoffs": r[7]} for r in rows]


async def campaign_performance(db: AsyncSession) -> list[dict]:
    campaigns = (await db.execute(sa.select(AICampaign).order_by(AICampaign.created_at.desc()))).scalars().unique()
    return [{"campaign_id": c.id, "name": c.name, "status": c.status, "stats": await campaign_stats(db, c.id)}
            for c in campaigns]


async def my_stats(db: AsyncSession, user: User, tz: str) -> dict:
    now = utcnow()
    today = resolve_range("today", None, None, tz, now)
    week = resolve_range("this_week", None, None, tz, now)
    month = resolve_range("this_month", None, None, tz, now)
    mine = HumanCall.salesperson_id == user.id

    async def count(start, end) -> int:
        return (await db.execute(sa.select(sa.func.count()).where(
            mine, HumanCall.started_at >= start, HumanCall.started_at < end))).scalar_one()

    connected, missed, avg, interested, converted = (await db.execute(
        sa.select(_count(_CONNECTED_H),
                  _count(sa.or_(sa.and_(HumanCall.direction == CallDirection.INBOUND,
                                        HumanCall.status != CallStatus.COMPLETED),
                                sa.and_(HumanCall.direction == CallDirection.OUTBOUND,
                                        HumanCall.status.in_([s.value for s in NOT_CONNECTED_STATUSES])))),
                  sa.func.avg(sa.case((_CONNECTED_H, HumanCall.talk_seconds))),
                  _count(HumanCall.outcome == CallOutcome.INTERESTED),
                  _count(HumanCall.outcome == CallOutcome.CONVERTED))
        .where(mine, HumanCall.started_at >= month[0], HumanCall.started_at < month[1]))).one()
    pending = (await db.execute(sa.select(sa.func.count()).select_from(Followup).where(
        Followup.assigned_to_id == user.id, Followup.status == FollowupStatus.PENDING))).scalar_one()
    return {
        "calls_today": await count(*today), "calls_this_week": await count(*week),
        "calls_this_month": await count(*month), "connected": connected, "missed": missed,
        "avg_duration_seconds": round(float(avg or 0), 1), "interested": interested, "converted": converted,
        "followups_pending": pending,
    }
