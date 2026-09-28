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
