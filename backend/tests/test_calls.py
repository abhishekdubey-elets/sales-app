import sqlalchemy as sa

from app.core.database import SessionLocal
from app.core.security import webhook_token
from app.models import Followup, HumanCall, Lead, OrgSettings
from tests.conftest import login, make_lead


def _hook(call_id: str, **params) -> tuple[str, dict]:
    return "/api/v1/webhooks/telephony/fake/status", {
        "kind": "human", "cid": call_id, "wt": webhook_token("human", call_id), **params}


async def test_no_provider_is_reported_not_faked(client, org):
    lead = await make_lead("Lead", "+919000000101", org["ex1"].id)
    ex = await login(client, "ex1@test.local")
    r = await client.post("/api/v1/calls", headers=ex, json={"lead_id": str(lead.id)})
    assert r.status_code == 503 and r.json()["code"] == "telephony_not_configured"
    async with SessionLocal() as db:
        call = (await db.execute(sa.select(HumanCall))).scalar_one()
    assert call.status == "failed" and call.provider_call_id is None and call.salesperson_id == org["ex1"].id


async def test_full_bridge_call_lifecycle(client, org, provider):
    lead = await make_lead("Lead", "+919000000102", org["ex1"].id)
    ex = await login(client, "ex1@test.local")
    r = await client.post("/api/v1/calls", headers=ex, json={"lead_id": str(lead.id)})
    assert r.status_code == 201, r.text
    call = r.json()
    assert call["status"] == "initiated" and call["provider_call_id"] == "FAKE-H1"
    assert call["salesperson_id"] == str(org["ex1"].id) and call["salesperson_name"] == "Exec One"
    assert provider.placed[0]["agent_number"] == "+919811100001"
    assert provider.placed[0]["customer_number"] == "+919000000102"

    # second simultaneous call to the same lead is refused
    r2 = await client.post("/api/v1/calls", headers=await login(client, "admin@test.local"),
                           json={"lead_id": str(lead.id)})
    assert r2.status_code == 409 and r2.json()["code"] == "lead_busy"

    for params in ({"status": "ringing", "leg": "agent"}, {"status": "connected", "leg": "customer"},
                   {"status": "completed", "leg": "customer", "talk": "95"},
                   {"status": "completed", "leg": "agent", "duration": "130"}):
        url, q = _hook(call["id"], **params)
        assert (await client.post(url, params=q)).status_code == 200

    done = (await client.get(f"/api/v1/calls/{call['id']}", headers=ex)).json()
    assert done["status"] == "completed" and done["talk_seconds"] == 95 and done["duration_seconds"] == 130
    assert done["answered_at"] is not None

    r = await client.post(f"/api/v1/calls/{call['id']}/disposition", headers=ex, json={
        "outcome": "interested", "notes": "Wants sponsorship deck", "followup_at": "2030-01-05T10:00:00+05:30"})
    assert r.status_code == 200
    assert r.json()["notes"][0]["body"] == "Wants sponsorship deck"
    async with SessionLocal() as db:
        lead_row = await db.get(Lead, lead.id)
        fu = (await db.execute(sa.select(Followup))).scalar_one()
    assert lead_row.status == "follow_up" and fu.assigned_to_id == org["ex1"].id

    # the lock was released on completion, so the lead can be called again
    r3 = await client.post("/api/v1/calls", headers=ex, json={"lead_id": str(lead.id)})
    assert r3.status_code == 201


async def test_unanswered_and_provider_rejection(client, org, provider):
    lead = await make_lead("Lead", "+919000000103", org["ex1"].id)
    ex = await login(client, "ex1@test.local")
    call = (await client.post("/api/v1/calls", headers=ex, json={"lead_id": str(lead.id)})).json()
    url, q = _hook(call["id"], status="completed", leg="agent", duration="40")
    await client.post(url, params=q)
    got = (await client.get(f"/api/v1/calls/{call['id']}", headers=ex)).json()
    assert got["status"] == "not_answered"  # salesperson answered, lead never connected

    provider.fail = True
    r = await client.post("/api/v1/calls", headers=ex, json={"lead_id": str(lead.id)})
    assert r.status_code == 502 and r.json()["code"] == "telephony_error"


async def test_webhook_rejects_bad_token(client, org, provider):
    lead = await make_lead("Lead", "+919000000104", org["ex1"].id)
    ex = await login(client, "ex1@test.local")
    call = (await client.post("/api/v1/calls", headers=ex, json={"lead_id": str(lead.id)})).json()
    r = await client.post("/api/v1/webhooks/telephony/fake/status",
                          params={"kind": "human", "cid": call["id"], "wt": "forged", "status": "completed"})
    assert r.status_code == 403


async def test_compliance_gates(client, org, provider):
    lead = await make_lead("Lead", "+919000000105", org["ex1"].id)
    ex = await login(client, "ex1@test.local")
    assert (await client.post(f"/api/v1/leads/{lead.id}/opt-out", headers=ex, json={"reason": "asked"})).status_code == 200
    r = await client.post("/api/v1/calls", headers=ex, json={"phone_number": "9000000105"})
    assert r.status_code == 403 and r.json()["code"] == "opted_out"

    other = await make_lead("Other", "+919000000106", org["ex1"].id)
    async with SessionLocal() as db:
        s = await db.get(OrgSettings, 1)
        s.calling_hours_start, s.calling_hours_end, s.calling_days = "00:00", "00:01", [1]
        await db.commit()
    r = await client.post("/api/v1/calls", headers=ex, json={"lead_id": str(other.id)})
    assert r.status_code == 403 and r.json()["code"] == "outside_calling_hours"
    assert provider.placed == []


async def test_executive_cannot_call_others_leads(client, org, provider):
    lead = await make_lead("Lead", "+919000000107", org["ex3"].id)
    ex = await login(client, "ex1@test.local")
    r = await client.post("/api/v1/calls", headers=ex, json={"lead_id": str(lead.id)})
    assert r.status_code == 404


async def test_dashboard_and_leaderboard(client, org, provider):
    lead = await make_lead("Lead", "+919000000108", org["ex1"].id)
    ex = await login(client, "ex1@test.local")
    call = (await client.post("/api/v1/calls", headers=ex, json={"lead_id": str(lead.id)})).json()
    for p in ({"status": "connected", "leg": "customer"}, {"status": "completed", "leg": "customer", "talk": "60"}):
        url, q = _hook(call["id"], **p)
        await client.post(url, params=q)
    await client.post(f"/api/v1/calls/{call['id']}/disposition", headers=ex, json={"outcome": "converted"})

    admin = await login(client, "admin@test.local")
    d = (await client.get("/api/v1/analytics/dashboard", headers=admin, params={"range": "today"})).json()
    assert d["scope"] == "organization" and d["total_calls"] == 1 and d["connected_calls"] == 1
    assert d["successful_calls"] == 1 and d["total_duration_seconds"] == 60 and d["leads_converted"] == 1
    board = (await client.get("/api/v1/analytics/leaderboard", headers=admin)).json()
    top = board[0]
    assert top["name"] == "Exec One" and top["calls"] == 1 and top["conversions"] == 1
    mine = (await client.get("/api/v1/analytics/me", headers=ex)).json()
    assert mine["calls_today"] == 1 and mine["converted"] == 1
    by_date = (await client.get("/api/v1/analytics/calls-by-date", headers=admin, params={"range": "this_week"})).json()
    assert sum(x["human"] for x in by_date) == 1
    exp = await client.get("/api/v1/analytics/export", headers=admin, params={"report": "calls", "format": "xlsx",
                                                                              "range": "today"})
    assert exp.status_code == 200 and exp.content[:2] == b"PK"
    unified = (await client.get(f"/api/v1/leads/{lead.id}/calls", headers=admin)).json()
    assert unified[0]["origin"] == "human" and unified[0]["salesperson_id"] == str(org["ex1"].id)
