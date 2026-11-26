"""Human (salesperson) calling: start, status webhooks, hang-up, disposition, inbound routing."""

import logging
import uuid

import sqlalchemy as sa
from fastapi import Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.crypto import normalize_phone, phone_hash
from app.core.database import utcnow
from app.core.errors import AppError, forbidden
from app.models import CallNote, CallRecording, Followup, HumanCall, Lead, OrgSettings, User
from app.models.enums import (
    ACTIVE_CALL_STATUSES,
    OUTCOME_TO_LEAD_STATUS,
    CallDirection,
    CallOutcome,
    CallStatus,
    FollowupSource,
    LeadStatus,
    NotificationType,
)
from app.realtime.hub import hub
from app.schemas.calls import DispositionIn
from app.services import call_locks, compliance
from app.services.call_state import apply_update
from app.services.leads import add_activity
from app.services.notifications import commit_and_deliver, notify
from app.services.org import get_org_settings, supervisors_of
from app.services.scoping import get_visible_lead, is_supervisor, scope_leads, sees_full_numbers
from app.services.serializers import human_call_out, human_calls_out
from app.telephony.base import StatusUpdate, TelephonyError, TelephonyNotSupported, build_callbacks
from app.telephony.registry import get_provider

log = logging.getLogger(__name__)


async def publish_call(db: AsyncSession, call: HumanCall, event: str = "call.status") -> None:
    """Send the call to the salesperson (masked per settings), their manager and admins (full)."""
    org = await get_org_settings(db)
    recipients = await supervisors_of(db, call.salesperson_id)
    owner_full = not org.mask_numbers_for_executives
    [full] = await human_calls_out(db, [call], True)
    masked = dict(full)
    if not owner_full:
        masked = (await human_calls_out(db, [call], False))[0]
    others = recipients - {call.salesperson_id}
    await hub.publish([call.salesperson_id], event, masked)
    if others:
        await hub.publish(others, event, full)


async def start_human_call(
    db: AsyncSession, user: User, *, lead_id: uuid.UUID | None, phone_number: str | None
) -> HumanCall:
    org = await get_org_settings(db)
    lead: Lead | None = None
    if lead_id:
        lead = await get_visible_lead(db, user, lead_id)
        number = lead.phone
    else:
        number = normalize_phone(phone_number)
        if not number:
            raise AppError(422, "validation_error", "Enter a valid phone number")
        ph = phone_hash(number)
        lead = (await db.execute(
            scope_leads(sa.select(Lead).where(sa.or_(Lead.phone_hash == ph, Lead.alternate_phone_hash == ph)), user)
            .limit(1)
        )).scalars().first()
    ph = phone_hash(number)

    if not user.calling_number:
        raise AppError(422, "calling_number_required",
                       "Add your calling number in Profile — the provider rings it first, then connects the lead")

    await compliance.ensure_callable(db, org, phone_e164=number, phone_hash=ph, lead=lead, kind="human")

    provider = get_provider()
    call_id = uuid.uuid4()
    if lead:
        await call_locks.acquire_lock(db, lead.id, "human", call_id)
    call = HumanCall(
        id=call_id,
        direction=CallDirection.OUTBOUND, lead_id=lead.id if lead else None, lead_name=lead.full_name if lead else None,
        phone_number=number, phone_hash=ph, salesperson_id=user.id, salesperson_name=user.full_name,
        team_id=user.team_id, provider=provider.name if provider else "none", status=CallStatus.INITIATED,
        started_at=utcnow(),
    )
    db.add(call)
    await db.flush()

    if provider is None or not provider.is_configured():
        await _fail(db, call, "Telephony provider is not configured")
        raise AppError(503, "telephony_not_configured",
                       "Calling is not available: no telephony provider is configured", call_id=str(call.id))

    await db.commit()  # the row must exist before the provider's first webhook arrives
    callbacks = build_callbacks(provider.name, "human", call.id)
    try:
        placed = await provider.place_bridge_call(
            agent_number=normalize_phone(user.calling_number) or user.calling_number, customer_number=number,
            caller_id=settings.TELEPHONY_CALLER_ID, callbacks=callbacks, record=org.recording_enabled,
            time_limit_seconds=settings.CALL_TIME_LIMIT_SECONDS,
        )
    except TelephonyError as exc:
        log.warning("bridge call failed: %s", exc)
        await _fail(db, call, str(exc)[:500])
        raise AppError(502, "telephony_error", f"The telephony provider did not place the call: {exc}",
                       call_id=str(call.id)) from exc

    call.provider_call_id = placed.provider_call_id
    if lead:
        lead.last_called_at = utcnow()
    await db.commit()
    await publish_call(db, call)
    return call


async def _fail(db: AsyncSession, call: HumanCall, reason: str) -> None:
    call.status = CallStatus.FAILED
    call.failure_reason = reason
    call.ended_at = utcnow()
    await call_locks.release_lock(db, call.lead_id, call.id)
    await db.commit()
    await publish_call(db, call)


async def apply_human_status(db: AsyncSession, call: HumanCall, upd: StatusUpdate) -> None:
    if upd.provider_call_id and not call.provider_call_id:
        call.provider_call_id = upd.provider_call_id
    now = utcnow()
    t = apply_update(call, upd, now, bridge=call.direction == CallDirection.OUTBOUND)
    if upd.recording_url:
        await attach_recording(db, call, upd.recording_url, upd.recording_id, None)
    if t.became_terminal:
        await _on_terminal(db, call)
    await commit_and_deliver(db)  # delivers e.g. the missed-call notification
    if t.changed:
        await publish_call(db, call)


async def _on_terminal(db: AsyncSession, call: HumanCall) -> None:
    org = await get_org_settings(db)
    await call_locks.release_lock(db, call.lead_id, call.id)
    compliance.consume_credits(org, call.talk_seconds or 0)
    if call.lead_id:
        lead = await db.get(Lead, call.lead_id)
        if lead:
            lead.last_called_at = call.ended_at
            if call.answered_at and lead.status in (LeadStatus.NEW, LeadStatus.ASSIGNED):
                lead.status = LeadStatus.CONTACTED
    if call.direction == CallDirection.INBOUND and call.status != CallStatus.COMPLETED:
        await notify(db, [call.salesperson_id], NotificationType.INCOMING_CALL, "Missed call",
                     f"{call.lead_name or 'Unknown caller'} called and was not connected",
                     {"call_id": str(call.id), "lead_id": str(call.lead_id) if call.lead_id else ""})


async def attach_recording(db: AsyncSession, call: HumanCall, url: str, rec_id: str | None, duration: int | None):
    exists = (await db.execute(
        sa.select(CallRecording.id).where(CallRecording.human_call_id == call.id)
    )).scalar_one_or_none()
    if exists is None:
        db.add(CallRecording(human_call_id=call.id, provider=call.provider, provider_recording_id=rec_id, url=url,
                             duration_seconds=duration))


async def hangup(db: AsyncSession, user: User, call: HumanCall) -> HumanCall:
    if call.salesperson_id != user.id and not is_supervisor(user):
        raise forbidden()
    if call.status not in ACTIVE_CALL_STATUSES:
        return call
    provider = get_provider(call.provider)
    if provider is None or not call.provider_call_id:
        raise AppError(409, "not_active", "This call has no active provider session")
    try:
        await provider.hangup(call.provider_call_id)
    except TelephonyNotSupported as exc:
        raise AppError(501, "not_supported", f"{exc}. End the call from your phone.") from exc
    except TelephonyError as exc:
        raise AppError(502, "telephony_error", str(exc)) from exc
    return call  # final status arrives through the provider's webhook


async def save_disposition(db: AsyncSession, user: User, call: HumanCall, data: DispositionIn) -> HumanCall:
    if call.salesperson_id != user.id and not is_supervisor(user):
        raise forbidden("Only the salesperson who made the call can record its outcome")
    call.outcome = data.outcome.value
    call.disposition_at = utcnow()
    call.followup_at = data.followup_at
    if data.notes:
        db.add(CallNote(human_call_id=call.id, author_id=user.id, author_name=user.full_name, body=data.notes))
    if call.lead_id:
        lead = await db.get(Lead, call.lead_id)
        if lead:
            new_status = data.lead_status or OUTCOME_TO_LEAD_STATUS.get(data.outcome)
            if data.followup_at and data.outcome not in (CallOutcome.CONVERTED, CallOutcome.MEETING_SCHEDULED) \
                    and data.lead_status is None:
                new_status = LeadStatus.FOLLOW_UP
            if new_status and new_status != lead.status:
                await add_activity(db, lead.id, "status_changed",
                                   f"Status changed to {new_status.value.replace('_', ' ')}",
                                   f"Call outcome: {data.outcome.value.replace('_', ' ')}", user, call.id)
                lead.status = new_status.value
            if data.notes:
                await add_activity(db, lead.id, "note", "Call note", data.notes, user, call.id)
            if data.followup_at:
                db.add(Followup(lead_id=lead.id, assigned_to_id=lead.assigned_to_id or user.id,
                                due_at=data.followup_at, note=data.notes, source=FollowupSource.HUMAN_CALL,
                                human_call_id=call.id, created_by_id=user.id))
                lead.next_followup_at = data.followup_at
    await db.commit()
    await publish_call(db, call)
    return call


async def handle_inbound(db: AsyncSession, provider_name: str, params: dict) -> Response:
    provider = get_provider(provider_name)
    if provider is None:
        raise AppError(404, "not_found", "Unknown provider")
    caller, provider_call_id = provider.inbound_caller(params)
    number = normalize_phone(caller)
    org = await get_org_settings(db)
    if not number:
        return provider.inbound_response(None, None, settings.TELEPHONY_CALLER_ID, False)
    ph = phone_hash(number)
    lead = (await db.execute(
        sa.select(Lead).where(Lead.deleted_at.is_(None), sa.or_(Lead.phone_hash == ph, Lead.alternate_phone_hash == ph))
        .limit(1)
    )).scalars().first()
    agent: User | None = None
    if lead and lead.assigned_to_id:
        agent = await db.get(User, lead.assigned_to_id)
    if agent is None or not agent.is_active or not agent.calling_number:
        # Nobody to route to: record a missed inbound call against the lead owner if we know one.
        if agent is not None:
            db.add(HumanCall(direction=CallDirection.INBOUND, lead_id=lead.id if lead else None,
                             lead_name=lead.full_name if lead else None, phone_number=number, phone_hash=ph,
                             salesperson_id=agent.id, salesperson_name=agent.full_name, team_id=agent.team_id,
                             provider=provider.name, provider_call_id=provider_call_id,
                             status=CallStatus.NOT_ANSWERED, ended_at=utcnow(),
                             failure_reason="Salesperson has no calling number"))
            await notify(db, [agent.id], NotificationType.INCOMING_CALL, "Missed call",
                         f"{lead.full_name if lead else number} called", {"lead_id": str(lead.id) if lead else ""})
            await db.commit()
        return provider.inbound_response(None, None, settings.TELEPHONY_CALLER_ID, False)

    call = HumanCall(direction=CallDirection.INBOUND, lead_id=lead.id, lead_name=lead.full_name, phone_number=number,
                     phone_hash=ph, salesperson_id=agent.id, salesperson_name=agent.full_name, team_id=agent.team_id,
                     provider=provider.name, provider_call_id=provider_call_id, status=CallStatus.RINGING)
    db.add(call)
    await db.commit()
    await publish_call(db, call, "call.incoming")
    callbacks = build_callbacks(provider.name, "human", call.id)
    return provider.inbound_response(normalize_phone(agent.calling_number), callbacks, settings.TELEPHONY_CALLER_ID,
                                     org.recording_enabled)


async def calls_out_for(db: AsyncSession, viewer: User, calls: list[HumanCall], org: OrgSettings,
                        with_notes: bool = False) -> list[dict]:
    return await human_calls_out(db, calls, sees_full_numbers(viewer, org), with_notes)


def call_out_for(viewer: User, call: HumanCall, org: OrgSettings) -> dict:
    return human_call_out(call, sees_full_numbers(viewer, org))
