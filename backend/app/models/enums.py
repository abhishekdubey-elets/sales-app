from enum import StrEnum

import sqlalchemy as sa


class LeadStatus(StrEnum):
    NEW = "new"
    ASSIGNED = "assigned"
    CONTACTED = "contacted"
    INTERESTED = "interested"
    FOLLOW_UP = "follow_up"
    MEETING_SCHEDULED = "meeting_scheduled"
    CONVERTED = "converted"
    LOST = "lost"


class Priority(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class ConsentStatus(StrEnum):
    UNKNOWN = "unknown"
    GRANTED = "granted"
    REVOKED = "revoked"


class CallDirection(StrEnum):
    OUTBOUND = "outbound"
    INBOUND = "inbound"


class CallStatus(StrEnum):
    INITIATED = "initiated"
    RINGING = "ringing"
    CONNECTED = "connected"
    COMPLETED = "completed"
    BUSY = "busy"
    NOT_ANSWERED = "not_answered"
    FAILED = "failed"
    REJECTED = "rejected"


ACTIVE_CALL_STATUSES = (CallStatus.INITIATED, CallStatus.RINGING, CallStatus.CONNECTED)
TERMINAL_CALL_STATUSES = (
    CallStatus.COMPLETED, CallStatus.BUSY, CallStatus.NOT_ANSWERED, CallStatus.FAILED, CallStatus.REJECTED,
)
NOT_CONNECTED_STATUSES = (CallStatus.BUSY, CallStatus.NOT_ANSWERED, CallStatus.FAILED, CallStatus.REJECTED)


class CallOutcome(StrEnum):
    INTERESTED = "interested"
    NOT_INTERESTED = "not_interested"
    FOLLOW_UP_REQUIRED = "follow_up_required"
    MEETING_SCHEDULED = "meeting_scheduled"
    CONVERTED = "converted"
    WRONG_NUMBER = "wrong_number"
    NO_RESPONSE = "no_response"


SUCCESSFUL_OUTCOMES = (
    CallOutcome.INTERESTED, CallOutcome.FOLLOW_UP_REQUIRED, CallOutcome.MEETING_SCHEDULED, CallOutcome.CONVERTED,
)

OUTCOME_TO_LEAD_STATUS = {
    CallOutcome.INTERESTED: LeadStatus.INTERESTED,
    CallOutcome.NOT_INTERESTED: LeadStatus.LOST,
    CallOutcome.FOLLOW_UP_REQUIRED: LeadStatus.FOLLOW_UP,
    CallOutcome.MEETING_SCHEDULED: LeadStatus.MEETING_SCHEDULED,
    CallOutcome.CONVERTED: LeadStatus.CONVERTED,
    CallOutcome.WRONG_NUMBER: LeadStatus.LOST,
    CallOutcome.NO_RESPONSE: LeadStatus.CONTACTED,
}


class InterestLevel(StrEnum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class CampaignStatus(StrEnum):
    DRAFT = "draft"
    RUNNING = "running"
    PAUSED = "paused"
    COMPLETED = "completed"
    STOPPED = "stopped"


class CampaignLeadStatus(StrEnum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"
    OPTED_OUT = "opted_out"


class FollowupStatus(StrEnum):
    PENDING = "pending"
    DONE = "done"
    CANCELLED = "cancelled"


class FollowupSource(StrEnum):
    HUMAN_CALL = "human_call"
    AI_CALL = "ai_call"
    MANUAL = "manual"


class NotificationType(StrEnum):
    LEAD_ASSIGNED = "lead_assigned"
    FOLLOWUP_REMINDER = "followup_reminder"
    AI_QUALIFIED_LEAD = "ai_qualified_lead"
    HANDOFF_REQUEST = "handoff_request"
    CAMPAIGN_COMPLETED = "campaign_completed"
    DAILY_SUMMARY = "daily_summary"
    INCOMING_CALL = "incoming_call"
    SYSTEM = "system"


class AnalysisStatus(StrEnum):
    PENDING = "pending"
    RUNNING = "running"
    DONE = "done"
    FAILED = "failed"
    SKIPPED = "skipped"


def enum_check(column: str, enum_cls: type[StrEnum], name: str | None = None) -> sa.CheckConstraint:
    values = ", ".join(f"'{e.value}'" for e in enum_cls)
    return sa.CheckConstraint(f"{column} IN ({values})", name=name or f"{column}_valid")
