"""The application factory's own wiring: things that aren't one controller's
concern (the platform-identity gate, its documented escape hatch)."""


def test_app_env_development_skips_the_entra_header_check(monkeypatch, tmp_path):
    """README.md promises APP_ENV=development runs the app outside a
    Container App, without the platform injecting X-MS-CLIENT-PRINCIPAL-*.
    TESTING already skips the check (every other test relies on that), so
    this proves the independently documented APP_ENV path also works,
    with TESTING off."""
    monkeypatch.setenv("APP_DATA_DIR", str(tmp_path))
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.delenv("DB_HOST", raising=False)
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.delenv("SEED_ADMIN_PASSWORD", raising=False)
    monkeypatch.delenv("SEED_DEMO_PASSWORD", raising=False)

    from app.db import init_engine
    init_engine()

    from app import create_app
    app = create_app({"TESTING": False})
    client = app.test_client()

    resp = client.get("/login")
    assert resp.status_code == 200
