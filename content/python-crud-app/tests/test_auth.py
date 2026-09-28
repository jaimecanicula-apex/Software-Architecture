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
