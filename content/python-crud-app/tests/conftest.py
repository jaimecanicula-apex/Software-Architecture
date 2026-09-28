"""Test fixtures: SQLite database and local-folder image storage, both reset
per test by pointing APP_DATA_DIR at a fresh tmp_path."""
import re

import pytest


@pytest.fixture()
def app(tmp_path, monkeypatch):
    monkeypatch.setenv("APP_DATA_DIR", str(tmp_path))
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.delenv("DB_HOST", raising=False)
    monkeypatch.delenv("AZURE_STORAGE_ACCOUNT_NAME", raising=False)
    monkeypatch.setenv("SEED_ADMIN_USERNAME", "admin")
    monkeypatch.setenv("SEED_ADMIN_PASSWORD", "admin-pass-123")
    monkeypatch.setenv("SEED_DEMO_USERNAME", "demo")
    monkeypatch.setenv("SEED_DEMO_PASSWORD", "demo-pass-123")
    monkeypatch.setenv("APP_ENV", "development")

    from app.db import init_engine
    init_engine()

    from app import create_app
    yield create_app({"TESTING": True})


@pytest.fixture()
def client(app):
    return app.test_client()


def login(client, username, password):
    page = client.get("/login")
    token = _extract_csrf(page.text)
    return client.post(
        "/login",
        data={"username": username, "password": password, "csrf_token": token},
        follow_redirects=True,
    )


def _extract_csrf(html: str) -> str:
    match = re.search(r'name="csrf_token" value="([^"]+)"', html)
    return match.group(1) if match else ""
