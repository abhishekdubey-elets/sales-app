import uuid
from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.deps import require
from app.core.errors import AppError
from app.core.permissions import P
from app.core.security import create_purpose_token, decode_token
from app.core.timeranges import resolve_range
from app.models import User
from app.schemas.common import SignedUrl
from app.schemas.misc import (
    AgentPerformance,
    CallsByDate,
    DashboardStats,
    DepartmentRow,
    ExportLinkIn,
    HumanVsAI,
    LeaderboardRow,
    MyStats,
)
from app.services import analytics as svc
from app.services import exports
from app.services.audit import audit
from app.services.org import get_org_settings
from app.services.scoping import sees_full_numbers

router = APIRouter(prefix="/analytics", tags=["analytics"])


async def _range(db: AsyncSession, range_: str | None, f: date | None, t: date | None):
    org = await get_org_settings(db)
    return (*resolve_range(range_, f, t, org.timezone), org)


_From = Query(None, alias="from")
_To = Query(None, alias="to")


@router.get("/dashboard", response_model=DashboardStats)
async def dashboard(range: str | None = "today", date_from: date | None = _From, date_to: date | None = _To,
                    user: User = Depends(require(P.ANALYTICS_VIEW)), db: AsyncSession = Depends(get_db)):
    start, end, _ = await _range(db, range, date_from, date_to)
    return await svc.dashboard(db, user, start, end)


@router.get("/leaderboard", response_model=list[LeaderboardRow])
async def leaderboard(range: str | None = "today", date_from: date | None = _From, date_to: date | None = _To,
                      team_id: uuid.UUID | None = None, user: User = Depends(require(P.ANALYTICS_VIEW)),
                      db: AsyncSession = Depends(get_db)):
    start, end, _ = await _range(db, range, date_from, date_to)
    return await svc.leaderboard(db, user, start, end, team_id)


@router.get("/calls-by-salesperson", response_model=list[LeaderboardRow])
async def by_salesperson(range: str | None = "this_month", date_from: date | None = _From, date_to: date | None = _To,
                         team_id: uuid.UUID | None = None, user: User = Depends(require(P.ANALYTICS_TEAM)),
                         db: AsyncSession = Depends(get_db)):
    start, end, _ = await _range(db, range, date_from, date_to)
    return await svc.leaderboard(db, user, start, end, team_id)


@router.get("/calls-by-date", response_model=list[CallsByDate])
async def by_date(range: str | None = "this_month", date_from: date | None = _From, date_to: date | None = _To,
                  user: User = Depends(require(P.ANALYTICS_VIEW)), db: AsyncSession = Depends(get_db)):
    start, end, org = await _range(db, range, date_from, date_to)
    return await svc.calls_by_date(db, user, start, end, org.timezone)


@router.get("/calls-by-department", response_model=list[DepartmentRow])
async def by_department(range: str | None = "this_month", date_from: date | None = _From, date_to: date | None = _To,
                        user: User = Depends(require(P.ANALYTICS_TEAM)), db: AsyncSession = Depends(get_db)):
    start, end, _ = await _range(db, range, date_from, date_to)
    return await svc.calls_by_department(db, user, start, end)


@router.get("/human-vs-ai", response_model=HumanVsAI)
async def human_vs_ai(range: str | None = "this_month", date_from: date | None = _From, date_to: date | None = _To,
                      user: User = Depends(require(P.ANALYTICS_TEAM)), db: AsyncSession = Depends(get_db)):
    start, end, _ = await _range(db, range, date_from, date_to)
    return await svc.human_vs_ai(db, user, start, end)


@router.get("/agents", response_model=list[AgentPerformance])
async def agents(range: str | None = "this_month", date_from: date | None = _From, date_to: date | None = _To,
                 user: User = Depends(require(P.AI_CALLS_VIEW, P.ANALYTICS_TEAM)), db: AsyncSession = Depends(get_db)):
    start, end, _ = await _range(db, range, date_from, date_to)
    return await svc.agent_performance(db, user, start, end)


@router.get("/campaigns")
async def campaigns(user: User = Depends(require(P.CAMPAIGNS_VIEW)), db: AsyncSession = Depends(get_db)):
    return await svc.campaign_performance(db)


@router.get("/me", response_model=MyStats)
async def me(user: User = Depends(require(P.ANALYTICS_VIEW)), db: AsyncSession = Depends(get_db)):
    org = await get_org_settings(db)
    return await svc.my_stats(db, user, org.timezone)


async def _export(db: AsyncSession, user: User, report: str, fmt: str, range_: str | None,
                  f: date | None, t: date | None) -> Response:
    if report not in ("calls", "ai_calls", "leads", "leaderboard", "unified") or fmt not in ("csv", "xlsx"):
        raise AppError(422, "validation_error", "Unknown report or format")
    if report == "ai_calls" and P.AI_CALLS_VIEW.value not in user.permissions:
        raise AppError(403, "forbidden", "You cannot export AI calls")
    start, end, org = await _range(db, range_, f, t)
    header, rows = await exports.build_rows(db, user, report, start, end, org.timezone, sees_full_numbers(user, org))
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M")
    name = f"elets-{report}-{stamp}.{fmt}"
    if fmt == "csv":
        content, media = exports.to_csv(header, rows), "text/csv; charset=utf-8"
    else:
        content = exports.to_xlsx(header, rows, report)
        media = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    return Response(content, media_type=media, headers={"Content-Disposition": f'attachment; filename="{name}"',
                                                        "Cache-Control": "private, no-store"})


@router.get("/export")
async def export(request: Request, report: str, format: str = "csv", range: str | None = "this_month",
                 date_from: date | None = _From, date_to: date | None = _To,
                 user: User = Depends(require(P.ANALYTICS_EXPORT)), db: AsyncSession = Depends(get_db)):
    await audit(db, user, "report.exported", "report", report, {"format": format, "range": range}, request)
    await db.commit()
    return await _export(db, user, report, format, range, date_from, date_to)


@router.post("/export-link", response_model=SignedUrl)
async def export_link(body: ExportLinkIn, request: Request, user: User = Depends(require(P.ANALYTICS_EXPORT)),
                      db: AsyncSession = Depends(get_db)):
    ttl = settings.SIGNED_URL_TTL_SECONDS
    token = create_purpose_token("export", {"sub": str(user.id), "report": body.report, "format": body.format,
                                            "range": body.range, "from": body.date_from, "to": body.date_to}, ttl)
    await audit(db, user, "report.exported", "report", body.report, {"format": body.format, "range": body.range},
                request)
    await db.commit()
    exp = datetime.fromtimestamp(datetime.now(timezone.utc).timestamp() + ttl, tz=timezone.utc)
    return {"url": f"{settings.API_PUBLIC_BASE_URL}/api/v1/analytics/export/download?token={token}",
            "expires_at": exp.isoformat()}


@router.get("/export/download")
async def export_download(token: str, db: AsyncSession = Depends(get_db)):
    payload = decode_token(token, "export")
    if not payload:
        raise AppError(403, "forbidden", "Link expired or invalid")
    user = await db.get(User, uuid.UUID(payload["sub"]))
    if user is None or not user.is_active or P.ANALYTICS_EXPORT.value not in user.permissions:
        raise AppError(403, "forbidden", "Link expired or invalid")
    f = date.fromisoformat(payload["from"]) if payload.get("from") else None
    t = date.fromisoformat(payload["to"]) if payload.get("to") else None
    return await _export(db, user, payload["report"], payload["format"], payload.get("range"), f, t)
