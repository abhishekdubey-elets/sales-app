"""AI-agent calls: placement, provider status, handoffs, transcripts and post-call intelligence."""

import logging
import uuid
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import SessionLocal, as_utc, utcnow
from app.core.errors import AppError
from app.models import (
    AIAgent,
    AICall,
    AICampaign,
    AICampaignLead,
    AIHandoff,
    CallRecording,
    CallTranscript,
    CampaignLog,
    Followup,
    Lead,
    User,
)
from app.models.enums import (
    AnalysisStatus,
    CallStatus,
    CampaignLeadStatus,
    FollowupSource,
    InterestLevel,
    LeadStatus,
    NotificationType,
)
from app.realtime.hub import hub
from app.services import call_locks, compliance
from app.services.call_state import apply_update
from app.services.leads import add_activity
from app.services.notifications import commit_and_deliver, notify
from app.services.org import get_org_settings, managers_and_admins, team_manager_id
from app.services.serializers import ai_call_out
from app.telephony.base import StatusUpdate, TelephonyError, build_callbacks
from app.telephony.registry import get_provider
from app.voice.llm.base import LLMError
from app.voice.prompts import ANALYSIS_SYSTEM_PROMPT, analysis_input
from app.voice.registry import get_llm, voice_ready

log = logging.getLogger(__name__)

# Lead statuses an AI suggestion may move a lead *from* (never downgrade converted/meeting/lost by hand).
_AI_MAY_UPDATE_FROM = {LeadStatus.NEW, LeadStatus.ASSIGNED, LeadStatus.CONTACTED, LeadStatus.INTERESTED,
                       LeadStatus.FOLLOW_UP}


async def campaign_log(db: AsyncSession, campaign_id, event: str, message: str, level: str = "info",
                       lead_id=None, ai_call_id=None) -> None:
    if campaign_id:
        db.add(CampaignLog(campaign_id=campaign_id, level=level, event=event, message=message, lead_id=lead_id,
                           ai_call_id=ai_call_id))


async def publish_ai_call(db: AsyncSession, call: AICall) -> None:
    await hub.publish(await managers_and_admins(db), "ai_call.status", ai_call_out(call))


async def start_ai_call(
    db: AsyncSession, agent: AIAgent, lead: Lead, *, campaign: AICampaign | None = None,
    campaign_lead: AICampaignLead | None = None, initiated_by: User | None = None,
) -> AICall:
    """Create the AI call row and ask the provider to dial. Raises AppError when the call cannot be placed."""
    org = await get_org_settings(db)
    if not agent.is_active:
        raise AppError(409, "agent_inactive", "This AI agent is archived")
    provider = get_provider()
    if provider is None or not provider.is_configured():
        raise AppError(503, "telephony_not_configured", "No telephony provider is configured")
    if not provider.supports_ai_streaming:
        raise AppError(503, "telephony_not_supported", f"{provider.name} does not support AI voice calls")
    ok, why = voice_ready()
    if not ok:
        raise AppError(503, "voice_not_configured", f"AI voice is not ready: {why}")
    await compliance.ensure_callable(db, org, phone_e164=lead.phone, phone_hash=lead.phone_hash, lead=lead, kind="ai")

    attempt = (campaign_lead.attempts + 1) if campaign_lead else 1
    # Lock first: if the lead is busy nothing has been added to the session (the runner keeps going).
    call_id = uuid.uuid4()
    await call_locks.acquire_lock(db, lead.id, "ai", call_id)
    call = AICall(
        id=call_id, agent_id=agent.id, campaign_id=campaign.id if campaign else None,
        campaign_lead_id=campaign_lead.id if campaign_lead else None, lead_id=lead.id, lead_name=lead.full_name,
        phone_number=lead.phone, phone_hash=lead.phone_hash, initiated_by_id=initiated_by.id if initiated_by else None,
        provider=provider.name, status=CallStatus.INITIATED, attempt=attempt, language=agent.language,
        started_at=utcnow(),
    )
    db.add(call)
    await db.flush()
    if campaign_lead:
        campaign_lead.status = CampaignLeadStatus.IN_PROGRESS
        campaign_lead.attempts = attempt
        campaign_lead.last_ai_call_id = call.id
        campaign_lead.next_attempt_at = None
    await db.commit()

    record = org.recording_enabled and agent.recording_enabled
    try:
        placed = await provider.place_ai_call(
            customer_number=lead.phone, caller_id=settings.TELEPHONY_CALLER_ID,
            callbacks=build_callbacks(provider.name, "ai", call.id), record=record,
            time_limit_seconds=min(agent.max_call_duration_seconds + 60, settings.CALL_TIME_LIMIT_SECONDS),
        )
    except TelephonyError as exc:
        call.status = CallStatus.FAILED
        call.failure_reason = str(exc)[:500]
        call.ended_at = utcnow()
        call.analysis_status = AnalysisStatus.SKIPPED
        await call_locks.release_lock(db, lead.id, call.id)
        if campaign_lead:
            await _after_attempt(db, call, campaign_lead, campaign)
        await campaign_log(db, call.campaign_id, "call_failed", f"Provider rejected call to {lead.full_name}: {exc}",
                           "error", lead.id, call.id)
        await db.commit()
        await publish_ai_call(db, call)
        raise AppError(502, "telephony_error", f"The telephony provider did not place the call: {exc}",
                       call_id=str(call.id)) from exc

    call.provider_call_id = placed.provider_call_id
    lead.last_called_at = utcnow()
    await campaign_log(db, call.campaign_id, "call_placed", f"Calling {lead.full_name} (attempt {attempt})",
                       lead_id=lead.id, ai_call_id=call.id)
    await db.commit()
    await publish_ai_call(db, call)
    return call


async def apply_ai_status(db: AsyncSession, call: AICall, upd: StatusUpdate) -> None:
    if upd.provider_call_id and upd.provider_call_id != call.provider_call_id and call.provider == "plivo":
        call.provider_call_id = upd.provider_call_id  # Plivo: request_uuid → CallUUID
    t = apply_update(call, upd, utcnow(), bridge=False)
    if upd.recording_url:
        await attach_ai_recording(db, call, upd.recording_url, upd.recording_id, None)
    if t.became_terminal:
        await _on_terminal(db, call)
    await commit_and_deliver(db)
    if t.changed:
        await publish_ai_call(db, call)


async def mark_connected(db: AsyncSession, call: AICall) -> None:
    """The provider opened the media stream, which only happens on an answered call."""
    if call.status in (CallStatus.INITIATED, CallStatus.RINGING):
        call.status = CallStatus.CONNECTED
        call.answered_at = call.answered_at or utcnow()
        await db.commit()
        await publish_ai_call(db, call)


async def _on_terminal(db: AsyncSession, call: AICall) -> None:
    org = await get_org_settings(db)
    await call_locks.release_lock(db, call.lead_id, call.id)
    compliance.consume_credits(org, call.duration_seconds if call.answered_at else 0)
    if call.answered_at is None:
        call.analysis_status = AnalysisStatus.SKIPPED
    if call.campaign_lead_id:
        cl = await db.get(AICampaignLead, call.campaign_lead_id)
        campaign = await db.get(AICampaign, call.campaign_id) if call.campaign_id else None
        if cl:
            await _after_attempt(db, call, cl, campaign)
    # Low-credit alerts are raised once per day by the daily job (workers/jobs.py) to avoid spam.


async def _after_attempt(db: AsyncSession, call: AICall, cl: AICampaignLead, campaign: AICampaign | None) -> None:
    cl.last_call_status = call.status
    if call.answered_at is not None:
        cl.status = CampaignLeadStatus.COMPLETED
        await campaign_log(db, call.campaign_id, "call_completed",
                           f"Conversation with {call.lead_name} ended ({call.duration_seconds}s)",
                           lead_id=call.lead_id, ai_call_id=call.id)
        return
    agent = call.agent or await db.get(AIAgent, call.agent_id)
    retry_on = set((agent.retry_rules or {}).get("retry_on", ["busy", "not_answered"]))
    max_attempts = campaign.max_attempts if campaign else 1
    delay = campaign.retry_delay_minutes if campaign else 60
    if call.status in retry_on and cl.attempts < max_attempts:
        cl.status = CampaignLeadStatus.PENDING
        cl.next_attempt_at = utcnow() + timedelta(minutes=delay)
        await campaign_log(db, call.campaign_id, "retry_scheduled",
                           f"{call.lead_name}: {call.status.replace('_', ' ')} — retry {cl.attempts + 1}/{max_attempts} "
                           f"in {delay} min", lead_id=call.lead_id, ai_call_id=call.id)
    else:
        cl.status = CampaignLeadStatus.FAILED
        await campaign_log(db, call.campaign_id, "lead_exhausted",
                           f"{call.lead_name}: {call.status.replace('_', ' ')} after {cl.attempts} attempt(s)",
                           "warning", call.lead_id, call.id)


async def attach_ai_recording(db: AsyncSession, call: AICall, url: str, rec_id: str | None, duration: int | None):
    exists = (await db.execute(sa.select(CallRecording.id).where(CallRecording.ai_call_id == call.id))).scalar()
    if exists is None:
        db.add(CallRecording(ai_call_id=call.id, provider=call.provider, provider_recording_id=rec_id, url=url,
                             duration_seconds=duration))


async def salesperson_for_lead(db: AsyncSession, lead: Lead | None) -> User | None:
    if lead and lead.assigned_to_id:
        user = await db.get(User, lead.assigned_to_id)
        if user and user.is_active:
            return user
    return None


async def record_handoff(db: AsyncSession, call: AICall, reason: str, transferred: bool) -> User | None:
    lead = await db.get(Lead, call.lead_id) if call.lead_id else None
    salesperson = await salesperson_for_lead(db, lead)
    call.handoff_requested = True
    db.add(AIHandoff(ai_call_id=call.id, lead_id=call.lead_id, reason=reason, transferred=transferred,
                     notified_user_id=salesperson.id if salesperson else None))
    recipients = [salesperson.id] if salesperson else await managers_and_admins(db)
    if lead:
        await add_activity(db, lead.id, "handoff", "AI agent: prospect asked for a salesperson", reason, None, call.id)
        if lead.status in _AI_MAY_UPDATE_FROM:
            lead.status = LeadStatus.FOLLOW_UP
        db.add(Followup(lead_id=lead.id, assigned_to_id=salesperson.id if salesperson else None, due_at=utcnow(),
                        note=f"Human hand-off requested on AI call: {reason}", source=FollowupSource.AI_CALL,
                        ai_call_id=call.id))
        lead.next_followup_at = utcnow()
    await notify(db, recipients, NotificationType.HANDOFF_REQUEST,
                 "Prospect wants to talk to you" if salesperson else "Unassigned prospect wants a salesperson",
                 f"{call.lead_name or 'A prospect'}: {reason}",
                 {"ai_call_id": str(call.id), "lead_id": str(call.lead_id) if call.lead_id else ""})
    await campaign_log(db, call.campaign_id, "handoff", f"{call.lead_name} asked for a human: {reason}",
                       lead_id=call.lead_id, ai_call_id=call.id)
    return salesperson


async def record_meeting_request(db: AsyncSession, call: AICall, preferred_time: str, iso: str | None,
                                 notes: str) -> str:
    org = await get_org_settings(db)
    lead = await db.get(Lead, call.lead_id) if call.lead_id else None
    if lead is None:
        return "Noted. The sales team will reach out to confirm."
    salesperson = await salesperson_for_lead(db, lead)
    tz = ZoneInfo(org.timezone)
    due: datetime | None = None
    if iso:
        try:
            parsed = datetime.fromisoformat(iso)
            due = parsed if parsed.tzinfo else parsed.replace(tzinfo=tz)
        except ValueError:
            due = None
    if due is None:
        tomorrow = (utcnow().astimezone(tz) + timedelta(days=1)).date()
        due = datetime.combine(tomorrow, time(11, 0), tzinfo=tz)
    db.add(Followup(lead_id=lead.id, assigned_to_id=salesperson.id if salesperson else None, due_at=due,
                    note=f"Meeting requested on AI call ({preferred_time}). {notes}".strip(),
                    source=FollowupSource.AI_CALL, ai_call_id=call.id))
    lead.next_followup_at = due
    if lead.status in _AI_MAY_UPDATE_FROM:
        lead.status = LeadStatus.MEETING_SCHEDULED
    await add_activity(db, lead.id, "followup", "AI agent: meeting requested", f"{preferred_time}. {notes}", None,
                       call.id)
    await notify(db, [salesperson.id] if salesperson else await managers_and_admins(db),
                 NotificationType.AI_QUALIFIED_LEAD, "Meeting requested by prospect",
                 f"{lead.full_name}: {preferred_time}", {"ai_call_id": str(call.id), "lead_id": str(lead.id)})
    who = salesperson.full_name.split()[0] if salesperson else "our sales team"
    return f"Meeting request saved for {preferred_time}. {who} will confirm the exact time."


async def save_transcript(db: AsyncSession, call: AICall, segments: list[dict]) -> None:
    text = "\n".join(f"{'Agent' if s['speaker'] == 'agent' else 'Prospect' if s['speaker'] == 'customer' else 'System'}:"
                     f" {s['text']}" for s in segments)
    existing = (await db.execute(sa.select(CallTranscript).where(CallTranscript.ai_call_id == call.id))).scalar()
    if existing:
        existing.segments, existing.full_text = segments, text
    else:
        db.add(CallTranscript(ai_call_id=call.id, language=call.language, segments=segments, full_text=text))


async def run_analysis(ai_call_id: uuid.UUID) -> None:
    """Generate call intelligence and propagate it to the lead, campaign and sales team."""
    async with SessionLocal() as db:
        call = await db.get(AICall, ai_call_id)
        if call is None or call.analysis_status in (AnalysisStatus.DONE, AnalysisStatus.RUNNING):
            return
        transcript = (await db.execute(sa.select(CallTranscript).where(CallTranscript.ai_call_id == call.id))).scalar()
        customer_spoke = transcript and any(s.get("speaker") == "customer" for s in transcript.segments)
        if not customer_spoke:
            call.analysis_status = AnalysisStatus.SKIPPED
            call.summary = call.summary or "No conversation took place."
            await db.commit()
            return
        llm = get_llm()
        if llm is None or not llm.is_configured():
            call.analysis_status = AnalysisStatus.FAILED
            await db.commit()
            return
        call.analysis_status = AnalysisStatus.RUNNING
        await db.commit()
        agent = await db.get(AIAgent, call.agent_id)
        lead = await db.get(Lead, call.lead_id) if call.lead_id else None
        try:
            intel = await llm.analyze_call(
                ANALYSIS_SYSTEM_PROMPT,
                analysis_input(agent, lead, transcript.full_text, as_utc(call.started_at).date().isoformat()),
            )
        except LLMError as exc:
            log.warning("analysis failed for %s: %s", call.id, exc)
            call.analysis_status = AnalysisStatus.FAILED
            await db.commit()
            return
        await apply_intelligence(db, call, lead, intel)
        await commit_and_deliver(db)
        await publish_ai_call(db, call)


async def apply_intelligence(db: AsyncSession, call: AICall, lead: Lead | None, intel) -> None:
    org = await get_org_settings(db)
    call.intelligence = intel.model_dump()
    call.summary = intel.summary
    call.interest_level = intel.interest_level
    call.qualification_score = intel.qualification_score
    call.analysis_status = AnalysisStatus.DONE
    if call.campaign_lead_id:
        cl = await db.get(AICampaignLead, call.campaign_lead_id)
        if cl:
            cl.outcome = intel.lead_status_suggestion
            cl.interest_level = intel.interest_level
    if lead is None:
        return
    if lead.status in _AI_MAY_UPDATE_FROM and intel.lead_status_suggestion != lead.status:
        lead.status = intel.lead_status_suggestion
        await add_activity(db, lead.id, "status_changed",
                           f"AI call: status set to {intel.lead_status_suggestion.replace('_', ' ')}",
                           intel.summary, None, call.id)
    salesperson = await salesperson_for_lead(db, lead)
    wants_followup = intel.interest_level in (InterestLevel.HIGH, InterestLevel.MEDIUM) or intel.followup_date
    if wants_followup and not call.handoff_requested:
        tz = ZoneInfo(org.timezone)
        try:
            day = date.fromisoformat(intel.followup_date) if intel.followup_date else None
        except ValueError:
            day = None
        day = day or (utcnow().astimezone(tz) + timedelta(days=1)).date()
        due = datetime.combine(day, time(11, 0), tzinfo=tz)
        db.add(Followup(lead_id=lead.id, assigned_to_id=salesperson.id if salesperson else None, due_at=due,
                        note=intel.followup_recommendation or intel.next_action, source=FollowupSource.AI_CALL,
                        ai_call_id=call.id))
        lead.next_followup_at = due
    qualified = intel.interest_level == InterestLevel.HIGH or intel.qualification_score >= 70
    if qualified:
        if salesperson:
            recipients = {salesperson.id}
            manager = await team_manager_id(db, salesperson.team_id)
            if manager:
                recipients.add(manager)
        else:
            recipients = set(await managers_and_admins(db))
        await notify(db, recipients, NotificationType.AI_QUALIFIED_LEAD, "AI-qualified lead",
                     f"{lead.full_name} · score {intel.qualification_score} · {intel.next_action}",
                     {"ai_call_id": str(call.id), "lead_id": str(lead.id)})
