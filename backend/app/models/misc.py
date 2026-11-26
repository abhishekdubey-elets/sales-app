import uuid
from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base, Timestamps, UUIDPk, utcnow
from app.models.enums import FollowupSource, FollowupStatus, NotificationType, enum_check


class Followup(UUIDPk, Timestamps, Base):
    __tablename__ = "followups"
    __table_args__ = (
        enum_check("status", FollowupStatus),
        enum_check("source", FollowupSource),
        sa.Index("ix_followups_assignee_due", "assigned_to_id", "status", "due_at"),
    )

    lead_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("leads.id", ondelete="CASCADE"), nullable=False, index=True
    )
    assigned_to_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"))
    due_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), nullable=False)
    status: Mapped[str] = mapped_column(sa.String(16), default=FollowupStatus.PENDING, nullable=False)
    note: Mapped[str | None] = mapped_column(sa.Text)
    source: Mapped[str] = mapped_column(sa.String(16), default=FollowupSource.MANUAL, nullable=False)
    human_call_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("human_calls.id", ondelete="SET NULL"))
    ai_call_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("ai_calls.id", ondelete="SET NULL"))
    reminded_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"))


class Notification(UUIDPk, Base):
    __tablename__ = "notifications"
    __table_args__ = (
        enum_check("type", NotificationType),
        sa.Index("ix_notifications_user_read", "user_id", "read_at"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    type: Mapped[str] = mapped_column(sa.String(32), nullable=False)
    title: Mapped[str] = mapped_column(sa.String(255), nullable=False)
    body: Mapped[str] = mapped_column(sa.Text, default="", nullable=False)
    data: Mapped[dict] = mapped_column(sa.JSON, default=dict, nullable=False)
    read_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    pushed_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False, index=True)


class AuditLog(UUIDPk, Base):
    __tablename__ = "audit_logs"

    actor_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"), index=True)
    actor_name: Mapped[str | None] = mapped_column(sa.String(160))
    action: Mapped[str] = mapped_column(sa.String(64), nullable=False, index=True)
    entity_type: Mapped[str | None] = mapped_column(sa.String(64), index=True)
    entity_id: Mapped[str | None] = mapped_column(sa.String(64))
    details: Mapped[dict] = mapped_column(sa.JSON, default=dict, nullable=False)
    ip_address: Mapped[str | None] = mapped_column(sa.String(64))
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False, index=True)


class OrgSettings(Timestamps, Base):
    """Single-row organisation settings (id = 1)."""

    __tablename__ = "org_settings"

    id: Mapped[int] = mapped_column(sa.Integer, primary_key=True, default=1)
    timezone: Mapped[str] = mapped_column(sa.String(64), default="Asia/Kolkata", nullable=False)
    calling_hours_start: Mapped[str] = mapped_column(sa.String(5), default="09:00", nullable=False)
    calling_hours_end: Mapped[str] = mapped_column(sa.String(5), default="21:00", nullable=False)
    calling_days: Mapped[list[int]] = mapped_column(sa.JSON, default=lambda: [1, 2, 3, 4, 5, 6], nullable=False)
    recording_enabled: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    recording_disclosure_text: Mapped[str] = mapped_column(
        sa.Text, default="This call may be recorded for quality and training purposes.", nullable=False
    )
    ai_disclosure_text: Mapped[str] = mapped_column(
        sa.Text,
        default="Hello, this is an AI assistant calling on behalf of Elets Technomedia.",
        nullable=False,
    )
    require_consent_for_ai_calls: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    mask_numbers_for_executives: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    calling_credits_minutes: Mapped[int | None] = mapped_column(sa.Integer)  # NULL = unlimited
    credits_used_minutes: Mapped[int] = mapped_column(sa.Integer, default=0, nullable=False)
    low_credit_threshold_minutes: Mapped[int] = mapped_column(sa.Integer, default=500, nullable=False)
    daily_summary_time: Mapped[str] = mapped_column(sa.String(5), default="19:00", nullable=False)
    last_daily_summary_date: Mapped[date | None] = mapped_column(sa.Date)
