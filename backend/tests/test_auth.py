from tests.conftest import PASSWORD, login


async def test_login_me_refresh_logout(client, org):
    r = await client.post("/api/v1/auth/login", json={"email": "EX1@test.local", "password": PASSWORD,
                                                      "device_name": "Pixel"})
    assert r.status_code == 200
    pair = r.json()
    assert pair["user"]["role"] == "executive" and pair["user"]["team_name"] == "Team A"
    me = await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {pair['access_token']}"})
    assert me.json()["email"] == "ex1@test.local"

    r2 = await client.post("/api/v1/auth/refresh", json={"refresh_token": pair["refresh_token"]})
    assert r2.status_code == 200
    # refresh tokens rotate: the old one no longer works
    r3 = await client.post("/api/v1/auth/refresh", json={"refresh_token": pair["refresh_token"]})
    assert r3.status_code == 401

    new = r2.json()
    await client.post("/api/v1/auth/logout", json={"refresh_token": new["refresh_token"]})
    gone = await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {new['access_token']}"})
    assert gone.status_code == 401  # revoked session invalidates its access tokens


async def test_bad_password_and_throttle(client, org):
    for _ in range(5):
        r = await client.post("/api/v1/auth/login", json={"email": "ex2@test.local", "password": "wrong"})
        assert r.status_code == 401 and r.json()["code"] == "invalid_credentials"
    r = await client.post("/api/v1/auth/login", json={"email": "ex2@test.local", "password": PASSWORD})
    assert r.status_code == 429


async def test_rbac_and_user_management(client, org):
    ex = await login(client, "ex1@test.local")
    r = await client.post("/api/v1/users", headers=ex, json={"full_name": "X", "email": "x@test.local",
                                                             "password": "Password1", "role": "executive"})
    assert r.status_code == 403
    admin = await login(client, "admin@test.local")
    r = await client.post("/api/v1/users", headers=admin, json={"full_name": "New Exec", "email": "new@test.local",
                                                                "password": "Password1", "role": "executive",
                                                                "team_id": str(org["team_b"].id),
                                                                "calling_number": "98111 22233"})
    assert r.status_code == 201
    assert r.json()["calling_number"] == "+919811122233"
    mgr = await login(client, "mgr.a@test.local")
    users = (await client.get("/api/v1/users", headers=mgr)).json()
    assert {u["email"] for u in users["items"]} == {"mgr.a@test.local", "ex1@test.local", "ex2@test.local"}
    r = await client.patch(f"/api/v1/users/{org['ex1'].id}", headers=mgr, json={"role": "admin"})
    assert r.status_code == 403


async def test_change_password_revokes_other_sessions(client, org):
    a = await login(client, "ex3@test.local")
    b = await login(client, "ex3@test.local")
    r = await client.post("/api/v1/auth/change-password", headers=a,
                          json={"current_password": PASSWORD, "new_password": "NewPass@123"})
    assert r.status_code == 204
    assert (await client.get("/api/v1/auth/me", headers=a)).status_code == 200
    assert (await client.get("/api/v1/auth/me", headers=b)).status_code == 401
