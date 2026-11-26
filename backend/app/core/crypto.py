"""Field-level encryption (Fernet) and blind indexes (HMAC) for PII such as phone numbers."""

import base64
import hashlib
import hmac
import re

import sqlalchemy as sa
from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy.types import TypeDecorator

from app.core.config import settings


def _fernet() -> Fernet:
    key = settings.FIELD_ENCRYPTION_KEY
    if not key:
        # Development fallback only — config validation forbids this outside dev/test.
        key = base64.urlsafe_b64encode(hashlib.sha256(settings.JWT_SECRET.encode()).digest()).decode()
    return Fernet(key.encode())


_FERNET = _fernet()


def encrypt(value: str | None) -> str | None:
    if value is None:
        return None
    return _FERNET.encrypt(value.encode()).decode()


def decrypt(token: str | None) -> str | None:
    if token is None:
        return None
    try:
        return _FERNET.decrypt(token.encode()).decode()
    except InvalidToken:
        return None


def blind_index(value: str | None) -> str | None:
    if not value:
        return None
    return hmac.new(settings.BLIND_INDEX_KEY.encode(), value.encode(), hashlib.sha256).hexdigest()


class EncryptedString(TypeDecorator):
    """Stores Fernet ciphertext; Python side sees plaintext."""

    impl = sa.Text
    cache_ok = True

    def process_bind_param(self, value, dialect):
        return encrypt(value) if value is not None else None

    def process_result_value(self, value, dialect):
        return decrypt(value) if value is not None else None


_NON_DIGIT = re.compile(r"[^\d+]")


def normalize_phone(raw: str | None) -> str | None:
    """Normalise to E.164. Bare 10-digit numbers get the default country code (+91)."""
    if not raw:
        return None
    s = _NON_DIGIT.sub("", raw.strip())
    if not s:
        return None
    if s.startswith("+"):
        digits = s[1:].replace("+", "")
    elif s.startswith("00"):
        digits = s[2:]
    else:
        digits = s.replace("+", "")
        if len(digits) == 11 and digits.startswith("0"):
            digits = digits[1:]
        if len(digits) == 10:
            digits = settings.DEFAULT_COUNTRY_CODE + digits
    if not (8 <= len(digits) <= 15):
        return None
    return "+" + digits


def phone_hash(raw: str | None) -> str | None:
    return blind_index(normalize_phone(raw))


def normalize_email(raw: str | None) -> str | None:
    if not raw:
        return None
    e = raw.strip().lower()
    return e or None


def email_hash(raw: str | None) -> str | None:
    return blind_index(normalize_email(raw))


def mask_phone(phone: str | None) -> str | None:
    if not phone:
        return None
    if len(phone) <= 6:
        return "•" * len(phone)
    return phone[:3] + "•" * (len(phone) - 7) + phone[-4:]
