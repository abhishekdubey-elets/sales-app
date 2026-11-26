import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class NotificationOut(BaseModel):
    id: uuid.UUID
    type: str
    title: str
    body: str
    data: dict
    read_at: datetime | None
    created_at: datetime


class OrgSettingsOut(BaseModel):
    timezone: str
    calling_hours_start: str
    calling_hours_end: str
    calling_days: list[int]
    recording_enabled: bool
    recording_disclosure_text: str
    ai_disclosure_text: str
    require_consent_for_ai_calls: bool
    mask_numbers_for_executives: bool
    calling_credits_minutes: int | None
    credits_used_minutes: int
    low_credit_threshold_minutes: int
    daily_summary_time: str


_HHMM = r"^([01]\d|2[0-3]):[0-5]\d$"


class OrgSettingsUpdate(BaseModel):
    timezone: str | None = None
    calling_hours_start: str | None = Field(default=None, pattern=_HHMM)
    calling_hours_end: str | None = Field(default=None, pattern=_HHMM)
    calling_days: list[int] | None = None
    recording_enabled: bool | None = None
    recording_disclosure_text: str | None = Field(default=None, min_length=5, max_length=500)
    ai_disclosure_text: str | None = Field(default=None, min_length=10, max_length=500)
    require_consent_for_ai_calls: bool | None = None
    mask_numbers_for_executives: bool | None = None
    calling_credits_minutes: int | None = Field(default=None, ge=0)
    low_credit_threshold_minutes: int | None = Field(default=None, ge=0)
    daily_summary_time: str | None = Field(default=None, pattern=_HHMM)
    reset_credits_used: bool = False


class TelephonyStatus(BaseModel):
    provider: str | None
    configured: bool
    call_mode: Literal["bridge", "voip"]
    supports_ai_streaming: bool
    supports_recording: bool
    supports_inbound: bool


class AuditLogOut(BaseModel):
    id: uuid.UUID
    actor_id: uuid.UUID | None
    actor_name: str | None
    action: str
    entity_type: str | None
    entity_id: str | None
    details: dict
    ip_address: str | None
    created_at: datetime


class DashboardStats(BaseModel):
    scope: Literal["personal", "team", "organization"]
    total_leads: int
    total_calls: int
    successful_calls: int
    missed_calls: int
    connected_calls: int
    not_connected: int
    total_duration_seconds: int
    pending_followups: int
    leads_converted: int
    ai_calls: int
    ai_successful_conversations: int


class LeaderboardRow(BaseModel):
    user_id: uuid.UUID
    name: str
    team_name: str | None
    calls: int
    connected: int
    duration_seconds: int
    conversions: int


class CallsByDate(BaseModel):
    date: str
    human: int
    ai: int
    human_connected: int
    ai_connected: int


class DepartmentRow(BaseModel):
    department: str
    calls: int
    connected: int
    duration_seconds: int
    conversions: int


class ChannelStats(BaseModel):
    calls: int
    connected: int
    avg_duration_seconds: float
    interested: int
    converted: int
    qualified: int


class HumanVsAI(BaseModel):
    human: ChannelStats
    ai: ChannelStats


class AgentPerformance(BaseModel):
    agent_id: uuid.UUID
    agent_name: str
    calls: int
    connected: int
    successful: int
    qualified: int
    avg_duration_seconds: float
    handoffs: int


class MyStats(BaseModel):
    calls_today: int
    calls_this_week: int
    calls_this_month: int
    connected: int
    missed: int
    avg_duration_seconds: float
    interested: int
    converted: int
    followups_pending: int


class ExportLinkIn(BaseModel):
    report: Literal["calls", "ai_calls", "leads", "leaderboard", "unified"]
    format: Literal["csv", "xlsx"] = "csv"
    range: str | None = "this_month"
    date_from: str | None = Field(default=None, alias="from")
    date_to: str | None = Field(default=None, alias="to")

    model_config = {"populate_by_name": True}
