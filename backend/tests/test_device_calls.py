"""Calls placed from the salesperson's own phone (no telephony provider) and the admin/employee sign-in."""

import sqlalchemy as sa

from app.core.database import SessionLocal
from app.models import Followup, HumanCall, Lead
from tests.conftest import PASSWORD, login, make_lead


async def test_phone_call_is_logged_against_the_salesperson(client, org):
    lead = await make_lead("Asha", "+919000000601", org["ex1"].id)
    ex = await login(client, "ex1@test.local")
    status = (await client.get("/api/v1/settings/telephony-status", headers=ex)).json()
    assert status["configured"] is False and status["call_mode"] == "device"

    r = await client.post("/api/v1/calls/device", headers=ex, json={"lead_id": str(lead.id)})
    assert r.status_code == 201, r.text
    call = r.json()
    # executives see masked numbers elsewhere, but get the real number for the call they are making
    assert call["dial_number"] == "+919000000601" and "•" in call["phone_number"]
    assert call["provider"] == "device" and call["status"] == "initiated"
    assert call["salesperson_id"] == str(org["ex1"].id)

    # a second simultaneous call to the same lead is refused
    busy = await client.post("/api/v1/calls/device", headers=ex, json={"lead_id": str(lead.id)})
    assert busy.status_code == 409 and busy.json()["code"] == "lead_busy"

    r = await client.post(f"/api/v1/calls/{call['id']}/device-result", headers=ex,
                          json={"connected": True, "duration_seconds": 125})
    assert r.status_code == 200, r.text
    done = r.json()
    assert done["status"] == "completed" and done["talk_seconds"] == 125 and done["answered_at"]
    again = await client.post(f"/api/v1/calls/{call['id']}/device-result", headers=ex,
                              json={"connected": False, "duration_seconds": 0})
    assert again.status_code == 409 and again.json()["code"] == "already_reported"

    r = await client.post(f"/api/v1/calls/{call['id']}/disposition", headers=ex,
                          json={"outcome": "follow_up_required", "followup_at": "2030-02-01T11:00:00+05:30"})
    assert r.status_code == 200
    async with SessionLocal() as db:
        lead_row = await db.get(Lead, lead.id)
        assert lead_row.status == "follow_up"
        assert (await db.execute(sa.select(sa.func.count()).select_from(Followup))).scalar_one() == 1

    admin = await login(client, "admin@test.local")
    d = (await client.get("/api/v1/analytics/dashboard", headers=admin)).json()
    assert d["total_calls"] == 1 and d["connected_calls"] == 1 and d["total_duration_seconds"] == 125
    board = (await client.get("/api/v1/analytics/leaderboard", headers=admin)).json()
    assert board[0]["name"] == "Exec One" and board[0]["calls"] == 1


async def test_unanswered_phone_call_and_manual_number(client, org):
    ex = await login(client, "ex2@test.local")
    r = await client.post("/api/v1/calls/device", headers=ex, json={"phone_number": "98765 00002"})
    assert r.status_code == 201 and r.json()["dial_number"] == "+919876500002"
    call_id = r.json()["id"]
    r = await client.post(f"/api/v1/calls/{call_id}/device-result", headers=ex,
                          json={"connected": False, "duration_seconds": 20})
    assert r.json()["status"] == "not_answered" and r.json()["talk_seconds"] == 0
    # another salesperson can't report on it
    other = await login(client, "ex3@test.local")
    assert (await client.post(f"/api/v1/calls/{call_id}/device-result", headers=other,
                              json={"connected": True, "duration_seconds": 5})).status_code == 404


async def test_phone_calls_respect_opt_out_and_bridge_calls_are_separate(client, org, provider):
    lead = await make_lead("Opted", "+919000000602", org["ex1"].id, opted_out=True)
    ex = await login(client, "ex1@test.local")
    r = await client.post("/api/v1/calls/device", headers=ex, json={"lead_id": str(lead.id)})
    assert r.status_code == 403 and r.json()["code"] == "opted_out"
    # with a provider configured the app uses bridge calls; reporting a result on one is refused
    ok_lead = await make_lead("Bridge", "+919000000603", org["ex1"].id)
    bridge = (await client.post("/api/v1/calls", headers=ex, json={"lead_id": str(ok_lead.id)})).json()
    r = await client.post(f"/api/v1/calls/{bridge['id']}/device-result", headers=ex,
                          json={"connected": True, "duration_seconds": 10})
    assert r.status_code == 409 and r.json()["code"] == "not_device_call"
    async with SessionLocal() as db:
        providers = set((await db.execute(sa.select(HumanCall.provider))).scalars())
    assert providers == {"fake"}


async def test_admin_and_employee_sign_in(client, org):
    async def attempt(email, portal):
        return await client.post("/api/v1/auth/login", json={"email": email, "password": PASSWORD, "portal": portal})

    assert (await attempt("admin@test.local", "admin")).status_code == 200
    assert (await attempt("ex1@test.local", "employee")).status_code == 200
    assert (await attempt("mgr.a@test.local", "employee")).status_code == 200  # managers are employees

    r = await attempt("ex1@test.local", "admin")
    assert r.status_code == 403 and r.json()["code"] == "wrong_portal"
    r = await attempt("admin@test.local", "employee")
    assert r.status_code == 403 and r.json()["code"] == "wrong_portal"
    # a refused portal never creates a session
    sessions = (await client.get("/api/v1/auth/sessions", headers=await login(client, "ex2@test.local"))).json()
    assert len(sessions) == 1

    # several employees signed in at once, each seeing only their own data
    h1, h2 = await login(client, "ex1@test.local"), await login(client, "ex2@test.local")
    assert (await client.get("/api/v1/auth/me", headers=h1)).json()["email"] == "ex1@test.local"
    assert (await client.get("/api/v1/auth/me", headers=h2)).json()["email"] == "ex2@test.local"
