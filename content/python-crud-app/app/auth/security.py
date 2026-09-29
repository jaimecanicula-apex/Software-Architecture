"""Session login helpers and a hand-rolled CSRF token (double-submit
cookie): small enough that adding Flask-WTF just for this would be the
wrong trade for a template meant to stay dependency-light."""
import secrets
from functools import wraps

from flask import abort, redirect, request, session, url_for


def log_in(user) -> None:
    session.clear()
    session["user_id"] = user.id
    session["role"] = user.role
    session["csrf_token"] = secrets.token_urlsafe(32)


def log_out() -> None:
    session.clear()


def csrf_token() -> str:
    if "csrf_token" not in session:
        session["csrf_token"] = secrets.token_urlsafe(32)
    return session["csrf_token"]


def require_csrf(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if request.method in ("POST", "PUT", "PATCH", "DELETE"):
            sent = request.form.get("csrf_token", "")
            expected = session.get("csrf_token", "")
            if not sent or not expected or not secrets.compare_digest(sent, expected):
                abort(400, "Invalid or missing CSRF token.")
        return view(*args, **kwargs)

    return wrapped


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if "user_id" not in session:
            return redirect(url_for("auth.login"))

        # Re-check against the database on every request, not just at login:
        # a deleted user must be signed out immediately, and a role change
        # (promote or demote) must take effect on the very next request,
        # not only the next time they sign in.
        from app.db import get_session as get_db_session
        from app.models.user import User

        user = get_db_session().get(User, session["user_id"])
        if user is None:
            session.clear()
            return redirect(url_for("auth.login"))
        session["role"] = user.role
        return view(*args, **kwargs)

    return wrapped


def admin_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if session.get("role") != "admin":
            abort(403)
        return view(*args, **kwargs)

    return wrapped
