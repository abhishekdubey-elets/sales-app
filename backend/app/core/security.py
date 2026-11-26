import hashlib
import hmac
import secrets
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

import bcrypt
from jose import JWTError, jwt

from app.core.config import settings


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=12)).decode()


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode(), password_hash.encode())
    except ValueError:
        return False


def create_access_token(user_id: uuid.UUID, role: str, session_id: uuid.UUID) -> tuple[str, int]:
    expires_in = settings.ACCESS_TOKEN_MINUTES * 60
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "role": role,
        "sid": str(session_id),
        "typ": "access",
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=expires_in)).timestamp()),
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM), expires_in


def decode_token(token: str, expected_type: str = "access") -> dict[str, Any] | None:
    try:
        payload = jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
    except JWTError:
        return None
    if payload.get("typ") != expected_type:
        return None
    return payload


def create_purpose_token(purpose: str, data: dict[str, Any], ttl_seconds: int) -> str:
    now = int(time.time())
    payload = {"typ": purpose, "iat": now, "exp": now + ttl_seconds, **data}
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _hmac(message: str) -> str:
    return hmac.new(settings.WEBHOOK_SIGNING_SECRET.encode(), message.encode(), hashlib.sha256).hexdigest()


def webhook_token(kind: str, call_id: uuid.UUID | str) -> str:
    return _hmac(f"wh:{kind}:{call_id}")[:40]


def verify_webhook_token(kind: str, call_id: str, token: str | None) -> bool:
    if not token:
        return False
    return hmac.compare_digest(webhook_token(kind, call_id), token)


def sign_resource(resource: str, resource_id: str, exp: int) -> str:
    return _hmac(f"res:{resource}:{resource_id}:{exp}")


def verify_resource_signature(resource: str, resource_id: str, exp: int, sig: str) -> bool:
    if exp < int(time.time()):
        return False
    return hmac.compare_digest(sign_resource(resource, resource_id, exp), sig)
