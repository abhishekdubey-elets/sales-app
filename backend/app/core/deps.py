import uuid
from collections.abc import Callable
from datetime import datetime, timezone

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import as_utc, get_db
from app.core.errors import AppError, forbidden
from app.core.permissions import P, Role
from app.core.security import decode_token
from app.models import User, UserSession

_bearer = HTTPBearer(auto_error=False)


def _unauthorized(detail: str = "Not authenticated") -> AppError:
    return AppError(401, "unauthorized", detail)


async def user_from_access_token(db: AsyncSession, token: str) -> User | None:
    payload = decode_token(token, "access")
    if not payload:
        return None
    try:
        user_id = uuid.UUID(payload["sub"])
        session_id = uuid.UUID(payload["sid"])
    except (KeyError, ValueError):
        return None
    session = await db.get(UserSession, session_id)
    if (
        session is None
        or session.user_id != user_id
        or session.revoked_at is not None
        or as_utc(session.expires_at) < datetime.now(timezone.utc)
    ):
        return None
    user = await db.get(User, user_id)
    if user is None or not user.is_active:
        return None
    user._session_id = session_id  # type: ignore[attr-defined]
    return user


async def get_current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: AsyncSession = Depends(get_db),
) -> User:
    if creds is None or creds.scheme.lower() != "bearer":
        raise _unauthorized()
    user = await user_from_access_token(db, creds.credentials)
    if user is None:
        raise _unauthorized("Session expired or invalid")
    return user


def require(*perms: P) -> Callable:
    async def _dep(user: User = Depends(get_current_user)) -> User:
        missing = {p.value for p in perms} - user.permissions
        if missing:
            raise forbidden()
        return user

    return _dep


def require_role(*roles: Role) -> Callable:
    async def _dep(user: User = Depends(get_current_user)) -> User:
        if user.role_name not in {r.value for r in roles}:
            raise forbidden()
        return user

    return _dep


def client_ip(request: Request) -> str | None:
    fwd = request.headers.get("x-forwarded-for")
    if fwd:
        return fwd.split(",")[0].strip()
    return request.client.host if request.client else None
