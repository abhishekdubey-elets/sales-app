import re
import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.crypto import blind_index, email_hash, normalize_email, normalize_phone, phone_hash
from app.core.database import as_utc, utcnow
from app.core.errors import AppError, bad_request, forbidden, not_found
from app.core.permissions import Role
from app.models import (
    AICall,
    AIHandoff,
    FavouriteLead,
    Followup,
    HumanCall,
    Lead,
    LeadActivity,
    LeadAssignment,
    User,
)
from app.models.enums import LeadStatus, NotificationType
from app.schemas.leads import LeadCreate, LeadUpdate
from app.services.notifications import notify
from app.services.scoping import scope_leads

_PHONEISH = re.compile(r"^[\d\s+()-]{6,}$")

SORTS = {
    "-created_at": Lead.created_at.desc(),
    "created_at": Lead.created_at.asc(),
    "next_followup_at": Lead.next_followup_at.asc().nulls_last(),
    "-last_called_at": Lead.last_called_at.desc().nulls_last(),
    "full_name": Lead.full_name.asc(),
    "-priority": sa.case({"high": 0, "medium": 1, "low": 2}, value=Lead.priority).asc(),
}


async def add_activity(
    db: AsyncSession, lead_id: uuid.UUID, type_: str, title: str,
    description: str | None = None, actor: User | None = None, ref_id: uuid.UUID | None = None,
) -> None:
    db.add(LeadActivity(
        lead_id=lead_id, type=type_, title=title, description=description,
        actor_id=actor.id if actor else None, actor_name=actor.full_name if actor else "System", ref_id=ref_id,
    ))


async def find_duplicate(
    db: AsyncSession, phone: str | None, email: str | None, exclude_id: uuid.UUID | None = None
) -> tuple[Lead | None, str | None]:
    base = sa.select(Lead).where(Lead.deleted_at.is_(None))
    if exclude_id:
        base = base.where(Lead.id != exclude_id)
    ph = phone_hash(phone)
    if ph:
        hit = (await db.execute(
            base.where(sa.or_(Lead.phone_hash == ph, Lead.alternate_phone_hash == ph)).limit(1)
        )).scalar_one_or_none()
        if hit:
            return hit, "phone"
    eh = email_hash(email)
    if eh:
        hit = (await db.execute(base.where(Lead.email_hash == eh).limit(1))).scalar_one_or_none()
        if hit:
            return hit, "email"
    return None, None


async def list_leads(
    db: AsyncSession, user: User, *, q: str | None = None, status: str | None = None, priority: str | None = None,
    assigned_to: str | None = None, source: str | None = None, industry: str | None = None,
    favourites: bool = False, followup_due: bool = False, sort: str = "-created_at", page: int = 1, page_size: int = 20,
) -> tuple[list[Lead], int]:
    stmt = scope_leads(sa.select(Lead), user)
    if q:
        q = q.strip()
        if _PHONEISH.match(q) and normalize_phone(q):
            ph = phone_hash(q)
            stmt = stmt.where(sa.or_(Lead.phone_hash == ph, Lead.alternate_phone_hash == ph))
        elif "@" in q:
            stmt = stmt.where(Lead.email_hash == blind_index(normalize_email(q)))
        else:
            like = f"%{q}%"
            stmt = stmt.where(sa.or_(
                Lead.full_name.ilike(like), Lead.company_name.ilike(like), Lead.designation.ilike(like),
                Lead.location.ilike(like),
            ))
    if status:
        stmt = stmt.where(Lead.status.in_(status.split(",")))
    if priority:
        stmt = stmt.where(Lead.priority.in_(priority.split(",")))
    if source:
        stmt = stmt.where(Lead.source == source)
    if industry:
        stmt = stmt.where(Lead.industry == industry)
    if assigned_to == "me":
        stmt = stmt.where(Lead.assigned_to_id == user.id)
    elif assigned_to == "unassigned":
        stmt = stmt.where(Lead.assigned_to_id.is_(None))
    elif assigned_to:
        try:
            stmt = stmt.where(Lead.assigned_to_id == uuid.UUID(assigned_to))
        except ValueError as exc:
            raise bad_request("assigned_to must be a user id, 'me' or 'unassigned'") from exc
    if favourites:
        stmt = stmt.where(Lead.id.in_(sa.select(FavouriteLead.lead_id).where(FavouriteLead.user_id == user.id)))
    if followup_due:
        stmt = stmt.where(Lead.next_followup_at.is_not(None), Lead.next_followup_at <= utcnow())

    total = (await db.execute(sa.select(sa.func.count()).select_from(stmt.subquery()))).scalar_one()
    order = SORTS.get(sort, SORTS["-created_at"])
    rows = await db.execute(stmt.order_by(order, Lead.id).offset((page - 1) * page_size).limit(page_size))
    return list(rows.scalars().unique()), total


async def _validate_assignee(db: AsyncSession, actor: User, assignee_id: uuid.UUID) -> User:
    assignee = await db.get(User, assignee_id)
    if assignee is None or not assignee.is_active:
        raise bad_request("Assignee not found or inactive", code="validation_error")
    if actor.role_name == Role.MANAGER and actor.team_id and assignee.team_id != actor.team_id and assignee.id != actor.id:
        raise forbidden("Managers can only assign leads within their team")
    return assignee


async def create_lead(db: AsyncSession, actor: User, data: LeadCreate, *, source_override: str | None = None) -> Lead:
    dup, matched = await find_duplicate(db, data.phone, data.email)
    if dup:
        raise AppError(409, "duplicate_lead", f"A lead with this {matched} already exists",
                       duplicate_lead_id=str(dup.id), matched_on=matched)
    if data.alternate_phone:
        dup_alt, _ = await find_duplicate(db, data.alternate_phone, None)
        if dup_alt:
            raise AppError(409, "duplicate_lead", "A lead with this alternate phone already exists",
                           duplicate_lead_id=str(dup_alt.id), matched_on="phone")

    assignee_id = data.assigned_to_id
    if actor.role_name == Role.EXECUTIVE:
        assignee_id = actor.id  # executives own the leads they create
    elif assignee_id:
        await _validate_assignee(db, actor, assignee_id)

    lead = Lead(
        full_name=data.full_name.strip(), company_name=data.company_name, phone=data.phone,
        phone_hash=phone_hash(data.phone), alternate_phone=data.alternate_phone,
        alternate_phone_hash=phone_hash(data.alternate_phone), email=normalize_email(data.email),
        email_hash=email_hash(data.email), designation=data.designation, industry=data.industry,
        location=data.location, source=source_override or data.source, priority=data.priority.value,
        remarks=data.remarks, consent_status=data.consent_status.value, assigned_to_id=assignee_id,
        status=LeadStatus.ASSIGNED if assignee_id else LeadStatus.NEW, created_by_id=actor.id,
    )
    db.add(lead)
    await db.flush()
    await add_activity(db, lead.id, "created", "Lead created", f"Source: {lead.source or 'manual'}", actor)
    if assignee_id:
        db.add(LeadAssignment(lead_id=lead.id, to_user_id=assignee_id, assigned_by_id=actor.id))
        if assignee_id != actor.id:
            await notify(db, [assignee_id], NotificationType.LEAD_ASSIGNED, "New lead assigned",
                         f"{lead.full_name}{' · ' + lead.company_name if lead.company_name else ''}",
                         {"lead_id": str(lead.id)})
    await db.refresh(lead, ["assigned_to"])
    return lead


async def update_lead(db: AsyncSession, actor: User, lead: Lead, data: LeadUpdate) -> Lead:
    fields = data.model_dump(exclude_unset=True)
    if "phone" in fields or "email" in fields or "alternate_phone" in fields:
        dup, matched = await find_duplicate(db, fields.get("phone"), fields.get("email"), exclude_id=lead.id)
        if dup:
            raise AppError(409, "duplicate_lead", f"A lead with this {matched} already exists",
                           duplicate_lead_id=str(dup.id), matched_on=matched)
    if "assigned_to_id" in fields:
        new_assignee = fields.pop("assigned_to_id")
        if new_assignee != lead.assigned_to_id:
            if actor.role_name == Role.EXECUTIVE:
                raise forbidden("Only managers and admins can reassign leads")
            if new_assignee:
                await assign_leads(db, actor, [lead.id], new_assignee)
            else:
                _unassign(db, actor, lead)
    if "status" in fields and fields["status"] != lead.status:
        await add_activity(db, lead.id, "status_changed", f"Status changed to {fields['status'].replace('_', ' ')}",
                           f"From {lead.status.replace('_', ' ')}", actor)
    for key, value in fields.items():
        if key == "phone" and value:
            lead.phone, lead.phone_hash = value, phone_hash(value)
        elif key == "alternate_phone":
            lead.alternate_phone, lead.alternate_phone_hash = value, phone_hash(value)
        elif key == "email":
            lead.email, lead.email_hash = normalize_email(value), email_hash(value)
        elif hasattr(value, "value"):
            setattr(lead, key, value.value)
        else:
            setattr(lead, key, value)
    lead.updated_at = utcnow()
    await db.flush()
    await db.refresh(lead, ["assigned_to"])
    return lead


def _unassign(db: AsyncSession, actor: User, lead: Lead) -> None:
    db.add(LeadAssignment(lead_id=lead.id, from_user_id=lead.assigned_to_id, to_user_id=None, assigned_by_id=actor.id))
    lead.assigned_to_id = None


async def assign_leads(db: AsyncSession, actor: User, lead_ids: list[uuid.UUID], assignee_id: uuid.UUID) -> int:
    assignee = await _validate_assignee(db, actor, assignee_id)
    leads = (await db.execute(scope_leads(sa.select(Lead).where(Lead.id.in_(lead_ids)), actor))).scalars().unique().all()
    changed: list[Lead] = []
    for lead in leads:
        if lead.assigned_to_id == assignee.id:
            continue
        db.add(LeadAssignment(lead_id=lead.id, from_user_id=lead.assigned_to_id, to_user_id=assignee.id,
                              assigned_by_id=actor.id))
        lead.assigned_to_id = assignee.id
        if lead.status == LeadStatus.NEW:
            lead.status = LeadStatus.ASSIGNED
        await add_activity(db, lead.id, "assigned", f"Assigned to {assignee.full_name}", None, actor)
        changed.append(lead)
    if changed and assignee.id != actor.id:
        n = len(changed)
        title = "New lead assigned" if n == 1 else f"{n} new leads assigned"
        body = changed[0].full_name if n == 1 else f"Assigned by {actor.full_name}"
        data = {"lead_id": str(changed[0].id)} if n == 1 else {"count": n}
        await notify(db, [assignee.id], NotificationType.LEAD_ASSIGNED, title, body, data)
    await db.flush()
    return len(changed)


async def soft_delete(db: AsyncSession, actor: User, lead: Lead) -> None:
    lead.deleted_at = utcnow()
    await add_activity(db, lead.id, "deleted", "Lead deleted", None, actor)


async def timeline(db: AsyncSession, lead: Lead) -> list[dict]:
    items: list[dict] = []
    for a in (await db.execute(sa.select(LeadActivity).where(LeadActivity.lead_id == lead.id))).scalars():
        items.append({"id": a.id, "type": a.type, "at": as_utc(a.created_at), "title": a.title,
                      "description": a.description, "actor_name": a.actor_name, "ref_id": a.ref_id})
    for c in (await db.execute(sa.select(HumanCall).where(HumanCall.lead_id == lead.id))).scalars():
        desc = c.status.replace("_", " ").title()
        if c.talk_seconds:
            desc += f" · {c.talk_seconds // 60}m {c.talk_seconds % 60}s"
        if c.outcome:
            desc += f" · {c.outcome.replace('_', ' ')}"
        items.append({"id": c.id, "type": "human_call", "at": as_utc(c.started_at),
                      "title": f"{'Inbound' if c.direction == 'inbound' else 'Call'} by {c.salesperson_name}",
                      "description": desc, "actor_name": c.salesperson_name, "ref_id": c.id})
    for c in (await db.execute(sa.select(AICall).where(AICall.lead_id == lead.id))).scalars():
        desc = c.summary or c.status.replace("_", " ").title()
        items.append({"id": c.id, "type": "ai_call", "at": as_utc(c.started_at),
                      "title": f"AI call · {c.agent.name if c.agent else 'agent'}", "description": desc,
                      "actor_name": c.agent.name if c.agent else None, "ref_id": c.id})
    for h in (await db.execute(sa.select(AIHandoff).where(AIHandoff.lead_id == lead.id))).scalars():
        items.append({"id": h.id, "type": "handoff", "at": as_utc(h.created_at), "title": "Requested a human salesperson",
                      "description": h.reason, "actor_name": "AI agent", "ref_id": h.ai_call_id})
    for f in (await db.execute(sa.select(Followup).where(Followup.lead_id == lead.id))).scalars():
        items.append({"id": f.id, "type": "followup", "at": as_utc(f.created_at),
                      "title": f"Follow-up {f.status} · due {as_utc(f.due_at):%d %b %Y %H:%M} UTC",
                      "description": f.note, "actor_name": None, "ref_id": f.id})
    items.sort(key=lambda i: i["at"] or datetime.min, reverse=True)
    return items


async def set_favourite(db: AsyncSession, user: User, lead: Lead, on: bool) -> None:
    existing = await db.get(FavouriteLead, (user.id, lead.id))
    if on and existing is None:
        db.add(FavouriteLead(user_id=user.id, lead_id=lead.id))
    elif not on and existing is not None:
        await db.delete(existing)


async def get_lead_or_404(db: AsyncSession, lead_id: uuid.UUID) -> Lead:
    lead = await db.get(Lead, lead_id)
    if lead is None or lead.deleted_at is not None:
        raise not_found("Lead")
    return lead
