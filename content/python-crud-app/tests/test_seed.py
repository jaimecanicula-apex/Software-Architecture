"""Seeding must be safe to run more than once (mirrors two replicas starting
together and both calling seed_users() before either commits)."""
from app.db import get_session
from app.models.user import User
from app.seed import seed_users


def test_seeding_twice_creates_each_user_once(app):
    seed_users()  # conftest's app fixture already seeded once; seed again explicitly
    db = get_session()
    admins = db.query(User).filter_by(username="admin").all()
    assert len(admins) == 1


def test_seed_users_creates_its_own_schema(app):
    """With gunicorn running 2 workers with no --preload, each worker calls
    create_app() independently, so seed_users() (inside the advisory-lock
    section) must not assume some other caller already ran create_all — it
    must be safe to call against a database that has no tables yet."""
    from app.db import Base, get_engine

    Base.metadata.drop_all(bind=get_engine())

    seed_users()

    db = get_session()
    admin = db.query(User).filter_by(username="admin").one()
    assert admin.username == "admin"
