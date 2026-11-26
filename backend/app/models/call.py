import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.crypto import EncryptedString
from app.core.database import Base, Timestamps, UUIDPk, utcnow
from app.models.enums import CallDirection, CallOutcome, CallStatus, enum_check

# Exactly one parent: a human call XOR an AI call.
_ONE_PARENT = "(human_call_id IS NOT NULL AND ai_call_id IS NULL) OR (human_call_id IS NULL AND ai_call_id IS NOT NULL)"


class HumanCall(UUIDPk, Timestamps, Base):
    """A call made or received by a salesperson. Always traceable to `salesperson_id`."""

    __tablename__ = "human_calls"
    __table_args__ = (
        enum_check("status", CallStatus),
        enum_check("direction", CallDirection),
        sa.CheckConstraint(
            "outcome IS NULL OR outcome IN (" + ", ".join(f"'{o.value}'" for o in CallOutcome) + ")",
            name="outcome_valid",
        ),
        sa.Index("ix_human_calls_salesperson_started", "salesperson_id", "started_at"),
        sa.Index("ix_human_calls_provider_call", "provider", "provider_call_id"),
    )

    direction: Mapped[str] = mapped_column(sa.String(16), default=CallDirection.OUTBOUND, nullable=False)
    lead_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("leads.id", ondelete="SET NULL"), index=True
    )
    lead_name: Mapped[str | None] = mapped_column(sa.String(160))
    phone_number: Mapped[str] = mapped_column(EncryptedString, nullable=False)
    phone_hash: Mapped[str] = mapped_column(sa.String(64), nullable=False, index=True)
    salesperson_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    salesperson_name: Mapped[str] = mapped_column(sa.String(160), nullable=False)
    team_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("teams.id", ondelete="SET NULL"), index=True
    )
    provider: Mapped[str] = mapped_column(sa.String(32), nullable=False)
    provider_call_id: Mapped[str | None] = mapped_column(sa.String(128))
    status: Mapped[str] = mapped_column(sa.String(16), default=CallStatus.INITIATED, nullable=False, index=True)
    started_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)
    answered_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    ended_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    duration_seconds: Mapped[int] = mapped_column(sa.Integer, default=0, nullable=False)
    talk_seconds: Mapped[int] = mapped_column(sa.Integer, default=0, nullable=False)
    outcome: Mapped[str | None] = mapped_column(sa.String(32), index=True)
    followup_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    disposition_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    failure_reason: Mapped[str | None] = mapped_column(sa.String(500))


class CallRecording(UUIDPk, Base):
    __tablename__ = "call_recordings"
    __table_args__ = (sa.CheckConstraint(_ONE_PARENT, name="one_parent"),)

    human_call_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("human_calls.id", ondelete="CASCADE"), index=True
    )
    ai_call_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("ai_calls.id", ondelete="CASCADE"), index=True
    )
    provider: Mapped[str] = mapped_column(sa.String(32), nullable=False)
    provider_recording_id: Mapped[str | None] = mapped_column(sa.String(128))
    url: Mapped[str] = mapped_column(EncryptedString, nullable=False)
    duration_seconds: Mapped[int | None] = mapped_column(sa.Integer)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)


class CallTranscript(UUIDPk, Base):
    __tablename__ = "call_transcripts"
    __table_args__ = (sa.CheckConstraint(_ONE_PARENT, name="one_parent"),)

    human_call_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("human_calls.id", ondelete="CASCADE"), unique=True
    )
    ai_call_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("ai_calls.id", ondelete="CASCADE"), unique=True
    )
    language: Mapped[str | None] = mapped_column(sa.String(16))
    segments: Mapped[list[dict]] = mapped_column(sa.JSON, default=list, nullable=False)
    full_text: Mapped[str] = mapped_column(sa.Text, default="", nullable=False)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)


class CallNote(UUIDPk, Base):
    __tablename__ = "call_notes"
    __table_args__ = (sa.CheckConstraint(_ONE_PARENT, name="one_parent"),)

    human_call_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("human_calls.id", ondelete="CASCADE"), index=True
    )
    ai_call_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("ai_calls.id", ondelete="CASCADE"), index=True
    )
    author_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"))
    author_name: Mapped[str | None] = mapped_column(sa.String(160))
    body: Mapped[str] = mapped_column(sa.Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)


class TelephonyEvent(UUIDPk, Base):
    """Raw provider callbacks, kept for audit and debugging."""

    __tablename__ = "telephony_events"

    provider: Mapped[str] = mapped_column(sa.String(32), nullable=False)
    kind: Mapped[str] = mapped_column(sa.String(16), nullable=False)  # human|ai|inbound
    call_ref_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, index=True)
    provider_call_id: Mapped[str | None] = mapped_column(sa.String(128), index=True)
    event: Mapped[str] = mapped_column(sa.String(32), nullable=False)
    payload: Mapped[dict] = mapped_column(sa.JSON, default=dict, nullable=False)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)
