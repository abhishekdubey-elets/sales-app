import uuid

import sqlalchemy as sa
from fastapi import APIRouter, Depends, File, Form, Query, Request, Response, UploadFile
from fastapi.responses import PlainTextResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.crypto import normalize_phone, phone_hash
from app.core.database import as_utc, get_db
from app.core.deps import get_current_user, require
from app.core.errors import AppError, not_found
from app.core.permissions import P
from app.models import AIAgent, AICampaign, Lead, User, unified_calls_view
from app.schemas.common import Page
from app.schemas.leads import (
    AssignIn,
    AssignOut,
    DuplicateCheckIn,
    DuplicateCheckOut,
    ImportResult,
    LeadCreate,
    LeadOut,
    LeadUpdate,
    OptOutIn,
    TimelineItem,
    UnifiedCallOut,
)
from app.services import compliance
from app.services import leads as svc
from app.services.audit import audit
from app.services.imports import import_leads, template_csv
from app.services.notifications import commit_and_deliver
from app.services.org import get_org_settings
from app.services.scoping import get_visible_lead, scope_leads, sees_full_numbers
from app.services.serializers import leads_out

router = APIRouter(prefix="/leads", tags=["leads"])


async def _one(db: AsyncSession, user: User, lead: Lead) -> dict:
    org = await get_org_settings(db)
    [out] = await leads_out(db, [lead], user, sees_full_numbers(user, org))
    return out


@router.get("", response_model=Page[LeadOut])
async def list_leads(
    q: str | None = None, status: str | None = None, priority: str | None = None, assigned_to: str | None = None,
    source: str | None = None, industry: str | None = None, favourites: bool = False, followup_due: bool = False,
    sort: str = "-created_at", page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100),
    user: User = Depends(require(P.LEADS_VIEW)), db: AsyncSession = Depends(get_db),
):
    items, total = await svc.list_leads(db, user, q=q, status=status, priority=priority, assigned_to=assigned_to,
                                        source=source, industry=industry, favourites=favourites,
                                        followup_due=followup_due, sort=sort, page=page, page_size=page_size)
    org = await get_org_settings(db)
    return {"items": await leads_out(db, items, user, sees_full_numbers(user, org)), "total": total, "page": page,
            "page_size": page_size}


@router.post("", response_model=LeadOut, status_code=201)
async def create_lead(body: LeadCreate, user: User = Depends(require(P.LEADS_CREATE)), db: AsyncSession = Depends(get_db)):
    lead = await svc.create_lead(db, user, body)
    await commit_and_deliver(db)
    return await _one(db, user, lead)


@router.post("/check-duplicate", response_model=DuplicateCheckOut)
async def check_duplicate(body: DuplicateCheckIn, user: User = Depends(require(P.LEADS_VIEW)),
                          db: AsyncSession = Depends(get_db)):
    lead, matched = await svc.find_duplicate(db, body.phone, body.email)
    return {"duplicate": lead is not None, "lead_id": lead.id if lead else None, "matched_on": matched}


@router.get("/lookup", response_model=LeadOut)
async def lookup(phone: str, user: User = Depends(require(P.LEADS_VIEW)), db: AsyncSession = Depends(get_db)):
    if not normalize_phone(phone):
        raise AppError(422, "validation_error", "Enter a valid phone number")
    ph = phone_hash(phone)
    lead = (await db.execute(scope_leads(
        sa.select(Lead).where(sa.or_(Lead.phone_hash == ph, Lead.alternate_phone_hash == ph)), user).limit(1)
    )).scalars().first()
    if lead is None:
        raise not_found("Lead")
    return await _one(db, user, lead)


@router.get("/import/template", response_class=PlainTextResponse)
async def import_template(user: User = Depends(require(P.LEADS_IMPORT))):
    return PlainTextResponse(template_csv(), media_type="text/csv",
                             headers={"Content-Disposition": 'attachment; filename="leads_template.csv"'})


@router.post("/import", response_model=ImportResult)
async def import_file(
    request: Request, file: UploadFile = File(...), assignee_id: uuid.UUID | None = Form(None),
    source: str | None = Form(None), user: User = Depends(require(P.LEADS_IMPORT)), db: AsyncSession = Depends(get_db),
):
    content = await file.read()
    result = await import_leads(db, user, file.filename or "", content, assignee_id=assignee_id, source=source)
    await audit(db, user, "leads.imported", "lead", None,
                {"file": file.filename, "created": result["created"], "duplicates": result["duplicates"]}, request)
    await commit_and_deliver(db)
    return result


@router.post("/assign", response_model=AssignOut)
async def assign(body: AssignIn, request: Request, user: User = Depends(require(P.LEADS_ASSIGN)),
                 db: AsyncSession = Depends(get_db)):
    n = await svc.assign_leads(db, user, body.lead_ids, body.assignee_id)
    await audit(db, user, "leads.assigned", "lead", None,
                {"count": n, "assignee_id": str(body.assignee_id)}, request)
    await commit_and_deliver(db)
    return {"assigned": n}


@router.get("/{lead_id}", response_model=LeadOut)
async def get_lead(lead_id: uuid.UUID, user: User = Depends(require(P.LEADS_VIEW)), db: AsyncSession = Depends(get_db)):
    return await _one(db, user, await get_visible_lead(db, user, lead_id))


@router.patch("/{lead_id}", response_model=LeadOut)
async def update_lead(lead_id: uuid.UUID, body: LeadUpdate, user: User = Depends(require(P.LEADS_EDIT)),
                      db: AsyncSession = Depends(get_db)):
    lead = await get_visible_lead(db, user, lead_id)
    lead = await svc.update_lead(db, user, lead, body)
    await commit_and_deliver(db)
    return await _one(db, user, lead)


@router.delete("/{lead_id}", status_code=204)
async def delete_lead(lead_id: uuid.UUID, request: Request, user: User = Depends(require(P.LEADS_DELETE)),
                      db: AsyncSession = Depends(get_db)):
    lead = await get_visible_lead(db, user, lead_id)
    await svc.soft_delete(db, user, lead)
    await audit(db, user, "lead.deleted", "lead", lead.id, {"name": lead.full_name}, request)
    await db.commit()
    return Response(status_code=204)


@router.get("/{lead_id}/timeline", response_model=list[TimelineItem])
async def timeline(lead_id: uuid.UUID, user: User = Depends(require(P.LEADS_VIEW)), db: AsyncSession = Depends(get_db)):
    return await svc.timeline(db, await get_visible_lead(db, user, lead_id))


@router.get("/{lead_id}/calls", response_model=list[UnifiedCallOut])
async def lead_calls(lead_id: uuid.UUID, user: User = Depends(require(P.LEADS_VIEW)), db: AsyncSession = Depends(get_db)):
    lead = await get_visible_lead(db, user, lead_id)
    v = unified_calls_view
    rows = (await db.execute(sa.select(v).where(v.c.lead_id == lead.id).order_by(v.c.started_at.desc()))).all()
    agent_ids = {r.ai_agent_id for r in rows if r.ai_agent_id}
    campaign_ids = {r.campaign_id for r in rows if r.campaign_id}
    agent_names = dict((await db.execute(sa.select(AIAgent.id, AIAgent.name).where(AIAgent.id.in_(agent_ids)))).all()) \
        if agent_ids else {}
    campaign_names = dict((await db.execute(
        sa.select(AICampaign.id, AICampaign.name).where(AICampaign.id.in_(campaign_ids))
    )).all()) if campaign_ids else {}
    out = []
    for r in rows:
        d = dict(r._mapping)
        for k in ("started_at", "answered_at", "ended_at"):
            d[k] = as_utc(d[k])
        d["duration_seconds"] = d["duration_seconds"] or 0
        d["agent_name"] = agent_names.get(r.ai_agent_id)
        d["campaign_name"] = campaign_names.get(r.campaign_id)
        out.append(d)
    return out


@router.post("/{lead_id}/favourite", status_code=204)
async def favourite(lead_id: uuid.UUID, user: User = Depends(require(P.LEADS_VIEW)), db: AsyncSession = Depends(get_db)):
    await svc.set_favourite(db, user, await get_visible_lead(db, user, lead_id), True)
    await db.commit()
    return Response(status_code=204)


@router.delete("/{lead_id}/favourite", status_code=204)
async def unfavourite(lead_id: uuid.UUID, user: User = Depends(require(P.LEADS_VIEW)),
                      db: AsyncSession = Depends(get_db)):
    await svc.set_favourite(db, user, await get_visible_lead(db, user, lead_id), False)
    await db.commit()
    return Response(status_code=204)


@router.post("/{lead_id}/opt-out", response_model=LeadOut)
async def opt_out(lead_id: uuid.UUID, body: OptOutIn, request: Request, user: User = Depends(get_current_user),
                  db: AsyncSession = Depends(get_db)):
    lead = await get_visible_lead(db, user, lead_id)
    await compliance.record_opt_out(db, phone_hash=lead.phone_hash, reason=body.reason, source="lead_request",
                                    lead_id=lead.id, user_id=user.id)
    if lead.alternate_phone_hash:
        await compliance.record_opt_out(db, phone_hash=lead.alternate_phone_hash, reason=body.reason,
                                        source="lead_request", lead_id=lead.id, user_id=user.id)
    await svc.add_activity(db, lead.id, "opt_out", "Opted out of calls", body.reason, user)
    await audit(db, user, "lead.opted_out", "lead", lead.id, {"reason": body.reason}, request)
    await db.commit()
    await db.refresh(lead)
    return await _one(db, user, lead)
