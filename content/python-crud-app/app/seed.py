"""Create the seed admin/demo users on startup, once. A Postgres advisory
lock stops two replicas racing to insert the same username; SQLite
(single-process dev/test) has no such race, so the lock is skipped there."""
import os

from sqlalchemy import text

from app.db import get_engine, get_session
from app.models.user import ROLE_ADMIN, ROLE_USER, User

SEED_LOCK_KEY = 823714  # arbitrary constant, unique to this app's seeding step


def seed_users() -> None:
    db = get_session()
    is_postgres = get_engine().dialect.name == "postgresql"
    if is_postgres:
        db.execute(text("SELECT pg_advisory_lock(:key)"), {"key": SEED_LOCK_KEY})
    try:
        _create_if_missing(db, os.environ.get("SEED_ADMIN_USERNAME", "admin"), os.environ.get("SEED_ADMIN_PASSWORD"), ROLE_ADMIN)
        _create_if_missing(db, os.environ.get("SEED_DEMO_USERNAME", "demo"), os.environ.get("SEED_DEMO_PASSWORD"), ROLE_USER)
    finally:
        if is_postgres:
            db.execute(text("SELECT pg_advisory_unlock(:key)"), {"key": SEED_LOCK_KEY})
        db.commit()


def _create_if_missing(db, username: str, password: str | None, role: str) -> None:
    if not password or db.query(User).filter_by(username=username).one_or_none():
        return
    user = User(username=username, role=role)
    user.set_password(password)
    db.add(user)
    db.commit()
