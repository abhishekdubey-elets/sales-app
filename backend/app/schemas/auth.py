import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.common import Email, Schema

RoleName = Literal["admin", "manager", "executive"]


class UserOut(Schema):
    id: uuid.UUID
    full_name: str
    email: str
    phone: str | None
    calling_number: str | None
    role: RoleName
    team_id: uuid.UUID | None
    team_name: str | None
    is_active: bool
    last_login_at: datetime | None
    created_at: datetime


class LoginIn(BaseModel):
    email: Email
    password: str = Field(min_length=1, max_length=256)
    device_name: str | None = Field(default=None, max_length=120)


class RefreshIn(BaseModel):
    refresh_token: str


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int
    user: UserOut


class ChangePasswordIn(BaseModel):
    current_password: str
    new_password: str = Field(min_length=8, max_length=128)


class SessionOut(BaseModel):
    id: uuid.UUID
    device_name: str | None
    created_at: datetime
    last_used_at: datetime
    expires_at: datetime
    current: bool


class UserCreate(BaseModel):
    full_name: str = Field(min_length=1, max_length=160)
    email: Email
    password: str = Field(min_length=8, max_length=128)
    phone: str | None = None
    calling_number: str | None = None
    role: RoleName
    team_id: uuid.UUID | None = None


class UserUpdate(BaseModel):
    full_name: str | None = Field(default=None, min_length=1, max_length=160)
    email: Email | None = None
    password: str | None = Field(default=None, min_length=8, max_length=128)
    phone: str | None = None
    calling_number: str | None = None
    role: RoleName | None = None
    team_id: uuid.UUID | None = None
    is_active: bool | None = None


class MeUpdate(BaseModel):
    full_name: str | None = Field(default=None, min_length=1, max_length=160)
    phone: str | None = None
    calling_number: str | None = None


class DeviceTokenIn(BaseModel):
    token: str = Field(min_length=10, max_length=512)
    platform: Literal["android", "ios", "web"]


class TeamOut(BaseModel):
    id: uuid.UUID
    name: str
    department: str | None
    manager_id: uuid.UUID | None
    manager_name: str | None
    member_count: int


class TeamCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    department: str | None = None
    manager_id: uuid.UUID | None = None


class TeamUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    department: str | None = None
    manager_id: uuid.UUID | None = None
