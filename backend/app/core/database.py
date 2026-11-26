import uuid
from collections.abc import AsyncIterator
from datetime import datetime, timezone

import sqlalchemy as sa
from sqlalchemy import MetaData, event
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.core.config import settings

NAMING_CONVENTION = {
    "ix": "ix_%(table_name)s_%(column_0_N_name)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)


class UUIDPk:
    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True, default=uuid.uuid4)


class Timestamps:
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False
    )


def _is_sqlite_memory(url: str) -> bool:
    return url.startswith("sqlite") and (url.rstrip("/").endswith(":") or ":memory:" in url)


def _make_engine(url: str):
    """PostgreSQL in production. SQLite is supported for tests (in memory) and single-machine demos (a file:
    `sqlite+aiosqlite:///./data/elets.db`), e.g. when Docker/PostgreSQL isn't available."""
    kwargs: dict = {"pool_pre_ping": True}
    if url.startswith("sqlite"):
        kwargs = {"connect_args": {"check_same_thread": False, "timeout": 30}}
        if _is_sqlite_memory(url):
            from sqlalchemy.pool import StaticPool

            kwargs["poolclass"] = StaticPool  # one shared connection, or each would get its own empty DB
    eng = create_async_engine(url, **kwargs)
    if url.startswith("sqlite"):
        file_db = not _is_sqlite_memory(url)

        @event.listens_for(eng.sync_engine, "connect")
        def _sqlite_pragmas(dbapi_conn, _):  # pragma: no cover - sqlite only
            cur = dbapi_conn.cursor()
            cur.execute("PRAGMA foreign_keys=ON")
            if file_db:
                # WAL lets the API and background workers read while another connection writes.
                cur.execute("PRAGMA journal_mode=WAL")
                cur.execute("PRAGMA busy_timeout=30000")
            cur.close()

    return eng


engine = _make_engine(settings.DATABASE_URL)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


def configure_engine(url: str) -> None:
    """Re-point the global engine (used by tests)."""
    global engine
    engine = _make_engine(url)
    SessionLocal.configure(bind=engine)


async def get_db() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session


def as_utc(dt: datetime | None) -> datetime | None:
    """SQLite drops tzinfo; normalise everything we read back to aware UTC."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)
