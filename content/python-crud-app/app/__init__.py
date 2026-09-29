"""Application factory: wires configuration, the database, logging, seeding
and the controllers together."""
import logging
import os

from flask import Flask, abort, render_template, request, session

from app.controllers.admin_controller import admin_blueprint
from app.controllers.asset_controller import assets_blueprint
from app.controllers.auth_controller import auth_blueprint
from app.controllers.health_controller import health_blueprint
from app.db import remove_session
from app.seed import seed_users

MEGABYTE = 1024 * 1024


def create_app(test_config: dict | None = None) -> Flask:
    app = Flask(__name__, template_folder="views")
    app.config.update(
        MAX_CONTENT_LENGTH=int(os.environ.get("APP_MAX_UPLOAD_MB", "10")) * MEGABYTE,
        SECRET_KEY=os.environ.get("APP_SECRET_KEY") or os.urandom(32),
        SESSION_COOKIE_SECURE=os.environ.get("APP_ENV", "production") != "development",
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
    )
    if test_config:
        app.config.update(test_config)

    configure_logging()

    # seed_users() creates the schema too (inside its advisory lock — see
    # app/seed.py's docstring for why that beats a separate create_all()
    # here, ahead of the lock, when two workers boot at once).
    seed_users()

    app.register_blueprint(auth_blueprint)
    app.register_blueprint(assets_blueprint)
    app.register_blueprint(admin_blueprint)
    app.register_blueprint(health_blueprint)

    @app.before_request
    def require_platform_identity():
        # Container Apps built-in auth already refuses unauthenticated
        # requests before they reach the app; this header check is
        # defense-in-depth so the app never trusts network position alone.
        if app.config.get("TESTING") or os.environ.get("APP_ENV") == "development":
            return
        if request.path == "/healthz" or request.path.startswith("/static/"):
            return
        if not request.headers.get("X-MS-CLIENT-PRINCIPAL-NAME"):
            abort(401)

    @app.teardown_appcontext
    def _remove_session(_exc=None):
        remove_session()

    @app.errorhandler(413)
    def upload_too_large(_error):
        limit_mb = app.config["MAX_CONTENT_LENGTH"] // MEGABYTE
        return render_template("error.html", message=f"The file is larger than {limit_mb} MB."), 413

    @app.errorhandler(403)
    def forbidden(_error):
        return render_template("error.html", message="You don't have permission to do that."), 403

    @app.context_processor
    def inject_role():
        return {"current_role": session.get("role")}

    return app


def configure_logging() -> None:
    logging.basicConfig(level=os.environ.get("APP_LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(name)s %(message)s")
    if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
        from azure.monitor.opentelemetry import configure_azure_monitor

        configure_azure_monitor(logger_name="app")
