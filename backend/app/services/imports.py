"""CSV / Excel lead import with header aliases, validation and duplicate detection."""

import csv
import io
import uuid

import sqlalchemy as sa
from openpyxl import load_workbook
from pydantic import ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.crypto import email_hash, normalize_email, phone_hash
from app.core.errors import bad_request
from app.models import Lead, LeadAssignment, User
from app.models.enums import LeadStatus, NotificationType, Priority
from app.schemas.leads import LeadBase
from app.services.leads import _validate_assignee, add_activity
from app.services.notifications import notify

ALIASES = {
    "full_name": {"full_name", "name", "full name", "lead name", "contact name"},
    "company_name": {"company_name", "company", "company name", "organisation", "organization"},
    "phone": {"phone", "mobile", "phone_number", "phone number", "mobile number", "contact number"},
    "alternate_phone": {"alternate_phone", "alternate phone", "alt phone", "landline"},
    "email": {"email", "email address", "e-mail"},
    "designation": {"designation", "title", "job title", "position"},
    "industry": {"industry", "sector", "vertical"},
    "location": {"location", "city", "state", "region"},
    "source": {"source", "lead_source", "lead source"},
    "priority": {"priority"},
    "remarks": {"remarks", "notes", "comments"},
}
_LOOKUP = {alias: field for field, aliases in ALIASES.items() for alias in aliases}
TEMPLATE_HEADERS = list(ALIASES.keys())


def template_csv() -> str:
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(TEMPLATE_HEADERS)
    w.writerow(["Asha Verma", "Example Schools Pvt Ltd", "+919800000001", "", "asha@example.com", "Principal",
                "Education", "New Delhi", "Website", "high", "Interested in eGov summit"])
    return buf.getvalue()


def _rows_from_file(filename: str, content: bytes) -> list[dict[str, str]]:
    name = (filename or "").lower()
    if name.endswith(".xlsx"):
        wb = load_workbook(io.BytesIO(content), read_only=True, data_only=True)
        ws = wb.active
        it = ws.iter_rows(values_only=True)
        try:
            header = [str(h or "").strip() for h in next(it)]
        except StopIteration:
            return []
        rows = []
        for values in it:
            if values is None or all(v in (None, "") for v in values):
                continue
            rows.append({header[i]: ("" if v is None else str(v)).strip() for i, v in enumerate(values) if i < len(header)})
        return rows
    if name.endswith(".csv") or name.endswith(".txt") or not name:
        try:
            text = content.decode("utf-8-sig")
        except UnicodeDecodeError:
            text = content.decode("latin-1")
        return [{(k or "").strip(): (v or "").strip() for k, v in r.items()} for r in csv.DictReader(io.StringIO(text))]
    raise bad_request("Upload a .csv or .xlsx file", code="validation_error")


def _map_row(raw: dict[str, str]) -> dict[str, str]:
    out: dict[str, str] = {}
    for key, value in raw.items():
        field = _LOOKUP.get(key.strip().lower())
        if field and value and field not in out:
            out[field] = value
    if "priority" in out:
        p = out["priority"].lower()
        out["priority"] = p if p in {e.value for e in Priority} else "medium"
    if "phone" in out and out["phone"].endswith(".0"):  # Excel numeric cells
        out["phone"] = out["phone"][:-2]
    return out


async def import_leads(
    db: AsyncSession, actor: User, filename: str, content: bytes, *,
    assignee_id: uuid.UUID | None = None, source: str | None = None,
) -> dict:
    if len(content) > settings.MAX_UPLOAD_BYTES:
        raise bad_request("File is too large (max 5 MB)", code="validation_error")
    raw_rows = _rows_from_file(filename, content)
    if len(raw_rows) > settings.MAX_IMPORT_ROWS:
        raise bad_request(f"Too many rows (max {settings.MAX_IMPORT_ROWS})", code="validation_error")
    assignee = await _validate_assignee(db, actor, assignee_id) if assignee_id else None

    parsed: list[tuple[int, LeadBase]] = []
    errors: list[dict] = []
    for idx, raw in enumerate(raw_rows, start=2):  # row 1 is the header
        mapped = _map_row(raw)
        if not mapped.get("full_name") or not mapped.get("phone"):
            errors.append({"row": idx, "error": "full_name and phone are required"})
            continue
        try:
            parsed.append((idx, LeadBase(**mapped)))
        except ValidationError as exc:
            errors.append({"row": idx, "error": exc.errors()[0]["msg"]})

    phone_hashes = {phone_hash(p.phone) for _, p in parsed}
    email_hashes = {email_hash(p.email) for _, p in parsed if p.email}
    existing_phones: dict[str, uuid.UUID] = {}
    existing_emails: dict[str, uuid.UUID] = {}
    ph_list = list(phone_hashes)
    for i in range(0, len(ph_list), 500):
        chunk = ph_list[i:i + 500]
        rows = await db.execute(
            sa.select(Lead.id, Lead.phone_hash, Lead.alternate_phone_hash).where(
                Lead.deleted_at.is_(None), sa.or_(Lead.phone_hash.in_(chunk), Lead.alternate_phone_hash.in_(chunk))
            )
        )
        for lid, a, b in rows:
            existing_phones.update({x: lid for x in (a, b) if x})
    em_list = list(email_hashes)
    for i in range(0, len(em_list), 500):
        rows = await db.execute(
            sa.select(Lead.id, Lead.email_hash).where(Lead.deleted_at.is_(None), Lead.email_hash.in_(em_list[i:i + 500]))
        )
        existing_emails.update({eh_: lid for lid, eh_ in rows if eh_})

    created: list[Lead] = []
    duplicate_ids: list[uuid.UUID] = []
    seen_phones: set[str] = set()
    seen_emails: set[str] = set()
    duplicates = 0
    for _row, p in parsed:
        ph, eh = phone_hash(p.phone), email_hash(p.email)
        dup_id = existing_phones.get(ph) or (existing_emails.get(eh) if eh else None)
        if dup_id is not None or ph in seen_phones or (eh and eh in seen_emails):
            duplicates += 1
            if dup_id is not None:
                duplicate_ids.append(dup_id)
            continue
        seen_phones.add(ph)
        if eh:
            seen_emails.add(eh)
        lead = Lead(
            full_name=p.full_name, company_name=p.company_name, phone=p.phone, phone_hash=ph,
            alternate_phone=p.alternate_phone, alternate_phone_hash=phone_hash(p.alternate_phone),
            email=normalize_email(p.email), email_hash=eh, designation=p.designation, industry=p.industry,
            location=p.location, source=source or p.source or "import", priority=p.priority.value, remarks=p.remarks,
            assigned_to_id=assignee.id if assignee else (actor.id if actor.role_name == "executive" else None),
            status=LeadStatus.ASSIGNED if assignee else LeadStatus.NEW, created_by_id=actor.id,
        )
        db.add(lead)
        created.append(lead)
    await db.flush()
    for lead in created:
        await add_activity(db, lead.id, "imported", "Imported from file", filename, actor)
        if assignee:
            db.add(LeadAssignment(lead_id=lead.id, to_user_id=assignee.id, assigned_by_id=actor.id))
    if assignee and created and assignee.id != actor.id:
        await notify(db, [assignee.id], NotificationType.LEAD_ASSIGNED, f"{len(created)} new leads assigned",
                     f"Imported by {actor.full_name}", {"count": len(created)})
    return {
        "total_rows": len(raw_rows), "created": len(created), "duplicates": duplicates, "errors": errors[:500],
        "lead_ids": [lead.id for lead in created],
        # internal: existing leads matched by the file (used when importing into a campaign)
        "existing_lead_ids": list(dict.fromkeys(duplicate_ids)),
    }
