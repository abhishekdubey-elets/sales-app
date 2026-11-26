import uuid
from datetime import datetime

from pydantic import BaseModel, Field, model_validator

from app.models.enums import CallDirection, CallOutcome, CallStatus, LeadStatus


class CallNoteOut(BaseModel):
    id: uuid.UUID
    body: str
    author_id: uuid.UUID | None
    author_name: str | None
    created_at: datetime


class HumanCallOut(BaseModel):
    id: uuid.UUID
    direction: CallDirection
    lead_id: uuid.UUID | None
    lead_name: str | None
    phone_number: str
    salesperson_id: uuid.UUID
    salesperson_name: str
    provider: str
    provider_call_id: str | None
    status: CallStatus
    started_at: datetime
    answered_at: datetime | None
    ended_at: datetime | None
    duration_seconds: int
    talk_seconds: int
    recording_id: uuid.UUID | None
    outcome: CallOutcome | None
    followup_at: datetime | None
    failure_reason: str | None
    notes: list[CallNoteOut] = []
    created_at: datetime


class StartCallIn(BaseModel):
    lead_id: uuid.UUID | None = None
    phone_number: str | None = None

    @model_validator(mode="after")
    def _one(self) -> "StartCallIn":
        if not self.lead_id and not self.phone_number:
            raise ValueError("Provide lead_id or phone_number")
        return self


class DispositionIn(BaseModel):
    outcome: CallOutcome
    notes: str | None = Field(default=None, max_length=5000)
    followup_at: datetime | None = None
    lead_status: LeadStatus | None = None


class NoteIn(BaseModel):
    body: str = Field(min_length=1, max_length=5000)


class FollowupOut(BaseModel):
    id: uuid.UUID
    lead_id: uuid.UUID
    lead_name: str | None
    assigned_to_id: uuid.UUID | None
    assigned_to_name: str | None
    due_at: datetime
    status: str
    note: str | None
    source: str
    created_at: datetime


class FollowupCreate(BaseModel):
    lead_id: uuid.UUID
    due_at: datetime
    note: str | None = Field(default=None, max_length=2000)
    assigned_to_id: uuid.UUID | None = None


class FollowupUpdate(BaseModel):
    status: str | None = Field(default=None, pattern="^(pending|done|cancelled)$")
    due_at: datetime | None = None
    note: str | None = Field(default=None, max_length=2000)
