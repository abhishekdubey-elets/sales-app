import uuid

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.crypto import mask_phone
from app.core.database import as_utc
from app.models import (
    AICall,
    CallNote,
    CallRecording,
    FavouriteLead,
    HumanCall,
    Lead,
    Team,
    User,
)


def user_out(u: User) -> dict:
    return {
        "id": u.id, "full_name": u.full_name, "email": u.email, "phone": u.phone,
        "calling_number": u.calling_number, "role": u.role_name, "team_id": u.team_id,
        "team_name": u.team.name if u.team else None, "is_active": u.is_active,
        "last_login_at": as_utc(u.last_login_at), "created_at": as_utc(u.created_at),
    }


async def team_out(db: AsyncSession, t: Team) -> dict:
    manager_name = None
    if t.manager_id:
        manager_name = (await db.execute(sa.select(User.full_name).where(User.id == t.manager_id))).scalar()
    count = (await db.execute(sa.select(sa.func.count()).select_from(User).where(User.team_id == t.id))).scalar_one()
    return {
        "id": t.id, "name": t.name, "department": t.department, "manager_id": t.manager_id,
        "manager_name": manager_name, "member_count": count,
    }


def _maybe_mask(phone: str | None, full: bool) -> str | None:
    if phone is None:
        return None
    return phone if full else mask_phone(phone)


async def leads_out(db: AsyncSession, leads: list[Lead], viewer: User, full_numbers: bool) -> list[dict]:
    if not leads:
        return []
    ids = [lead.id for lead in leads]
    favs = set(
        (await db.execute(
            sa.select(FavouriteLead.lead_id).where(FavouriteLead.user_id == viewer.id, FavouriteLead.lead_id.in_(ids))
        )).scalars()
    )
    counts: dict[uuid.UUID, int] = {}
    for model in (HumanCall, AICall):
        rows = await db.execute(
            sa.select(model.lead_id, sa.func.count()).where(model.lead_id.in_(ids)).group_by(model.lead_id)
        )
        for lead_id, n in rows:
            counts[lead_id] = counts.get(lead_id, 0) + n
    return [lead_out(lead, full_numbers, lead.id in favs, counts.get(lead.id, 0)) for lead in leads]


def lead_out(lead: Lead, full_numbers: bool, is_favourite: bool = False, call_count: int = 0) -> dict:
    return {
        "id": lead.id, "full_name": lead.full_name, "company_name": lead.company_name,
        "phone": _maybe_mask(lead.phone, full_numbers), "phone_masked": mask_phone(lead.phone),
        "alternate_phone": _maybe_mask(lead.alternate_phone, full_numbers),
        "email": lead.email, "designation": lead.designation, "industry": lead.industry,
        "location": lead.location, "source": lead.source, "assigned_to_id": lead.assigned_to_id,
        "assigned_to_name": lead.assigned_to.full_name if lead.assigned_to else None,
        "status": lead.status, "priority": lead.priority, "last_called_at": as_utc(lead.last_called_at),
        "next_followup_at": as_utc(lead.next_followup_at), "remarks": lead.remarks,
        "consent_status": lead.consent_status, "opted_out": lead.opted_out, "is_favourite": is_favourite,
        "call_count": call_count, "created_at": as_utc(lead.created_at), "updated_at": as_utc(lead.updated_at),
    }


def note_out(n: CallNote) -> dict:
    return {"id": n.id, "body": n.body, "author_id": n.author_id, "author_name": n.author_name,
            "created_at": as_utc(n.created_at)}


async def human_calls_out(
    db: AsyncSession, calls: list[HumanCall], full_numbers: bool, with_notes: bool = False
) -> list[dict]:
    if not calls:
        return []
    ids = [c.id for c in calls]
    recs = dict(
        (await db.execute(
            sa.select(CallRecording.human_call_id, CallRecording.id).where(CallRecording.human_call_id.in_(ids))
        )).all()
    )
    notes: dict[uuid.UUID, list[dict]] = {}
    if with_notes:
        rows = (await db.execute(
            sa.select(CallNote).where(CallNote.human_call_id.in_(ids)).order_by(CallNote.created_at)
        )).scalars()
        for n in rows:
            notes.setdefault(n.human_call_id, []).append(note_out(n))
    return [human_call_out(c, full_numbers, recs.get(c.id), notes.get(c.id, [])) for c in calls]


def human_call_out(c: HumanCall, full_numbers: bool, recording_id=None, notes: list | None = None) -> dict:
    return {
        "id": c.id, "direction": c.direction, "lead_id": c.lead_id, "lead_name": c.lead_name,
        "phone_number": _maybe_mask(c.phone_number, full_numbers), "salesperson_id": c.salesperson_id,
        "salesperson_name": c.salesperson_name, "provider": c.provider, "provider_call_id": c.provider_call_id,
        "status": c.status, "started_at": as_utc(c.started_at), "answered_at": as_utc(c.answered_at),
        "ended_at": as_utc(c.ended_at), "duration_seconds": c.duration_seconds, "talk_seconds": c.talk_seconds,
        "recording_id": recording_id, "outcome": c.outcome, "followup_at": as_utc(c.followup_at),
        "failure_reason": c.failure_reason, "notes": notes or [], "created_at": as_utc(c.created_at),
    }


def ai_call_out(c: AICall) -> dict:
    return {
        "id": c.id, "agent_id": c.agent_id, "agent_name": c.agent.name if c.agent else "",
        "campaign_id": c.campaign_id, "campaign_name": c.campaign.name if c.campaign else None,
        "lead_id": c.lead_id, "lead_name": c.lead_name, "phone_masked": mask_phone(c.phone_number),
        "provider": c.provider, "provider_call_id": c.provider_call_id, "status": c.status,
        "attempt": c.attempt, "started_at": as_utc(c.started_at), "answered_at": as_utc(c.answered_at),
        "ended_at": as_utc(c.ended_at), "duration_seconds": c.duration_seconds,
        "interest_level": c.interest_level, "qualification_score": c.qualification_score,
        "handoff_requested": c.handoff_requested, "summary": c.summary, "failure_reason": c.failure_reason,
        "created_at": as_utc(c.created_at),
    }
