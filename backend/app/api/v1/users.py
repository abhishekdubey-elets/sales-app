import uuid

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Query, Request, Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.crypto import normalize_phone
from app.core.database import get_db, utcnow
from app.core.deps import get_current_user, require
from app.core.errors import AppError, forbidden, not_found
from app.core.permissions import P, Role
from app.core.security import hash_password
from app.models import DeviceToken, RoleModel, Team, User
from app.schemas.auth import DeviceTokenIn, MeUpdate, TeamCreate, TeamOut, TeamUpdate, UserCreate, UserOut, UserUpdate
from app.schemas.common import Page
from app.services.audit import audit
from app.services.scoping import scope_users
from app.services.serializers import team_out, user_out

router = APIRouter(tags=["users"])


def _phone_or_none(v: str | None, field: str) -> str | None:
    if v in (None, ""):
        return None
    n = normalize_phone(v)
    if not n:
        raise AppError(422, "validation_error", f"Enter a valid {field}")
    return n


async def _role(db: AsyncSession, name: str) -> RoleModel:
    role = (await db.execute(sa.select(RoleModel).where(RoleModel.name == name))).scalar_one_or_none()
    if role is None:
        raise AppError(422, "validation_error", f"Unknown role {name}")
    return role


@router.get("/users", response_model=Page[UserOut])
async def list_users(
    q: str | None = None, role: str | None = None, team_id: uuid.UUID | None = None, is_active: bool | None = None,
    page: int = Query(1, ge=1), page_size: int = Query(50, ge=1, le=100),
    user: User = Depends(require(P.USERS_VIEW)), db: AsyncSession = Depends(get_db),
):
    stmt = scope_users(sa.select(User).join(RoleModel, User.role_id == RoleModel.id), user)
    if q:
        stmt = stmt.where(sa.or_(User.full_name.ilike(f"%{q}%"), User.email.ilike(f"%{q}%")))
    if role:
        stmt = stmt.where(RoleModel.name == role)
    if team_id:
        stmt = stmt.where(User.team_id == team_id)
    if is_active is not None:
        stmt = stmt.where(User.is_active.is_(is_active))
    total = (await db.execute(sa.select(sa.func.count()).select_from(stmt.subquery()))).scalar_one()
    rows = (await db.execute(stmt.order_by(User.full_name).offset((page - 1) * page_size).limit(page_size))).scalars()
    return {"items": [user_out(u) for u in rows.unique()], "total": total, "page": page, "page_size": page_size}


@router.post("/users", response_model=UserOut, status_code=201)
async def create_user(body: UserCreate, request: Request, actor: User = Depends(require(P.USERS_MANAGE)),
                      db: AsyncSession = Depends(get_db)):
    email = body.email.lower()
    if (await db.execute(sa.select(User.id).where(sa.func.lower(User.email) == email))).scalar():
        raise AppError(409, "duplicate_email", "A user with this email already exists")
    role = await _role(db, body.role)
    u = User(full_name=body.full_name, email=email, password_hash=hash_password(body.password),
             phone=_phone_or_none(body.phone, "phone"), calling_number=_phone_or_none(body.calling_number, "calling number"),
             role_id=role.id, team_id=body.team_id)
    db.add(u)
    await db.flush()
    await audit(db, actor, "user.created", "user", u.id, {"email": email, "role": body.role}, request)
    await db.commit()
    await db.refresh(u, ["role", "team"])
    return user_out(u)


@router.get("/users/{user_id}", response_model=UserOut)
async def get_user(user_id: uuid.UUID, actor: User = Depends(require(P.USERS_VIEW)), db: AsyncSession = Depends(get_db)):
    u = (await db.execute(scope_users(sa.select(User).where(User.id == user_id), actor))).scalar_one_or_none()
    if u is None:
        raise not_found("User")
    return user_out(u)


@router.patch("/users/me", response_model=UserOut)
async def update_me(body: MeUpdate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    data = body.model_dump(exclude_unset=True)
    if "full_name" in data:
        user.full_name = data["full_name"]
    if "phone" in data:
        user.phone = _phone_or_none(data["phone"], "phone")
    if "calling_number" in data:
        user.calling_number = _phone_or_none(data["calling_number"], "calling number")
    await db.commit()
    return user_out(user)


@router.patch("/users/{user_id}", response_model=UserOut)
async def update_user(user_id: uuid.UUID, body: UserUpdate, request: Request, actor: User = Depends(get_current_user),
                      db: AsyncSession = Depends(get_db)):
    u = await db.get(User, user_id)
    if u is None:
        raise not_found("User")
    is_admin = actor.role_name == Role.ADMIN
    is_team_manager = actor.role_name == Role.MANAGER and actor.team_id and u.team_id == actor.team_id
    if not (is_admin or is_team_manager):
        raise forbidden()
    data = body.model_dump(exclude_unset=True)
    if not is_admin and ({"role", "team_id", "email", "password", "is_active"} & data.keys()):
        raise forbidden("Managers can only edit names and phone numbers of their team members")
    if "email" in data and data["email"]:
        email = data["email"].lower()
        clash = (await db.execute(sa.select(User.id).where(sa.func.lower(User.email) == email, User.id != u.id))).scalar()
        if clash:
            raise AppError(409, "duplicate_email", "A user with this email already exists")
        u.email = email
    if "role" in data and data["role"]:
        if u.id == actor.id and data["role"] != Role.ADMIN:
            raise AppError(409, "invalid_state", "You cannot remove your own admin role")
        u.role_id = (await _role(db, data["role"])).id
    if "password" in data and data["password"]:
        u.password_hash = hash_password(data["password"])
    if "is_active" in data and data["is_active"] is not None:
        if u.id == actor.id and not data["is_active"]:
            raise AppError(409, "invalid_state", "You cannot deactivate your own account")
        u.is_active = data["is_active"]
    for field in ("full_name", "team_id"):
        if field in data:
            setattr(u, field, data[field])
    if "phone" in data:
        u.phone = _phone_or_none(data["phone"], "phone")
    if "calling_number" in data:
        u.calling_number = _phone_or_none(data["calling_number"], "calling number")
    u.updated_at = utcnow()
    await audit(db, actor, "user.updated", "user", u.id, {k: v for k, v in data.items() if k != "password"}, request)
    await db.commit()
    await db.refresh(u, ["role", "team"])
    return user_out(u)


@router.post("/users/me/device-tokens", status_code=204)
async def register_device(body: DeviceTokenIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    existing = (await db.execute(sa.select(DeviceToken).where(DeviceToken.token == body.token))).scalar_one_or_none()
    if existing:
        existing.user_id, existing.platform, existing.last_seen_at = user.id, body.platform, utcnow()
    else:
        db.add(DeviceToken(user_id=user.id, token=body.token, platform=body.platform))
    await db.commit()
    return Response(status_code=204)


@router.get("/teams", response_model=list[TeamOut])
async def list_teams(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    teams = (await db.execute(sa.select(Team).order_by(Team.name))).scalars().all()
    return [await team_out(db, t) for t in teams]


@router.post("/teams", response_model=TeamOut, status_code=201)
async def create_team(body: TeamCreate, request: Request, actor: User = Depends(require(P.TEAMS_MANAGE)),
                      db: AsyncSession = Depends(get_db)):
    if (await db.execute(sa.select(Team.id).where(Team.name == body.name))).scalar():
        raise AppError(409, "duplicate_team", "A team with this name already exists")
    t = Team(name=body.name, department=body.department, manager_id=body.manager_id)
    db.add(t)
    await db.flush()
    if body.manager_id:
        mgr = await db.get(User, body.manager_id)
        if mgr:
            mgr.team_id = t.id
    await audit(db, actor, "team.created", "team", t.id, {"name": body.name}, request)
    await db.commit()
    return await team_out(db, t)


@router.patch("/teams/{team_id}", response_model=TeamOut)
async def update_team(team_id: uuid.UUID, body: TeamUpdate, request: Request,
                      actor: User = Depends(require(P.TEAMS_MANAGE)), db: AsyncSession = Depends(get_db)):
    t = await db.get(Team, team_id)
    if t is None:
        raise not_found("Team")
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(t, k, v)
    await audit(db, actor, "team.updated", "team", t.id, body.model_dump(exclude_unset=True, mode="json"), request)
    await db.commit()
    return await team_out(db, t)
