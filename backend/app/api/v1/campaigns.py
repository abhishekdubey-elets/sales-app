import uuid

import sqlalchemy as sa
from fastapi import APIRouter, Depends, File, Query, Request, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import as_utc, get_db
from app.core.deps import require
from app.core.permissions import P
from app.models import AICampaign, AICampaignLead, CampaignLog, User
from app.schemas.ai import (
    CampaignCreate,
    CampaignLeadOut,
    CampaignLeadsIn,
    CampaignLeadsOut,
    CampaignLogOut,
    CampaignOut,
    CampaignUpdate,
)
from app.schemas.common import Page
from app.schemas.leads import ImportResult
from app.services import campaigns as svc
from app.services.audit import audit
from app.services.imports import import_leads
from app.services.notifications import commit_and_deliver

router = APIRouter(prefix="/ai/campaigns", tags=["campaigns"])


@router.get("", response_model=list[CampaignOut])
async def list_campaigns(status: str | None = None, user: User = Depends(require(P.CAMPAIGNS_VIEW)),
                         db: AsyncSession = Depends(get_db)):
    stmt = sa.select(AICampaign).order_by(AICampaign.created_at.desc())
    if status:
        stmt = stmt.where(AICampaign.status.in_(status.split(",")))
    return [await svc.campaign_out(db, c) for c in (await db.execute(stmt)).scalars().unique()]


@router.post("", response_model=CampaignOut, status_code=201)
async def create_campaign(body: CampaignCreate, request: Request, user: User = Depends(require(P.CAMPAIGNS_MANAGE)),
                          db: AsyncSession = Depends(get_db)):
    c = await svc.create_campaign(db, user, body)
    await audit(db, user, "campaign.created", "ai_campaign", c.id, {"name": c.name}, request)
    await db.commit()
    return await svc.campaign_out(db, c)


@router.get("/{campaign_id}", response_model=CampaignOut)
async def get_campaign(campaign_id: uuid.UUID, user: User = Depends(require(P.CAMPAIGNS_VIEW)),
                       db: AsyncSession = Depends(get_db)):
    return await svc.campaign_out(db, await svc.get_campaign(db, campaign_id))


@router.patch("/{campaign_id}", response_model=CampaignOut)
async def update_campaign(campaign_id: uuid.UUID, body: CampaignUpdate, user: User = Depends(require(P.CAMPAIGNS_MANAGE)),
                          db: AsyncSession = Depends(get_db)):
    c = await svc.update_campaign(db, await svc.get_campaign(db, campaign_id), body)
    await db.commit()
    return await svc.campaign_out(db, c)


@router.post("/{campaign_id}/leads", response_model=CampaignLeadsOut)
async def add_leads(campaign_id: uuid.UUID, body: CampaignLeadsIn, user: User = Depends(require(P.CAMPAIGNS_MANAGE)),
                    db: AsyncSession = Depends(get_db)):
    c = await svc.get_campaign(db, campaign_id)
    result = await svc.add_leads(db, c, body.lead_ids, body.filter)
    await db.commit()
    return result


@router.post("/{campaign_id}/leads/import", response_model=ImportResult)
async def import_campaign_leads(campaign_id: uuid.UUID, request: Request, file: UploadFile = File(...),
                                user: User = Depends(require(P.CAMPAIGNS_MANAGE)), db: AsyncSession = Depends(get_db)):
    c = await svc.get_campaign(db, campaign_id)
    result = await import_leads(db, user, file.filename or "", await file.read(), source=f"campaign:{c.name}"[:120])
    await svc.add_leads(db, c, result["lead_ids"] + result.get("existing_lead_ids", []), None)
    await audit(db, user, "campaign.leads_imported", "ai_campaign", c.id,
                {"file": file.filename, "created": result["created"], "duplicates": result["duplicates"]}, request)
    await commit_and_deliver(db)
    return result


@router.get("/{campaign_id}/leads", response_model=Page[CampaignLeadOut])
async def campaign_leads(campaign_id: uuid.UUID, status: str | None = None, page: int = Query(1, ge=1),
                         page_size: int = Query(20, ge=1, le=100), user: User = Depends(require(P.CAMPAIGNS_VIEW)),
                         db: AsyncSession = Depends(get_db)):
    stmt = sa.select(AICampaignLead).where(AICampaignLead.campaign_id == campaign_id)
    if status:
        stmt = stmt.where(AICampaignLead.status.in_(status.split(",")))
    total = (await db.execute(sa.select(sa.func.count()).select_from(stmt.subquery()))).scalar_one()
    rows = (await db.execute(stmt.order_by(AICampaignLead.created_at).offset((page - 1) * page_size)
                             .limit(page_size))).scalars().all()
    return {"items": await svc.campaign_leads_out(db, list(rows)), "total": total, "page": page,
            "page_size": page_size}


@router.get("/{campaign_id}/logs", response_model=Page[CampaignLogOut])
async def campaign_logs(campaign_id: uuid.UUID, page: int = Query(1, ge=1), page_size: int = Query(50, ge=1, le=100),
                        user: User = Depends(require(P.CAMPAIGNS_VIEW)), db: AsyncSession = Depends(get_db)):
    stmt = sa.select(CampaignLog).where(CampaignLog.campaign_id == campaign_id)
    total = (await db.execute(sa.select(sa.func.count()).select_from(stmt.subquery()))).scalar_one()
    rows = (await db.execute(stmt.order_by(CampaignLog.created_at.desc()).offset((page - 1) * page_size)
                             .limit(page_size))).scalars().all()
    return {"items": [{"id": r.id, "level": r.level, "event": r.event, "message": r.message, "lead_id": r.lead_id,
                       "ai_call_id": r.ai_call_id, "created_at": as_utc(r.created_at)} for r in rows],
            "total": total, "page": page, "page_size": page_size}


async def _transition(action: str, campaign_id: uuid.UUID, request: Request, user: User, db: AsyncSession) -> dict:
    c = await svc.transition(db, user, await svc.get_campaign(db, campaign_id), action)
    await audit(db, user, f"campaign.{action}", "ai_campaign", c.id, {"name": c.name}, request)
    await db.commit()
    await svc.publish_progress(db, c)
    return await svc.campaign_out(db, c)


@router.post("/{campaign_id}/start", response_model=CampaignOut)
async def start(campaign_id: uuid.UUID, request: Request, user: User = Depends(require(P.CAMPAIGNS_MANAGE)),
                db: AsyncSession = Depends(get_db)):
    return await _transition("start", campaign_id, request, user, db)


@router.post("/{campaign_id}/pause", response_model=CampaignOut)
async def pause(campaign_id: uuid.UUID, request: Request, user: User = Depends(require(P.CAMPAIGNS_MANAGE)),
                db: AsyncSession = Depends(get_db)):
    return await _transition("pause", campaign_id, request, user, db)


@router.post("/{campaign_id}/resume", response_model=CampaignOut)
async def resume(campaign_id: uuid.UUID, request: Request, user: User = Depends(require(P.CAMPAIGNS_MANAGE)),
                 db: AsyncSession = Depends(get_db)):
    return await _transition("resume", campaign_id, request, user, db)


@router.post("/{campaign_id}/stop", response_model=CampaignOut)
async def stop(campaign_id: uuid.UUID, request: Request, user: User = Depends(require(P.CAMPAIGNS_MANAGE)),
               db: AsyncSession = Depends(get_db)):
    return await _transition("stop", campaign_id, request, user, db)
