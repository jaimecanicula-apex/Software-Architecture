"""Admin-only user management: list, create, reset password, delete
(never yourself)."""
from flask import Blueprint, abort, redirect, render_template, request, session, url_for

from app.auth.security import admin_required, csrf_token, login_required, require_csrf
from app.db import get_session
from app.models.asset import Asset
from app.models.user import ROLE_ADMIN, ROLE_USER, User

admin_blueprint = Blueprint("admin", __name__, url_prefix="/admin")


@admin_blueprint.route("/users")
@login_required
@admin_required
def list_users():
    db = get_session()
    users = db.query(User).order_by(User.username).all()
    return render_template("admin/users.html", users=users, csrf_token=csrf_token(), error=None)


@admin_blueprint.route("/users/new", methods=["POST"])
@login_required
@admin_required
@require_csrf
def create_user():
    db = get_session()
    username = request.form.get("username", "").strip()
    password = request.form.get("password", "")
    role = request.form.get("role", ROLE_USER)
    if role not in (ROLE_ADMIN, ROLE_USER):
        abort(400)
    if not username or not password or db.query(User).filter_by(username=username).one_or_none():
        return redirect(url_for("admin.list_users"))
    user = User(username=username, role=role)
    user.set_password(password)
    db.add(user)
    db.commit()
    return redirect(url_for("admin.list_users"))


@admin_blueprint.route("/users/<int:user_id>/reset-password", methods=["POST"])
@login_required
@admin_required
@require_csrf
def reset_password(user_id: int):
    db = get_session()
    user = db.get(User, user_id)
    if user is None:
        abort(404)
    new_password = request.form.get("password", "")
    if new_password:
        user.set_password(new_password)
        user.failed_login_count = 0
        user.locked_until = None
        db.commit()
    return redirect(url_for("admin.list_users"))


@admin_blueprint.route("/users/<int:user_id>/delete", methods=["POST"])
@login_required
@admin_required
@require_csrf
def delete_user(user_id: int):
    if user_id == session["user_id"]:
        abort(400)
    db = get_session()
    user = db.get(User, user_id)
    if user is None:
        abort(404)

    owned_assets = db.query(Asset).filter_by(owner_user_id=user_id).count()
    if owned_assets:
        users = db.query(User).order_by(User.username).all()
        error = f"Cannot delete '{user.username}': it owns {owned_assets} asset(s). Delete or reassign them first."
        return render_template("admin/users.html", users=users, csrf_token=csrf_token(), error=error), 409

    db.delete(user)
    db.commit()
    return redirect(url_for("admin.list_users"))
