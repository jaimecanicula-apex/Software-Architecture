"""Login, lockout and CSRF behavior for the app's own username/password layer."""
from tests.conftest import login


def test_login_with_correct_credentials_succeeds(client):
    resp = login(client, "admin", "admin-pass-123")
    assert resp.status_code == 200


def test_login_with_wrong_password_fails(client):
    resp = login(client, "admin", "wrong-password")
    assert resp.status_code == 401


def test_repeated_failures_lock_the_account(client):
    for _ in range(5):
        login(client, "admin", "wrong-password")
    resp = login(client, "admin", "admin-pass-123")
    assert resp.status_code == 401
    assert b"Invalid username or password" in resp.data


def test_post_without_csrf_token_is_rejected(client):
    resp = client.post("/login", data={"username": "admin", "password": "admin-pass-123"})
    assert resp.status_code == 400


def test_post_with_wrong_csrf_token_is_rejected(client):
    login(client, "admin", "admin-pass-123")
    resp = client.post("/logout", data={"csrf_token": "not-the-real-token"})
    assert resp.status_code == 400


def test_deleted_user_is_signed_out_on_the_next_request(client):
    login(client, "demo", "demo-pass-123")

    from app.db import get_session
    from app.models.user import User
    db = get_session()
    demo = db.query(User).filter_by(username="demo").one()
    db.delete(demo)
    db.commit()

    resp = client.get("/assets/", follow_redirects=True)
    assert b"Sign in" in resp.data


def test_demoted_admin_loses_admin_access_on_the_next_request(client):
    login(client, "admin", "admin-pass-123")

    from app.db import get_session
    from app.models.user import ROLE_USER, User
    db = get_session()
    admin = db.query(User).filter_by(username="admin").one()
    admin.role = ROLE_USER
    db.commit()

    resp = client.get("/admin/users")
    assert resp.status_code == 403
