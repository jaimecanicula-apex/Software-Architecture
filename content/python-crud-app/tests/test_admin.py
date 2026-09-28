"""Admin-only user management, and that non-admins are refused."""
import re

from tests.conftest import login


def _csrf_from(page) -> str:
    return re.search(r'name="csrf_token" value="([^"]+)"', page.text).group(1)


def test_non_admin_cannot_reach_user_management(client):
    login(client, "demo", "demo-pass-123")
    resp = client.get("/admin/users")
    assert resp.status_code == 403


def test_admin_can_create_and_delete_a_user(client):
    login(client, "admin", "admin-pass-123")
    token = _csrf_from(client.get("/admin/users"))

    client.post("/admin/users/new", data={"username": "temp", "password": "temp-pass-123", "role": "user", "csrf_token": token})
    page = client.get("/admin/users")
    assert b"temp" in page.data

    from app.db import get_session
    from app.models.user import User
    db = get_session()
    temp = db.query(User).filter_by(username="temp").one()
    client.post(f"/admin/users/{temp.id}/delete", data={"csrf_token": token})
    page = client.get("/admin/users")
    assert b">temp<" not in page.data


def test_admin_cannot_delete_themselves(client):
    login(client, "admin", "admin-pass-123")
    token = _csrf_from(client.get("/admin/users"))
    from app.db import get_session
    from app.models.user import User
    db = get_session()
    admin = db.query(User).filter_by(username="admin").one()
    resp = client.post(f"/admin/users/{admin.id}/delete", data={"csrf_token": token})
    assert resp.status_code == 400
