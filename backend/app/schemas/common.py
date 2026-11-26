import re
import uuid
from typing import Annotated, Generic, TypeVar

from pydantic import AfterValidator, BaseModel, ConfigDict

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _check_email(value: str) -> str:
    value = value.strip().lower()
    if len(value) > 254 or not _EMAIL_RE.match(value):
        raise ValueError("Enter a valid email address")
    return value


# Lenient on purpose: internal domains (e.g. *.local) and messy CRM data must still be accepted.
Email = Annotated[str, AfterValidator(_check_email)]

T = TypeVar("T")


class Schema(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    page_size: int


class IdList(BaseModel):
    ids: list[uuid.UUID]


class Count(BaseModel):
    count: int


class SignedUrl(BaseModel):
    url: str
    expires_at: str
