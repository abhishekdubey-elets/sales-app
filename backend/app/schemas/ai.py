import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

Language = Literal["en-IN", "hi-IN"]


class RetryRules(BaseModel):
    max_attempts: int = Field(default=3, ge=1, le=10)
    retry_delay_minutes: int = Field(default=120, ge=5, le=10080)
    retry_on: list[Literal["busy", "not_answered", "failed"]] = ["busy", "not_answered"]


class AIAgentCreate(BaseModel):
    name: str = Field(min_length=1, max_length=160)
    description: str | None = None
    personality: str | None = None
    language: Language = "en-IN"
    voice_id: str | None = None
    speaking_speed: float = Field(default=1.0, ge=0.5, le=2.0)
    system_prompt: str = Field(min_length=10)
    knowledge_base: str | None = None
    objectives: list[str] = []
    greeting: str | None = None
    max_call_duration_seconds: int = Field(default=300, ge=30, le=1800)
    retry_rules: RetryRules = RetryRules()
    handoff_conditions: list[str] = []
    recording_enabled: bool = True


class AIAgentUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=160)
    description: str | None = None
    personality: str | None = None
    language: Language | None = None
    voice_id: str | None = None
    speaking_speed: float | None = Field(default=None, ge=0.5, le=2.0)
    system_prompt: str | None = Field(default=None, min_length=10)
    knowledge_base: str | None = None
    objectives: list[str] | None = None
    greeting: str | None = None
    max_call_duration_seconds: int | None = Field(default=None, ge=30, le=1800)
    retry_rules: RetryRules | None = None
    handoff_conditions: list[str] | None = None
    recording_enabled: bool | None = None
    is_active: bool | None = None


class AIAgentOut(AIAgentCreate):
    id: uuid.UUID
    is_active: bool
    created_by_name: str | None
    created_at: datetime
    updated_at: datetime
    total_calls: int
    successful_conversations: int


class ChatTurn(BaseModel):
    role: Literal["user", "assistant"]
    text: str


class TestReplyIn(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    history: list[ChatTurn] = Field(default=[], max_length=40)


class TestReplyOut(BaseModel):
    reply: str
    actions: list[dict]


class AIDashboard(BaseModel):
    total_calls: int
    in_progress: int
    completed: int
    successful_conversations: int
    qualified: int
    interested: int
    followups_required: int
    avg_duration_seconds: float
    handoffs: int


class AICallOut(BaseModel):
    id: uuid.UUID
    agent_id: uuid.UUID
    agent_name: str
    campaign_id: uuid.UUID | None
    campaign_name: str | None
    lead_id: uuid.UUID | None
    lead_name: str | None
    phone_masked: str | None
    provider: str
    provider_call_id: str | None
    status: str
    attempt: int
    started_at: datetime
    answered_at: datetime | None
    ended_at: datetime | None
    duration_seconds: int
    interest_level: str | None
    qualification_score: int | None
    handoff_requested: bool
    summary: str | None
    failure_reason: str | None
    created_at: datetime


class TranscriptSegment(BaseModel):
    speaker: Literal["agent", "customer", "system"]
    text: str
    offset_ms: int


class HandoffOut(BaseModel):
    reason: str
    notified_user_id: uuid.UUID | None
    notified_user_name: str | None
    transferred: bool
    at: datetime


class CallIntelligence(BaseModel):
    """Structured output requested from the LLM after every AI call."""

    summary: str = Field(description="3-5 sentence factual summary of the conversation")
    customer_requirements: list[str] = Field(description="Concrete needs the prospect expressed")
    interest_level: Literal["high", "medium", "low"]
    budget_information: str | None = Field(description="Budget discussed, or null if not discussed")
    decision_maker_information: str | None = Field(
        description="Who decides / whether the speaker is the decision maker, or null if unknown"
    )
    next_action: str = Field(description="The single most useful next step for the sales team")
    followup_recommendation: str | None = Field(description="When and how to follow up, or null")
    followup_date: str | None = Field(description="ISO date (YYYY-MM-DD) agreed for follow-up, or null")
    qualification_score: int = Field(description="0-100 lead qualification score")
    sentiment: Literal["positive", "neutral", "negative"]
    lead_status_suggestion: Literal[
        "contacted", "interested", "follow_up", "meeting_scheduled", "converted", "lost"
    ]

    @field_validator("qualification_score")
    @classmethod
    def _clamp(cls, v: int) -> int:
        return max(0, min(100, v))


class AICallDetail(AICallOut):
    intelligence: CallIntelligence | None
    transcript: list[TranscriptSegment]
    recording_id: uuid.UUID | None
    handoff: HandoffOut | None


class StartAICallIn(BaseModel):
    agent_id: uuid.UUID
    lead_id: uuid.UUID


class CampaignSchedule(BaseModel):
    timezone: str = "Asia/Kolkata"
    days_of_week: list[int] = Field(default=[1, 2, 3, 4, 5], min_length=1)
    start_time: str = Field(default="10:00", pattern=r"^([01]\d|2[0-3]):[0-5]\d$")
    end_time: str = Field(default="18:00", pattern=r"^([01]\d|2[0-3]):[0-5]\d$")
    start_date: date | None = None
    end_date: date | None = None

    @field_validator("days_of_week")
    @classmethod
    def _days(cls, v: list[int]) -> list[int]:
        if any(d < 1 or d > 7 for d in v):
            raise ValueError("days_of_week values must be 1 (Mon) … 7 (Sun)")
        return sorted(set(v))

    @model_validator(mode="after")
    def _times(self) -> "CampaignSchedule":
        if self.start_time >= self.end_time:
            raise ValueError("start_time must be before end_time")
        if self.start_date and self.end_date and self.end_date < self.start_date:
            raise ValueError("end_date must be on or after start_date")
        try:
            from zoneinfo import ZoneInfo

            ZoneInfo(self.timezone)
        except Exception as exc:  # noqa: BLE001
            raise ValueError("Unknown timezone") from exc
        return self


class CampaignCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    description: str | None = None
    agent_id: uuid.UUID
    schedule: CampaignSchedule = CampaignSchedule()
    max_attempts: int = Field(default=3, ge=1, le=10)
    retry_delay_minutes: int = Field(default=120, ge=5, le=10080)
    max_concurrent_calls: int = Field(default=2, ge=1, le=50)
    calls_per_minute: int = Field(default=5, ge=1, le=120)


class CampaignUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    agent_id: uuid.UUID | None = None
    schedule: CampaignSchedule | None = None
    max_attempts: int | None = Field(default=None, ge=1, le=10)
    retry_delay_minutes: int | None = Field(default=None, ge=5, le=10080)
    max_concurrent_calls: int | None = Field(default=None, ge=1, le=50)
    calls_per_minute: int | None = Field(default=None, ge=1, le=120)


class CampaignStats(BaseModel):
    total_leads: int = 0
    pending: int = 0
    in_progress: int = 0
    attempted: int = 0
    connected: int = 0
    not_answered: int = 0
    failed: int = 0
    interested: int = 0
    qualified: int = 0
    followups: int = 0
    conversions: int = 0
    handoffs: int = 0
    opted_out: int = 0


class CampaignOut(CampaignCreate):
    id: uuid.UUID
    agent_name: str
    status: str
    created_at: datetime
    started_at: datetime | None
    completed_at: datetime | None
    stats: CampaignStats


class LeadFilter(BaseModel):
    status: str | None = None
    source: str | None = None
    industry: str | None = None
    assigned_to: uuid.UUID | None = None


class CampaignLeadsIn(BaseModel):
    lead_ids: list[uuid.UUID] | None = Field(default=None, max_length=10000)
    filter: LeadFilter | None = None

    @model_validator(mode="after")
    def _one(self) -> "CampaignLeadsIn":
        if not self.lead_ids and self.filter is None:
            raise ValueError("Provide lead_ids or filter")
        return self


class CampaignLeadsOut(BaseModel):
    added: int
    skipped: int


class CampaignLeadOut(BaseModel):
    id: uuid.UUID
    lead_id: uuid.UUID
    lead_name: str | None
    company_name: str | None
    status: str
    attempts: int
    next_attempt_at: datetime | None
    last_call_status: str | None
    outcome: str | None
    interest_level: str | None
    last_ai_call_id: uuid.UUID | None


class CampaignLogOut(BaseModel):
    id: uuid.UUID
    level: str
    event: str
    message: str
    lead_id: uuid.UUID | None
    ai_call_id: uuid.UUID | None
    created_at: datetime
