import time
import uuid
from datetime import date, datetime, timezone

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import as_utc, get_db, utcnow
from app.core.deps import get_current_user, require
from app.core.errors import AppError, forbidden, not_found
from app.core.permissions import P, Role
from app.core.security import sign_resource, verify_resource_signature
from app.core.timeranges import resolve_range
from app.models import CallNote, CallRecording, Followup, HumanCall, Lead, User
from app.models.enums import ACTIVE_CALL_STATUSES, FollowupStatus
from app.schemas.calls import (
    CallNoteOut,
    DispositionIn,
    FollowupCreate,
    FollowupOut,
    FollowupUpdate,
    HumanCallOut,
    NoteIn,
    StartCallIn,
)
from app.schemas.common import Page, SignedUrl
from app.services import calls as svc
from app.services.audit import audit
from app.services.notifications import commit_and_deliver
from app.services.org import get_org_settings
from app.services.scoping import (
    get_visible_ai_call,
    get_visible_human_call,
    get_visible_lead,
    scope_human_calls,
)
from app.services.serializers import note_out
from app.telephony.base import TelephonyError
from app.telephony.registry import get_provider

router = APIRouter(tags=["calls"])


async def _out(db: AsyncSession, user: User, call: HumanCall, notes: bool = True) -> dict:
    org = await get_org_settings(db)
    [out] = await svc.calls_out_for(db, user, [call], org, with_notes=notes)
    return out


@router.post("/calls", response_model=HumanCallOut, status_code=201)
async def start_call(body: StartCallIn, user: User = Depends(require(P.CALLS_MAKE)), db: AsyncSession = Depends(get_db)):
    call = await svc.start_human_call(db, user, lead_id=body.lead_id, phone_number=body.phone_number)
    return await _out(db, user, call)


@router.get("/calls", response_model=Page[HumanCallOut])
async def list_calls(
    salesperson_id: uuid.UUID | None = None, lead_id: uuid.UUID | None = None, status: str | None = None,
    outcome: str | None = None, direction: str | None = None, range: str | None = None,
    date_from: date | None = Query(None, alias="from"), date_to: date | None = Query(None, alias="to"),
    page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100),
    user: User = Depends(require(P.CALLS_VIEW)), db: AsyncSession = Depends(get_db),
):
    stmt = scope_human_calls(sa.select(HumanCall), user)
    if salesperson_id:
        stmt = stmt.where(HumanCall.salesperson_id == salesperson_id)
    if lead_id:
        stmt = stmt.where(HumanCall.lead_id == lead_id)
    if status:
        stmt = stmt.where(HumanCall.status.in_(status.split(",")))
    if outcome:
        stmt = stmt.where(HumanCall.outcome.in_(outcome.split(",")))
    if direction:
        stmt = stmt.where(HumanCall.direction == direction)
    if range:
        org = await get_org_settings(db)
        start, end = resolve_range(range, date_from, date_to, org.timezone)
        stmt = stmt.where(HumanCall.started_at >= start, HumanCall.started_at < end)
    total = (await db.execute(sa.select(sa.func.count()).select_from(stmt.subquery()))).scalar_one()
    rows = (await db.execute(stmt.order_by(HumanCall.started_at.desc()).offset((page - 1) * page_size)
                             .limit(page_size))).scalars().all()
    org = await get_org_settings(db)
    return {"items": await svc.calls_out_for(db, user, list(rows), org), "total": total, "page": page,
            "page_size": page_size}


@router.get("/calls/active", response_model=HumanCallOut | None)
async def active_call(user: User = Depends(require(P.CALLS_MAKE)), db: AsyncSession = Depends(get_db)):
    call = (await db.execute(sa.select(HumanCall).where(
        HumanCall.salesperson_id == user.id, HumanCall.status.in_([s.value for s in ACTIVE_CALL_STATUSES])
    ).order_by(HumanCall.started_at.desc()).limit(1))).scalar_one_or_none()
    return await _out(db, user, call) if call else None


@router.get("/calls/recent", response_model=list[HumanCallOut])
async def recent_calls(limit: int = Query(20, ge=1, le=100), user: User = Depends(require(P.CALLS_VIEW)),
                       db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(sa.select(HumanCall).where(HumanCall.salesperson_id == user.id)
                             .order_by(HumanCall.started_at.desc()).limit(limit))).scalars().all()
    org = await get_org_settings(db)
    return await svc.calls_out_for(db, user, list(rows), org)


@router.get("/calls/{call_id}", response_model=HumanCallOut)
async def get_call(call_id: uuid.UUID, user: User = Depends(require(P.CALLS_VIEW)), db: AsyncSession = Depends(get_db)):
    return await _out(db, user, await get_visible_human_call(db, user, call_id))


@router.post("/calls/{call_id}/hangup", response_model=HumanCallOut)
async def hangup(call_id: uuid.UUID, user: User = Depends(require(P.CALLS_MAKE)), db: AsyncSession = Depends(get_db)):
    call = await get_visible_human_call(db, user, call_id)
    await svc.hangup(db, user, call)
    return await _out(db, user, call)


@router.post("/calls/{call_id}/disposition", response_model=HumanCallOut)
async def disposition(call_id: uuid.UUID, body: DispositionIn, user: User = Depends(require(P.CALLS_MAKE)),
                      db: AsyncSession = Depends(get_db)):
    call = await get_visible_human_call(db, user, call_id)
    await svc.save_disposition(db, user, call, body)
    return await _out(db, user, call)


@router.post("/calls/{call_id}/notes", response_model=CallNoteOut, status_code=201)
async def add_note(call_id: uuid.UUID, body: NoteIn, user: User = Depends(require(P.CALLS_VIEW)),
                   db: AsyncSession = Depends(get_db)):
    call = await get_visible_human_call(db, user, call_id)
    note = CallNote(human_call_id=call.id, author_id=user.id, author_name=user.full_name, body=body.body)
    db.add(note)
    await db.commit()
    return note_out(note)


# ── recordings ─────────────────────────────────────────────────────────────
@router.get("/recordings/{recording_id}/url", response_model=SignedUrl)
async def recording_url(recording_id: uuid.UUID, request: Request, user: User = Depends(get_current_user),
                        db: AsyncSession = Depends(get_db)):
    rec = await db.get(CallRecording, recording_id)
    if rec is None:
        raise not_found("Recording")
    if rec.human_call_id:
        if P.RECORDINGS_VIEW.value not in user.permissions:
            call = await get_visible_human_call(db, user, rec.human_call_id)
            if call.salesperson_id != user.id:
                raise forbidden()
        else:
            await get_visible_human_call(db, user, rec.human_call_id)
    else:
        if user.role_name not in (Role.ADMIN, Role.MANAGER):
            raise forbidden("AI call recordings are available to managers and admins")
        await get_visible_ai_call(db, user, rec.ai_call_id)
    exp = int(time.time()) + settings.SIGNED_URL_TTL_SECONDS
    sig = sign_resource("recording", str(rec.id), exp)
    await audit(db, user, "recording.accessed", "call_recording", rec.id,
                {"human_call_id": str(rec.human_call_id or ""), "ai_call_id": str(rec.ai_call_id or "")}, request)
    await db.commit()
    return {"url": f"{settings.API_PUBLIC_BASE_URL}/api/v1/recordings/{rec.id}/stream?exp={exp}&sig={sig}",
            "expires_at": datetime.fromtimestamp(exp, tz=timezone.utc).isoformat()}


@router.get("/recordings/{recording_id}/stream")
async def recording_stream(recording_id: uuid.UUID, exp: int, sig: str, db: AsyncSession = Depends(get_db)):
    if not verify_resource_signature("recording", str(recording_id), exp, sig):
        raise AppError(403, "forbidden", "Link expired or invalid")
    rec = await db.get(CallRecording, recording_id)
    if rec is None:
        raise not_found("Recording")
    provider = get_provider(rec.provider)
    if provider is None:
        raise AppError(503, "telephony_not_configured", "Recording provider is not configured")
    try:
        body, content_type = await provider.open_recording(rec.url)
    except TelephonyError as exc:
        raise AppError(502, "telephony_error", str(exc)) from exc
    return StreamingResponse(body, media_type=content_type, headers={"Cache-Control": "private, no-store"})


# ── follow-ups ─────────────────────────────────────────────────────────────
def _followup_scope(stmt, user: User):
    if user.role_name == Role.ADMIN:
        return stmt
    if user.role_name == Role.MANAGER and user.team_id:
        return stmt.where(sa.or_(Followup.assigned_to_id.in_(sa.select(User.id).where(User.team_id == user.team_id)),
                                 Followup.assigned_to_id.is_(None)))
    return stmt.where(Followup.assigned_to_id == user.id)


async def _followups_out(db: AsyncSession, rows: list[Followup]) -> list[dict]:
    lead_names = dict((await db.execute(sa.select(Lead.id, Lead.full_name).where(
        Lead.id.in_([f.lead_id for f in rows])))).all()) if rows else {}
    user_ids = [f.assigned_to_id for f in rows if f.assigned_to_id]
    user_names = dict((await db.execute(sa.select(User.id, User.full_name).where(User.id.in_(user_ids)))).all()) \
        if user_ids else {}
    return [{"id": f.id, "lead_id": f.lead_id, "lead_name": lead_names.get(f.lead_id),
             "assigned_to_id": f.assigned_to_id, "assigned_to_name": user_names.get(f.assigned_to_id),
             "due_at": as_utc(f.due_at), "status": f.status, "note": f.note, "source": f.source,
             "created_at": as_utc(f.created_at)} for f in rows]


@router.get("/followups", response_model=Page[FollowupOut])
async def list_followups(
    status: str | None = "pending", due: str | None = None, assigned_to: uuid.UUID | None = None,
    page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100),
    user: User = Depends(require(P.LEADS_VIEW)), db: AsyncSession = Depends(get_db),
):
    stmt = _followup_scope(sa.select(Followup), user)
    if status:
        stmt = stmt.where(Followup.status == status)
    if assigned_to:
        stmt = stmt.where(Followup.assigned_to_id == assigned_to)
    if due:
        org = await get_org_settings(db)
        start, end = resolve_range("today", None, None, org.timezone)
        now = utcnow()
        if due == "overdue":
            stmt = stmt.where(Followup.due_at < now)
        elif due == "today":
            stmt = stmt.where(Followup.due_at >= start, Followup.due_at < end)
        elif due == "upcoming":
            stmt = stmt.where(Followup.due_at >= now)
    total = (await db.execute(sa.select(sa.func.count()).select_from(stmt.subquery()))).scalar_one()
    rows = (await db.execute(stmt.order_by(Followup.due_at.asc()).offset((page - 1) * page_size)
                             .limit(page_size))).scalars().all()
    return {"items": await _followups_out(db, list(rows)), "total": total, "page": page, "page_size": page_size}


@router.post("/followups", response_model=FollowupOut, status_code=201)
async def create_followup(body: FollowupCreate, user: User = Depends(require(P.LEADS_EDIT)),
                          db: AsyncSession = Depends(get_db)):
    lead = await get_visible_lead(db, user, body.lead_id)
    assignee = body.assigned_to_id or lead.assigned_to_id or user.id
    if user.role_name == Role.EXECUTIVE:
        assignee = user.id
    f = Followup(lead_id=lead.id, assigned_to_id=assignee, due_at=body.due_at, note=body.note, created_by_id=user.id)
    db.add(f)
    lead.next_followup_at = body.due_at
    await db.commit()
    return (await _followups_out(db, [f]))[0]


@router.patch("/followups/{followup_id}", response_model=FollowupOut)
async def update_followup(followup_id: uuid.UUID, body: FollowupUpdate, user: User = Depends(require(P.LEADS_EDIT)),
                          db: AsyncSession = Depends(get_db)):
    f = (await db.execute(_followup_scope(sa.select(Followup).where(Followup.id == followup_id), user))
         ).scalar_one_or_none()
    if f is None:
        raise not_found("Follow-up")
    data = body.model_dump(exclude_unset=True)
    if "status" in data and data["status"]:
        f.status = data["status"]
        f.completed_at = utcnow() if data["status"] == FollowupStatus.DONE else None
    if "due_at" in data and data["due_at"]:
        f.due_at, f.reminded_at = data["due_at"], None
    if "note" in data:
        f.note = data["note"]
    lead = await db.get(Lead, f.lead_id)
    if lead:
        nxt = (await db.execute(sa.select(sa.func.min(Followup.due_at)).where(
            Followup.lead_id == lead.id, Followup.status == FollowupStatus.PENDING))).scalar()
        lead.next_followup_at = nxt
    await commit_and_deliver(db)
    return (await _followups_out(db, [f]))[0]

