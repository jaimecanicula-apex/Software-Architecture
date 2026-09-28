"""The health endpoint stays reachable without signing in."""


def test_healthz_is_public(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}
