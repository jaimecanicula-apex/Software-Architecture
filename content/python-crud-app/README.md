# python-crud-app

A Flask CRUD example for the `privately-accessible-container-app-with-database-and-storage`
golden template: an asset catalogue with its own username/password login,
layered behind the Container Apps Entra sign-in the infrastructure template
enforces in front.

## Running locally

No database or storage account needed — with `DATABASE_URL`/`DB_HOST` and
`AZURE_STORAGE_ACCOUNT_NAME` unset, the app uses a SQLite file and a local
folder under `APP_DATA_DIR` (defaults to `/tmp`).

```
pip install -r requirements-dev.txt
export SEED_ADMIN_PASSWORD=change-me APP_ENV=development
python -m flask --app app run
```

Sign in at `/login` as `admin` / `change-me`. The Entra header check in
`app/__init__.py` is skipped when `APP_ENV=development`.

## Tests

```
pip install -r requirements-dev.txt
pytest
```

## Environment variables

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` or `DB_HOST`/`DB_USER`/`DB_PASSWORD`/`DB_NAME` | PostgreSQL connection. Unset falls back to SQLite. |
| `AZURE_STORAGE_ACCOUNT_NAME` / `AZURE_STORAGE_CONTAINER` | Blob storage for images. Unset falls back to a local folder. |
| `APP_SECRET_KEY` | Flask session signing key. |
| `SEED_ADMIN_USERNAME` / `SEED_ADMIN_PASSWORD` / `SEED_DEMO_USERNAME` / `SEED_DEMO_PASSWORD` | Seed users created on first startup if missing. |
| `APP_MAX_FAILED_LOGINS` / `APP_LOCKOUT_MINUTES` | Login lockout (defaults 5 / 15). |
| `APP_MAX_UPLOAD_MB` | Upload size limit (default 10). |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Optional: OpenTelemetry export. |
| `APP_ENV=development` | Skips the Entra-header check so the app runs outside a Container App. |
