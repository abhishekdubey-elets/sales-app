import os

os.environ["ENVIRONMENT"] = "test"
os.environ["DATABASE_URL"] = "sqlite+aiosqlite://"
os.environ["TELEPHONY_PROVIDER"] = ""
os.environ["TELEPHONY_CALLER_ID"] = "+918000000000"
os.environ["ANTHROPIC_API_KEY"] = ""
os.environ["RUN_WORKERS"] = "false"

import pytest  # noqa: E402
import pytest_asyncio  # noqa: E402
import sqlalchemy as sa  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402

from app.core.crypto import phone_hash  # noqa: E402
from app.core.database import Base, SessionLocal, engine  # noqa: E402
from app.core.permissions import DEFAULT_ROLE_PERMISSIONS, Role  # noqa: E402
from app.core.security import hash_password  # noqa: E402
from app.main import app  # noqa: E402
from app.models import Lead, OrgSettings, RoleModel, Team, User, unified_calls_view_sql  # noqa: E402
from app.models.enums import CallStatus, LeadStatus  # noqa: E402
from app.telephony import registry as tel_registry  # noqa: E402
from app.telephony.base import PlacedCall, StatusUpdate, TelephonyError, TelephonyProvider, to_int  # noqa: E402
from app.telephony.media import TwilioMediaAdapter  # noqa: E402
from app.voice import registry as voice_registry  # noqa: E402

PASSWORD = "Test@12345"


class FakeProvider(TelephonyProvider):
    """Test double. Real adapters live in app/telephony; this one never runs outside tests."""

    name = "fake"
    supports_ai_streaming = True
    supports_inbound = True
    transfer_mode = "api"

    def __init__(self) -> None:
        self.placed: list[dict] = []
        self.ai_placed: list[dict] = []
        self.hungup: list[str] = []
        self.transfers: list[tuple[str, str]] = []
        self.fail = False

    def is_configured(self) -> bool:
        return True

    async def place_bridge_call(self, **kw) -> PlacedCall:
        if self.fail:
            raise TelephonyError("rejected by fake provider")
        self.placed.append(kw)
        return PlacedCall(provider_call_id=f"FAKE-H{len(self.placed)}")

    async def place_ai_call(self, **kw) -> PlacedCall:
        if self.fail:
            raise TelephonyError("rejected by fake provider")
        self.ai_placed.append(kw)
        return PlacedCall(provider_call_id=f"FAKE-A{len(self.ai_placed)}")

    async def hangup(self, provider_call_id: str) -> None:
        self.hungup.append(provider_call_id)

    async def transfer(self, provider_call_id, to_number, callbacks, caller_id) -> bool:
        self.transfers.append((provider_call_id, to_number))
        return True

    def parse_status(self, params: dict) -> StatusUpdate:
        st = params.get("status")
        return StatusUpdate(provider_call_id=params.get("sid"), status=CallStatus(st) if st else None,
                            leg=params.get("leg"), duration_seconds=to_int(params.get("duration")),
                            talk_seconds=to_int(params.get("talk")), recording_url=params.get("rec"), raw_status=st)

    def media_adapter(self):
        return TwilioMediaAdapter()


@pytest_asyncio.fixture(autouse=True)
async def db_reset():
    async with engine.begin() as conn:
        await conn.execute(sa.text("DROP VIEW IF EXISTS v_unified_calls"))
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
        await conn.execute(sa.text(unified_calls_view_sql("sqlite")))
    async with SessionLocal() as db:
        for role, perms in DEFAULT_ROLE_PERMISSIONS.items():
            db.add(RoleModel(name=role.value, permissions=sorted(p.value for p in perms)))
        # Tests run at any time of day: open the calling window fully.
        db.add(OrgSettings(id=1, timezone="Asia/Kolkata", calling_hours_start="00:00", calling_hours_end="23:59",
                           calling_days=[1, 2, 3, 4, 5, 6, 7], mask_numbers_for_executives=True))
        await db.commit()
    yield
    tel_registry.set_provider_override(None)
    for kind in ("llm", "stt", "tts"):
        voice_registry.set_override(kind, None)


@pytest_asyncio.fixture
async def client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


@pytest.fixture
def provider():
    p = FakeProvider()
    tel_registry.set_provider_override(p)
    return p


async def make_user(full_name: str, email: str, role: Role, team_id=None, calling_number="+919811100000") -> User:
    async with SessionLocal() as db:
        r = (await db.execute(sa.select(RoleModel).where(RoleModel.name == role.value))).scalar_one()
        u = User(full_name=full_name, email=email, password_hash=hash_password(PASSWORD), role_id=r.id,
                 team_id=team_id, calling_number=calling_number)
        db.add(u)
        await db.commit()
        return u


async def make_team(name: str, manager_id=None) -> Team:
    async with SessionLocal() as db:
        t = Team(name=name, department=name, manager_id=manager_id)
        db.add(t)
        await db.commit()
        return t


async def make_lead(name: str, phone: str, assigned_to=None, **kw) -> Lead:
    async with SessionLocal() as db:
        lead = Lead(full_name=name, phone=phone, phone_hash=phone_hash(phone), assigned_to_id=assigned_to,
                    status=LeadStatus.ASSIGNED if assigned_to else LeadStatus.NEW, **kw)
        db.add(lead)
        await db.commit()
        return lead


async def login(client: AsyncClient, email: str) -> dict:
    r = await client.post("/api/v1/auth/login", json={"email": email, "password": PASSWORD})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest_asyncio.fixture
async def org():
    """Two teams, an admin, two managers and three executives."""
    admin = await make_user("Admin", "admin@test.local", Role.ADMIN)
    team_a = await make_team("Team A")
    team_b = await make_team("Team B")
    mgr_a = await make_user("Manager A", "mgr.a@test.local", Role.MANAGER, team_a.id)
    mgr_b = await make_user("Manager B", "mgr.b@test.local", Role.MANAGER, team_b.id)
    async with SessionLocal() as db:
        (await db.get(Team, team_a.id)).manager_id = mgr_a.id
        (await db.get(Team, team_b.id)).manager_id = mgr_b.id
        await db.commit()
    ex1 = await make_user("Exec One", "ex1@test.local", Role.EXECUTIVE, team_a.id, "+919811100001")
    ex2 = await make_user("Exec Two", "ex2@test.local", Role.EXECUTIVE, team_a.id, "+919811100002")
    ex3 = await make_user("Exec Three", "ex3@test.local", Role.EXECUTIVE, team_b.id, "+919811100003")
    return {"admin": admin, "team_a": team_a, "team_b": team_b, "mgr_a": mgr_a, "mgr_b": mgr_b,
            "ex1": ex1, "ex2": ex2, "ex3": ex3}
