"""Login/logout for the app's own username/password layer — this sits
behind (not instead of) the Entra sign-in Container Apps enforces in front."""
import datetime as dt
import os

from flask import Blueprint, redirect, render_template, request, url_for

from app.auth.security import csrf_token, log_in, log_out, require_csrf
from app.db import get_session
from app.models.user import User
from app.timeutils import utcnow

auth_blueprint = Blueprint("auth", __name__)

MAX_FAILED_ATTEMPTS = int(os.environ.get("APP_MAX_FAILED_LOGINS", "5"))
LOCKOUT_MINUTES = int(os.environ.get("APP_LOCKOUT_MINUTES", "15"))


@auth_blueprint.route("/login", methods=["GET", "POST"])
@require_csrf
def login():
    if request.method == "GET":
        return render_template("login.html", csrf_token=csrf_token(), error=None)

    username = request.form.get("username", "").strip()
    password = request.form.get("password", "")
    db = get_session()
    user = db.query(User).filter_by(username=username).one_or_none()

    # Same error for "no such user" and "locked": don't tell an attacker which one it is.
    if user is None or user.is_locked():
        return render_template("login.html", csrf_token=csrf_token(), error="Invalid username or password."), 401

    if user.check_password(password):
        user.failed_login_count = 0
        user.locked_until = None
        db.commit()
        log_in(user)
        return redirect(url_for("assets.list_assets"))

    user.failed_login_count += 1
    if user.failed_login_count >= MAX_FAILED_ATTEMPTS:
        user.locked_until = utcnow() + dt.timedelta(minutes=LOCKOUT_MINUTES)
    db.commit()
    return render_template("login.html", csrf_token=csrf_token(), error="Invalid username or password."), 401


@auth_blueprint.route("/logout", methods=["POST"])
@require_csrf
def logout():
    log_out()
    return redirect(url_for("auth.login"))
