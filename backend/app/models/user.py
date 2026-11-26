import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base, Timestamps, UUIDPk, utcnow


class RoleModel(UUIDPk, Base):
    __tablename__ = "roles"

    name: Mapped[str] = mapped_column(sa.String(32), unique=True, nullable=False)
    description: Mapped[str | None] = mapped_column(sa.String(255))
    permissions: Mapped[list[str]] = mapped_column(sa.JSON, default=list, nullable=False)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)


class Team(UUIDPk, Timestamps, Base):
    __tablename__ = "teams"

    name: Mapped[str] = mapped_column(sa.String(120), unique=True, nullable=False)
    department: Mapped[str | None] = mapped_column(sa.String(120))
    # No ORM relationship on purpose (users ⇄ teams is circular); manager names are fetched explicitly.
    manager_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL", use_alter=True), index=True
    )


class User(UUIDPk, Timestamps, Base):
    __tablename__ = "users"

    full_name: Mapped[str] = mapped_column(sa.String(160), nullable=False)
    email: Mapped[str] = mapped_column(sa.String(254), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(sa.String(255), nullable=False)
    phone: Mapped[str | None] = mapped_column(sa.String(20))
    # The number the telephony provider rings first for bridge (click-to-call) calls.
    calling_number: Mapped[str | None] = mapped_column(sa.String(20))
    role_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, sa.ForeignKey("roles.id"), nullable=False, index=True)
    team_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("teams.id", ondelete="SET NULL"), index=True
    )
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    last_login_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))

    role: Mapped[RoleModel] = relationship(lazy="joined")
    team: Mapped[Team | None] = relationship(foreign_keys=[team_id], lazy="joined")

    @property
    def role_name(self) -> str:
        return self.role.name

    @property
    def permissions(self) -> set[str]:
        return set(self.role.permissions or [])


class UserSession(UUIDPk, Base):
    __tablename__ = "user_sessions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    refresh_token_hash: Mapped[str] = mapped_column(sa.String(64), unique=True, nullable=False)
    device_name: Mapped[str | None] = mapped_column(sa.String(120))
    ip_address: Mapped[str | None] = mapped_column(sa.String(64))
    user_agent: Mapped[str | None] = mapped_column(sa.String(255))
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)
    last_used_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))


class DeviceToken(UUIDPk, Base):
    __tablename__ = "device_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    token: Mapped[str] = mapped_column(sa.String(512), unique=True, nullable=False)
    platform: Mapped[str] = mapped_column(sa.String(16), nullable=False)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)
