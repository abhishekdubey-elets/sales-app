import time
from collections import defaultdict
from datetime import timedelta

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import as_utc, get_db, utcnow
from app.core.deps import client_ip, get_current_user
from app.core.errors import AppError, not_found
from app.core.security import create_access_token, hash_password, hash_token, new_refresh_token, verify_password
from app.models import User, UserSession
from app.schemas.auth import ChangePasswordIn, LoginIn, RefreshIn, SessionOut, TokenPair, UserOut
from app.services.audit import audit
from app.services.serializers import user_out

router = APIRouter(prefix="/auth", tags=["auth"])

# Simple in-process brute-force guard: 5 failures per (ip, email) per 15 minutes.
_FAILS: dict[tuple[str, str], list[float]] = defaultdict(list)
_WINDOW, _MAX_FAILS = 15 * 60, 5


def _throttled(key: tuple[str, str]) -> bool:
    now = time.time()
    _FAILS[key] = [t for t in _FAILS[key] if now - t < _WINDOW]
    return len(_FAILS[key]) >= _MAX_FAILS


async def _issue(db: AsyncSession, user: User, request: Request, device: str | None,
                 session: UserSession | None = None) -> dict:
    refresh = new_refresh_token()
    if session is None:
        session = UserSession(
            user_id=user.id, device_name=device, ip_address=client_ip(request),
            user_agent=(request.headers.get("user-agent") or "")[:255],
            expires_at=utcnow() + timedelta(days=settings.REFRESH_TOKEN_DAYS), refresh_token_hash=hash_token(refresh),
        )
        db.add(session)
    else:
        session.refresh_token_hash = hash_token(refresh)
        session.last_used_at = utcnow()
        session.expires_at = utcnow() + timedelta(days=settings.REFRESH_TOKEN_DAYS)
    await db.flush()
    access, expires_in = create_access_token(user.id, user.role_name, session.id)
    return {"access_token": access, "refresh_token": refresh, "token_type": "bearer", "expires_in": expires_in,
            "user": user_out(user)}


@router.post("/login", response_model=TokenPair)
async def login(body: LoginIn, request: Request, db: AsyncSession = Depends(get_db)):
    email = body.email.lower()
    key = (client_ip(request) or "?", email)
    if _throttled(key):
        raise AppError(429, "too_many_attempts", "Too many failed attempts. Try again in 15 minutes.")
    user = (await db.execute(sa.select(User).where(sa.func.lower(User.email) == email))).scalar_one_or_none()
    if user is None or not verify_password(body.password, user.password_hash):
        _FAILS[key].append(time.time())
        await audit(db, user, "auth.login_failed", "user", user.id if user else None, {"email": email}, request)
        await db.commit()
        raise AppError(401, "invalid_credentials", "Invalid email or password")
    if not user.is_active:
        raise AppError(403, "account_disabled", "This account has been deactivated")
    _FAILS.pop(key, None)
    user.last_login_at = utcnow()
    pair = await _issue(db, user, request, body.device_name)
    await audit(db, user, "auth.login", "user", user.id, {"device": body.device_name}, request)
    await db.commit()
    return pair


@router.post("/refresh", response_model=TokenPair)
async def refresh(body: RefreshIn, request: Request, db: AsyncSession = Depends(get_db)):
    session = (await db.execute(
        sa.select(UserSession).where(UserSession.refresh_token_hash == hash_token(body.refresh_token))
    )).scalar_one_or_none()
    if session is None or session.revoked_at is not None or as_utc(session.expires_at) < utcnow():
        raise AppError(401, "invalid_refresh_token", "Session expired. Please sign in again.")
    user = await db.get(User, session.user_id)
    if user is None or not user.is_active:
        raise AppError(401, "invalid_refresh_token", "Session expired. Please sign in again.")
    pair = await _issue(db, user, request, session.device_name, session)
    await db.commit()
    return pair


@router.post("/logout", status_code=204)
async def logout(body: RefreshIn, db: AsyncSession = Depends(get_db)):
    session = (await db.execute(
        sa.select(UserSession).where(UserSession.refresh_token_hash == hash_token(body.refresh_token))
    )).scalar_one_or_none()
    if session and session.revoked_at is None:
        session.revoked_at = utcnow()
        await db.commit()
    return Response(status_code=204)


@router.get("/me", response_model=UserOut)
async def me(user: User = Depends(get_current_user)):
    return user_out(user)


@router.post("/change-password", status_code=204)
async def change_password(body: ChangePasswordIn, request: Request, user: User = Depends(get_current_user),
                          db: AsyncSession = Depends(get_db)):
    if not verify_password(body.current_password, user.password_hash):
        raise AppError(400, "invalid_credentials", "Current password is incorrect")
    user.password_hash = hash_password(body.new_password)
    current = getattr(user, "_session_id", None)
    await db.execute(sa.update(UserSession).where(
        UserSession.user_id == user.id, UserSession.id != current, UserSession.revoked_at.is_(None)
    ).values(revoked_at=utcnow()))
    await audit(db, user, "auth.password_changed", "user", user.id, None, request)
    await db.commit()
    return Response(status_code=204)


@router.get("/sessions", response_model=list[SessionOut])
async def sessions(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(sa.select(UserSession).where(
        UserSession.user_id == user.id, UserSession.revoked_at.is_(None), UserSession.expires_at > utcnow()
    ).order_by(UserSession.last_used_at.desc()))).scalars().all()
    current = getattr(user, "_session_id", None)
    return [{"id": s.id, "device_name": s.device_name, "created_at": as_utc(s.created_at),
             "last_used_at": as_utc(s.last_used_at), "expires_at": as_utc(s.expires_at), "current": s.id == current}
            for s in rows]


@router.delete("/sessions/{session_id}", status_code=204)
async def revoke_session(session_id: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    import uuid

    try:
        sid = uuid.UUID(session_id)
    except ValueError as exc:
        raise not_found("Session") from exc
    s = await db.get(UserSession, sid)
    if s is None or s.user_id != user.id:
        raise not_found("Session")
    s.revoked_at = utcnow()
    await db.commit()
    return Response(status_code=204)
