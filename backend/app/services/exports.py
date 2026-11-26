"""CSV / Excel exports of role-scoped reports."""

import csv
import io
from datetime import datetime
from zoneinfo import ZoneInfo

import sqlalchemy as sa
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.crypto import mask_phone
from app.core.database import as_utc
from app.models import AICall, HumanCall, Lead, User, unified_calls_view
from app.services import analytics
from app.services.scoping import scope_ai_calls, scope_human_calls, scope_leads

MAX_EXPORT_ROWS = 100_000


def _fmt(dt: datetime | None, tz: ZoneInfo) -> str:
    return as_utc(dt).astimezone(tz).strftime("%Y-%m-%d %H:%M:%S") if dt else ""


async def build_rows(db: AsyncSession, user: User, report: str, start: datetime, end: datetime,
                     tz_name: str, full_numbers: bool) -> tuple[list[str], list[list]]:
    tz = ZoneInfo(tz_name)
    phone = (lambda p: p) if full_numbers else mask_phone
    if report == "calls":
        rows = (await db.execute(scope_human_calls(
            sa.select(HumanCall).where(HumanCall.started_at >= start, HumanCall.started_at < end)
            .order_by(HumanCall.started_at.desc()).limit(MAX_EXPORT_ROWS), user))).scalars().all()
        header = ["Call ID", "Direction", "Lead ID", "Lead name", "Phone", "Salesperson ID", "Salesperson",
                  "Provider", "Provider call ID", "Status", "Started", "Answered", "Ended", "Duration (s)",
                  "Talk (s)", "Outcome", "Follow-up", "Failure reason"]
        return header, [[str(c.id), c.direction, str(c.lead_id or ""), c.lead_name or "", phone(c.phone_number),
                         str(c.salesperson_id), c.salesperson_name, c.provider, c.provider_call_id or "", c.status,
                         _fmt(c.started_at, tz), _fmt(c.answered_at, tz), _fmt(c.ended_at, tz), c.duration_seconds,
                         c.talk_seconds, c.outcome or "", _fmt(c.followup_at, tz), c.failure_reason or ""]
                        for c in rows]
    if report == "ai_calls":
        rows = (await db.execute(scope_ai_calls(
            sa.select(AICall).where(AICall.started_at >= start, AICall.started_at < end)
            .order_by(AICall.started_at.desc()).limit(MAX_EXPORT_ROWS), user))).scalars().unique().all()
        header = ["AI call ID", "Agent ID", "Agent", "Campaign ID", "Campaign", "Lead ID", "Lead name", "Phone",
                  "Status", "Attempt", "Started", "Answered", "Ended", "Duration (s)", "Interest", "Score",
                  "Hand-off", "Summary"]
        return header, [[str(c.id), str(c.agent_id), c.agent.name if c.agent else "", str(c.campaign_id or ""),
                         c.campaign.name if c.campaign else "", str(c.lead_id or ""), c.lead_name or "",
                         phone(c.phone_number), c.status, c.attempt, _fmt(c.started_at, tz), _fmt(c.answered_at, tz),
                         _fmt(c.ended_at, tz), c.duration_seconds, c.interest_level or "",
                         c.qualification_score if c.qualification_score is not None else "",
                         "yes" if c.handoff_requested else "no", c.summary or ""] for c in rows]
    if report == "leads":
        rows = (await db.execute(scope_leads(sa.select(Lead), user).order_by(Lead.created_at.desc())
                                 .limit(MAX_EXPORT_ROWS))).scalars().unique().all()
        header = ["Lead ID", "Full name", "Company", "Phone", "Email", "Designation", "Industry", "Location",
                  "Source", "Assigned to", "Status", "Priority", "Last called", "Next follow-up", "Opted out",
                  "Created"]
        return header, [[str(x.id), x.full_name, x.company_name or "", phone(x.phone), x.email or "",
                         x.designation or "", x.industry or "", x.location or "", x.source or "",
                         x.assigned_to.full_name if x.assigned_to else "", x.status, x.priority,
                         _fmt(x.last_called_at, tz), _fmt(x.next_followup_at, tz), "yes" if x.opted_out else "no",
                         _fmt(x.created_at, tz)] for x in rows]
    if report == "leaderboard":
        rows = await analytics.leaderboard(db, user, start, end)
        header = ["Salesperson", "Team", "Calls", "Connected", "Talk time (s)", "Conversions"]
        return header, [[r["name"], r["team_name"] or "", r["calls"], r["connected"], r["duration_seconds"],
                         r["conversions"]] for r in rows]
    if report == "unified":
        if user.role_name != "admin":
            return await build_rows(db, user, "calls", start, end, tz_name, full_numbers)
        v = unified_calls_view
        rows = (await db.execute(sa.select(v).where(v.c.started_at >= start, v.c.started_at < end)
                                 .order_by(v.c.started_at.desc()).limit(MAX_EXPORT_ROWS))).all()
        header = ["ID", "Origin", "Direction", "Lead ID", "Lead", "Salesperson ID", "Salesperson", "AI agent ID",
                  "Campaign ID", "Provider", "Status", "Started", "Ended", "Duration (s)", "Outcome", "Interest"]
        return header, [[str(r.id), r.origin, r.direction, str(r.lead_id or ""), r.lead_name or "",
                         str(r.salesperson_id or ""), r.salesperson_name or "", str(r.ai_agent_id or ""),
                         str(r.campaign_id or ""), r.provider, r.status, _fmt(r.started_at, tz), _fmt(r.ended_at, tz),
                         r.duration_seconds, r.outcome or "", r.interest_level or ""] for r in rows]
    raise ValueError(report)


def to_csv(header: list[str], rows: list[list]) -> bytes:
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(header)
    w.writerows(rows)
    return ("﻿" + buf.getvalue()).encode("utf-8")  # BOM so Excel opens UTF-8 (Hindi names) correctly


def to_xlsx(header: list[str], rows: list[list], title: str) -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = title[:31]
    ws.append(header)
    for cell in ws[1]:
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor="0B1B3F")
    for r in rows:
        ws.append(r)
    ws.freeze_panes = "A2"
    for col in ws.columns:
        width = max(len(str(c.value or "")) for c in list(col)[:200])
        ws.column_dimensions[col[0].column_letter].width = min(max(10, width + 2), 60)
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()
