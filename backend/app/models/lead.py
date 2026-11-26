import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.crypto import EncryptedString
from app.core.database import Base, Timestamps, UUIDPk, utcnow
from app.models.enums import ConsentStatus, LeadStatus, Priority, enum_check
from app.models.user import User


class Lead(UUIDPk, Timestamps, Base):
    __tablename__ = "leads"
    __table_args__ = (
        enum_check("status", LeadStatus),
        enum_check("priority", Priority),
        enum_check("consent_status", ConsentStatus),
        # Duplicate protection: one live lead per phone / email (soft-deleted rows excluded).
        sa.Index(
            "uq_leads_phone_hash_live", "phone_hash", unique=True,
            postgresql_where=sa.text("deleted_at IS NULL"), sqlite_where=sa.text("deleted_at IS NULL"),
        ),
        sa.Index(
            "uq_leads_email_hash_live", "email_hash", unique=True,
            postgresql_where=sa.text("deleted_at IS NULL AND email_hash IS NOT NULL"),
            sqlite_where=sa.text("deleted_at IS NULL AND email_hash IS NOT NULL"),
        ),
        sa.Index("ix_leads_status_assigned", "status", "assigned_to_id"),
    )

    full_name: Mapped[str] = mapped_column(sa.String(160), nullable=False, index=True)
    company_name: Mapped[str | None] = mapped_column(sa.String(200), index=True)
    phone: Mapped[str] = mapped_column(EncryptedString, nullable=False)
    phone_hash: Mapped[str] = mapped_column(sa.String(64), nullable=False)
    alternate_phone: Mapped[str | None] = mapped_column(EncryptedString)
    alternate_phone_hash: Mapped[str | None] = mapped_column(sa.String(64), index=True)
    email: Mapped[str | None] = mapped_column(EncryptedString)
    email_hash: Mapped[str | None] = mapped_column(sa.String(64))
    designation: Mapped[str | None] = mapped_column(sa.String(160))
    industry: Mapped[str | None] = mapped_column(sa.String(120), index=True)
    location: Mapped[str | None] = mapped_column(sa.String(160))
    source: Mapped[str | None] = mapped_column(sa.String(120), index=True)
    assigned_to_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    status: Mapped[str] = mapped_column(sa.String(32), default=LeadStatus.NEW, nullable=False)
    priority: Mapped[str] = mapped_column(sa.String(16), default=Priority.MEDIUM, nullable=False)
    last_called_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    next_followup_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True), index=True)
    remarks: Mapped[str | None] = mapped_column(sa.Text)
    consent_status: Mapped[str] = mapped_column(sa.String(16), default=ConsentStatus.UNKNOWN, nullable=False)
    opted_out: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"))
    deleted_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True), index=True)

    assigned_to: Mapped[User | None] = relationship(foreign_keys=[assigned_to_id], lazy="joined")


class LeadAssignment(UUIDPk, Base):
    __tablename__ = "lead_assignments"

    lead_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("leads.id", ondelete="CASCADE"), nullable=False, index=True
    )
    from_user_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"))
    to_user_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    assigned_by_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"))
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)


class LeadActivity(UUIDPk, Base):
    """Lead history entries that are not calls/follow-ups (those are read from their own tables)."""

    __tablename__ = "lead_activities"

    lead_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("leads.id", ondelete="CASCADE"), nullable=False, index=True
    )
    type: Mapped[str] = mapped_column(sa.String(32), nullable=False)
    title: Mapped[str] = mapped_column(sa.String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(sa.Text)
    actor_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"))
    actor_name: Mapped[str | None] = mapped_column(sa.String(160))
    ref_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)


class FavouriteLead(Base):
    __tablename__ = "favourite_leads"

    user_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    lead_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, sa.ForeignKey("leads.id", ondelete="CASCADE"), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)


class OptOut(UUIDPk, Base):
    """Do-not-call list keyed by phone blind index. Checked before every human or AI call."""

    __tablename__ = "opt_outs"

    phone_hash: Mapped[str] = mapped_column(sa.String(64), unique=True, nullable=False)
    reason: Mapped[str | None] = mapped_column(sa.String(255))
    source: Mapped[str] = mapped_column(sa.String(32), nullable=False)  # lead_request|ai_call|admin|dnd_registry
    lead_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("leads.id", ondelete="SET NULL"))
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"))
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)


class LeadCallLock(Base):
    """At most one live call (human or AI) per lead. Primary key on lead_id enforces it."""

    __tablename__ = "lead_call_locks"

    lead_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, sa.ForeignKey("leads.id", ondelete="CASCADE"), primary_key=True)
    holder_type: Mapped[str] = mapped_column(sa.String(16), nullable=False)  # human|ai
    holder_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, nullable=False)
    acquired_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), nullable=False)
