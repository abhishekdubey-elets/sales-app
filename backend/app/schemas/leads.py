import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.core.crypto import normalize_phone
from app.models.enums import ConsentStatus, LeadStatus, Priority
from app.schemas.common import Email


class LeadBase(BaseModel):
    full_name: str = Field(min_length=1, max_length=160)
    company_name: str | None = Field(default=None, max_length=200)
    phone: str
    alternate_phone: str | None = None
    email: Email | None = None
    designation: str | None = Field(default=None, max_length=160)
    industry: str | None = Field(default=None, max_length=120)
    location: str | None = Field(default=None, max_length=160)
    source: str | None = Field(default=None, max_length=120)
    priority: Priority = Priority.MEDIUM
    remarks: str | None = None
    consent_status: ConsentStatus = ConsentStatus.UNKNOWN

    @field_validator("phone")
    @classmethod
    def _phone(cls, v: str) -> str:
        n = normalize_phone(v)
        if not n:
            raise ValueError("Enter a valid phone number")
        return n

    @field_validator("alternate_phone")
    @classmethod
    def _alt_phone(cls, v: str | None) -> str | None:
        if v in (None, ""):
            return None
        n = normalize_phone(v)
        if not n:
            raise ValueError("Enter a valid alternate phone number")
        return n

    @field_validator("email", mode="before")
    @classmethod
    def _empty_email(cls, v):
        return None if v == "" else v


class LeadCreate(LeadBase):
    assigned_to_id: uuid.UUID | None = None


class LeadUpdate(BaseModel):
    full_name: str | None = Field(default=None, min_length=1, max_length=160)
    company_name: str | None = None
    phone: str | None = None
    alternate_phone: str | None = None
    email: Email | None = None
    designation: str | None = None
    industry: str | None = None
    location: str | None = None
    source: str | None = None
    priority: Priority | None = None
    remarks: str | None = None
    consent_status: ConsentStatus | None = None
    status: LeadStatus | None = None
    assigned_to_id: uuid.UUID | None = None

    @field_validator("phone")
    @classmethod
    def _phone(cls, v: str | None) -> str | None:
        if v is None:
            return None
        n = normalize_phone(v)
        if not n:
            raise ValueError("Enter a valid phone number")
        return n

    @field_validator("alternate_phone")
    @classmethod
    def _alt(cls, v: str | None) -> str | None:
        if v in (None, ""):
            return None
        n = normalize_phone(v)
        if not n:
            raise ValueError("Enter a valid alternate phone number")
        return n

    @field_validator("email", mode="before")
    @classmethod
    def _empty_email(cls, v):
        return None if v == "" else v


class LeadOut(BaseModel):
    id: uuid.UUID
    full_name: str
    company_name: str | None
    phone: str
    phone_masked: str | None
    alternate_phone: str | None
    email: str | None
    designation: str | None
    industry: str | None
    location: str | None
    source: str | None
    assigned_to_id: uuid.UUID | None
    assigned_to_name: str | None
    status: LeadStatus
    priority: Priority
    last_called_at: datetime | None
    next_followup_at: datetime | None
    remarks: str | None
    consent_status: ConsentStatus
    opted_out: bool
    is_favourite: bool
    call_count: int
    created_at: datetime
    updated_at: datetime


class DuplicateCheckIn(BaseModel):
    phone: str | None = None
    email: str | None = None


class DuplicateCheckOut(BaseModel):
    duplicate: bool
    lead_id: uuid.UUID | None = None
    matched_on: Literal["phone", "email"] | None = None


class AssignIn(BaseModel):
    lead_ids: list[uuid.UUID] = Field(min_length=1, max_length=1000)
    assignee_id: uuid.UUID


class AssignOut(BaseModel):
    assigned: int


class OptOutIn(BaseModel):
    reason: str | None = Field(default=None, max_length=255)


class ImportError_(BaseModel):
    row: int
    error: str


class ImportResult(BaseModel):
    total_rows: int
    created: int
    duplicates: int
    errors: list[ImportError_]
    lead_ids: list[uuid.UUID]


class TimelineItem(BaseModel):
    id: uuid.UUID
    type: str
    at: datetime
    title: str
    description: str | None
    actor_name: str | None
    ref_id: uuid.UUID | None


class UnifiedCallOut(BaseModel):
    id: uuid.UUID
    origin: Literal["human", "ai"]
    direction: str
    lead_id: uuid.UUID | None
    lead_name: str | None
    salesperson_id: uuid.UUID | None
    salesperson_name: str | None
    ai_agent_id: uuid.UUID | None
    agent_name: str | None = None
    campaign_id: uuid.UUID | None
    campaign_name: str | None = None
    provider: str
    status: str
    started_at: datetime
    answered_at: datetime | None
    ended_at: datetime | None
    duration_seconds: int
    outcome: str | None
    interest_level: str | None
    summary: str | None
