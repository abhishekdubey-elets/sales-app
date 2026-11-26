import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.crypto import EncryptedString
from app.core.database import Base, Timestamps, UUIDPk, utcnow
from app.models.enums import AnalysisStatus, CallStatus, CampaignLeadStatus, CampaignStatus, enum_check


class AIAgent(UUIDPk, Timestamps, Base):
    __tablename__ = "ai_agents"

    name: Mapped[str] = mapped_column(sa.String(160), nullable=False)
    description: Mapped[str | None] = mapped_column(sa.Text)
    personality: Mapped[str | None] = mapped_column(sa.Text)
    language: Mapped[str] = mapped_column(sa.String(16), default="en-IN", nullable=False)
    voice_id: Mapped[str | None] = mapped_column(sa.String(120))
    speaking_speed: Mapped[float] = mapped_column(sa.Float, default=1.0, nullable=False)
    system_prompt: Mapped[str] = mapped_column(sa.Text, nullable=False)
    knowledge_base: Mapped[str | None] = mapped_column(sa.Text)
    objectives: Mapped[list[str]] = mapped_column(sa.JSON, default=list, nullable=False)
    greeting: Mapped[str | None] = mapped_column(sa.Text)
    max_call_duration_seconds: Mapped[int] = mapped_column(sa.Integer, default=300, nullable=False)
    retry_rules: Mapped[dict] = mapped_column(sa.JSON, default=dict, nullable=False)
    handoff_conditions: Mapped[list[str]] = mapped_column(sa.JSON, default=list, nullable=False)
    recording_enabled: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"))


class AICampaign(UUIDPk, Timestamps, Base):
    __tablename__ = "ai_campaigns"
    __table_args__ = (enum_check("status", CampaignStatus),)

    name: Mapped[str] = mapped_column(sa.String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(sa.Text)
    agent_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("ai_agents.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    status: Mapped[str] = mapped_column(sa.String(16), default=CampaignStatus.DRAFT, nullable=False, index=True)
    schedule: Mapped[dict] = mapped_column(sa.JSON, default=dict, nullable=False)
    max_attempts: Mapped[int] = mapped_column(sa.Integer, default=3, nullable=False)
    retry_delay_minutes: Mapped[int] = mapped_column(sa.Integer, default=120, nullable=False)
    max_concurrent_calls: Mapped[int] = mapped_column(sa.Integer, default=2, nullable=False)
    calls_per_minute: Mapped[int] = mapped_column(sa.Integer, default=5, nullable=False)
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"))
    started_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))

    agent: Mapped[AIAgent] = relationship(lazy="joined")


class AICampaignLead(UUIDPk, Timestamps, Base):
    __tablename__ = "ai_campaign_leads"
    __table_args__ = (
        sa.UniqueConstraint("campaign_id", "lead_id"),
        enum_check("status", CampaignLeadStatus),
        sa.Index("ix_campaign_leads_due", "campaign_id", "status", "next_attempt_at"),
    )

    campaign_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("ai_campaigns.id", ondelete="CASCADE"), nullable=False
    )
    lead_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("leads.id", ondelete="CASCADE"), nullable=False, index=True
    )
    status: Mapped[str] = mapped_column(sa.String(16), default=CampaignLeadStatus.PENDING, nullable=False)
    attempts: Mapped[int] = mapped_column(sa.Integer, default=0, nullable=False)
    next_attempt_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    last_call_status: Mapped[str | None] = mapped_column(sa.String(16))
    outcome: Mapped[str | None] = mapped_column(sa.String(32))
    interest_level: Mapped[str | None] = mapped_column(sa.String(16))
    last_ai_call_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid)


class AICall(UUIDPk, Timestamps, Base):
    """A call placed by an AI agent. Always traceable to `agent_id` (and `campaign_id` for campaign calls)."""

    __tablename__ = "ai_calls"
    __table_args__ = (
        enum_check("status", CallStatus),
        enum_check("analysis_status", AnalysisStatus),
        sa.Index("ix_ai_calls_agent_started", "agent_id", "started_at"),
        sa.Index("ix_ai_calls_provider_call", "provider", "provider_call_id"),
    )

    agent_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("ai_agents.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    campaign_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("ai_campaigns.id", ondelete="SET NULL"), index=True
    )
    campaign_lead_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("ai_campaign_leads.id", ondelete="SET NULL")
    )
    lead_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("leads.id", ondelete="SET NULL"), index=True)
    lead_name: Mapped[str | None] = mapped_column(sa.String(160))
    phone_number: Mapped[str] = mapped_column(EncryptedString, nullable=False)
    phone_hash: Mapped[str] = mapped_column(sa.String(64), nullable=False, index=True)
    initiated_by_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"))
    provider: Mapped[str] = mapped_column(sa.String(32), nullable=False)
    provider_call_id: Mapped[str | None] = mapped_column(sa.String(128))
    status: Mapped[str] = mapped_column(sa.String(16), default=CallStatus.INITIATED, nullable=False, index=True)
    attempt: Mapped[int] = mapped_column(sa.Integer, default=1, nullable=False)
    language: Mapped[str] = mapped_column(sa.String(16), default="en-IN", nullable=False)
    started_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)
    answered_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    ended_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    duration_seconds: Mapped[int] = mapped_column(sa.Integer, default=0, nullable=False)
    interest_level: Mapped[str | None] = mapped_column(sa.String(16), index=True)
    qualification_score: Mapped[int | None] = mapped_column(sa.Integer)
    handoff_requested: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    transfer_to_number: Mapped[str | None] = mapped_column(EncryptedString)
    summary: Mapped[str | None] = mapped_column(sa.Text)
    intelligence: Mapped[dict | None] = mapped_column(sa.JSON)
    analysis_status: Mapped[str] = mapped_column(sa.String(16), default=AnalysisStatus.PENDING, nullable=False)
    failure_reason: Mapped[str | None] = mapped_column(sa.String(500))

    agent: Mapped[AIAgent] = relationship(lazy="joined")
    campaign: Mapped[AICampaign | None] = relationship(lazy="joined")


class AIHandoff(UUIDPk, Base):
    __tablename__ = "ai_handoffs"

    ai_call_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("ai_calls.id", ondelete="CASCADE"), nullable=False, index=True
    )
    lead_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("leads.id", ondelete="SET NULL"), index=True)
    reason: Mapped[str] = mapped_column(sa.Text, nullable=False)
    notified_user_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"))
    transferred: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)


class CampaignLog(UUIDPk, Base):
    __tablename__ = "campaign_logs"

    campaign_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("ai_campaigns.id", ondelete="CASCADE"), nullable=False, index=True
    )
    level: Mapped[str] = mapped_column(sa.String(16), default="info", nullable=False)
    event: Mapped[str] = mapped_column(sa.String(64), nullable=False)
    message: Mapped[str] = mapped_column(sa.Text, nullable=False)
    lead_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid)
    ai_call_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False, index=True)
