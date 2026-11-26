from app.core.database import SessionLocal
from app.models import Notification
from tests.conftest import login, make_lead


async def test_create_duplicate_and_masking(client, org):
    ex = await login(client, "ex1@test.local")
    r = await client.post("/api/v1/leads", headers=ex, json={
        "full_name": "Asha Verma", "company_name": "Sunrise School", "phone": "98765 43210", "email": "Asha@Example.com",
        "priority": "high"})
    assert r.status_code == 201, r.text
    lead = r.json()
    assert lead["assigned_to_id"] == str(org["ex1"].id)  # executives own leads they create
    assert lead["phone"].startswith("+91") and "•" in lead["phone"]  # masked for executives
    assert lead["email"] == "asha@example.com"

    dup = await client.post("/api/v1/leads", headers=ex, json={"full_name": "Other", "phone": "+919876543210"})
    assert dup.status_code == 409 and dup.json()["duplicate_lead_id"] == lead["id"]
    dup2 = await client.post("/api/v1/leads", headers=ex, json={"full_name": "Other", "phone": "9000000001",
                                                                "email": "ASHA@example.com"})
    assert dup2.status_code == 409 and dup2.json()["matched_on"] == "email"

    admin = await login(client, "admin@test.local")
    full = (await client.get(f"/api/v1/leads/{lead['id']}", headers=admin)).json()
    assert full["phone"] == "+919876543210"
    found = (await client.get("/api/v1/leads", headers=admin, params={"q": "098765-43210"})).json()
    assert found["total"] == 1  # phone search works on encrypted numbers via the blind index


async def test_scoping(client, org):
    await make_lead("Lead A1", "+919000000011", org["ex1"].id)
    await make_lead("Lead A2", "+919000000012", org["ex2"].id)
    await make_lead("Lead B1", "+919000000013", org["ex3"].id)
    await make_lead("Unassigned", "+919000000014")
    names = lambda r: {i["full_name"] for i in r.json()["items"]}  # noqa: E731
    assert names(await client.get("/api/v1/leads", headers=await login(client, "ex1@test.local"))) == {"Lead A1"}
    assert names(await client.get("/api/v1/leads", headers=await login(client, "mgr.a@test.local"))) == {
        "Lead A1", "Lead A2", "Unassigned"}
    assert len(names(await client.get("/api/v1/leads", headers=await login(client, "admin@test.local")))) == 4


async def test_bulk_assign_notifies(client, org):
    l1 = await make_lead("L1", "+919000000021")
    l2 = await make_lead("L2", "+919000000022")
    mgr = await login(client, "mgr.a@test.local")
    r = await client.post("/api/v1/leads/assign", headers=mgr,
                          json={"lead_ids": [str(l1.id), str(l2.id)], "assignee_id": str(org["ex2"].id)})
    assert r.json() == {"assigned": 2}
    # managers can't assign outside their team
    r = await client.post("/api/v1/leads/assign", headers=mgr,
                          json={"lead_ids": [str(l1.id)], "assignee_id": str(org["ex3"].id)})
    assert r.status_code == 403
    async with SessionLocal() as db:
        from sqlalchemy import select

        notes = (await db.execute(select(Notification).where(Notification.user_id == org["ex2"].id))).scalars().all()
    assert len(notes) == 1 and notes[0].title == "2 new leads assigned"
    timeline = (await client.get(f"/api/v1/leads/{l1.id}/timeline", headers=mgr)).json()
    assert timeline[0]["type"] == "assigned"


async def test_import_csv(client, org):
    await make_lead("Existing", "+919000000031")
    csv = ("Name,Company,Mobile,Email,City,Priority\n"
           "New One,Acme,9000000032,new1@example.com,Delhi,HIGH\n"
           "Dup Existing,Acme,+91 90000 00031,,Delhi,low\n"
           "Dup In File,Acme,9000000032,,Delhi,low\n"
           ",NoName,9000000033,,,\n"
           "Bad Phone,Acme,12,,,\n")
    admin = await login(client, "admin@test.local")
    r = await client.post("/api/v1/leads/import", headers=admin,
                          files={"file": ("leads.csv", csv.encode(), "text/csv")},
                          data={"assignee_id": str(org["ex1"].id)})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["total_rows"] == 5 and body["created"] == 1 and body["duplicates"] == 2
    assert sorted(e["row"] for e in body["errors"]) == [5, 6]
    lead = (await client.get(f"/api/v1/leads/{body['lead_ids'][0]}", headers=admin)).json()
    assert lead["priority"] == "high" and lead["assigned_to_id"] == str(org["ex1"].id)


async def test_delete_is_admin_only_and_soft(client, org):
    lead = await make_lead("To Delete", "+919000000041", org["ex1"].id)
    ex = await login(client, "ex1@test.local")
    assert (await client.delete(f"/api/v1/leads/{lead.id}", headers=ex)).status_code == 403
    admin = await login(client, "admin@test.local")
    assert (await client.delete(f"/api/v1/leads/{lead.id}", headers=admin)).status_code == 204
    assert (await client.get(f"/api/v1/leads/{lead.id}", headers=admin)).status_code == 404
    # the number can be re-added after a soft delete
    r = await client.post("/api/v1/leads", headers=admin, json={"full_name": "Back", "phone": "+919000000041"})
    assert r.status_code == 201
