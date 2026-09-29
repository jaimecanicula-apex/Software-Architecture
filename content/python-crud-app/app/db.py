"""Database engine and session.

DATABASE_URL, or DB_HOST/DB_USER/DB_PASSWORD/DB_NAME, picks PostgreSQL; with
none of those set, falls back to a SQLite file under APP_DATA_DIR, so local
dev and tests need no database server.

engine/SessionLocal are created once at import time from the environment at
that moment. init_engine() rebuilds them from the *current* environment —
call it before create_app() in any test that changes DATABASE_URL, DB_HOST
or APP_DATA_DIR. Other modules must import get_session()/get_engine(), not
SessionLocal/engine directly: a direct `from app.db import SessionLocal`
binds the name at import time and misses a later init_engine() rebuild,
since Python resolves a name used inside a function body from the module's
current globals, not the value captured at import time.
"""
import os

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, scoped_session, sessionmaker


class Base(DeclarativeBase):
    pass


def database_url() -> str:
    explicit = os.environ.get("DATABASE_URL")
    if explicit:
        return explicit
    host = os.environ.get("DB_HOST")
    if not host:
        data_dir = os.environ.get("APP_DATA_DIR", "/tmp")
        return f"sqlite:///{data_dir}/app.db"
    user = os.environ["DB_USER"]
    password = os.environ["DB_PASSWORD"]
    name = os.environ.get("DB_NAME", "app")
    return f"postgresql+psycopg://{user}:{password}@{host}:5432/{name}?sslmode=require"


def _build():
    engine = create_engine(database_url(), pool_pre_ping=True)
    return engine, scoped_session(sessionmaker(bind=engine, expire_on_commit=False))


engine, SessionLocal = _build()


def init_engine() -> None:
    global engine, SessionLocal
    engine, SessionLocal = _build()


def get_engine():
    return engine


def get_session():
    return SessionLocal()


def remove_session() -> None:
    """Call at request teardown. A plain `from app.db import SessionLocal`
    elsewhere would bind the pre-init_engine() object at import time and
    remove the wrong (stale) scoped session after a test's init_engine()
    rebuild; this function resolves SessionLocal from the module's current
    globals at call time instead, the same late-binding get_session() relies
    on."""
    SessionLocal.remove()
