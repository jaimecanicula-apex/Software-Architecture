"""Application factory: wires configuration, logging and the controllers together."""

import logging
import os

from flask import Flask, render_template

from app.controllers.conversion_controller import conversion_blueprint
from app.controllers.health_controller import health_blueprint

MEGABYTE = 1024 * 1024


def create_app(test_config: dict | None = None) -> Flask:
    app = Flask(__name__, template_folder="views")
    app.config.update(
        MAX_CONTENT_LENGTH=int(os.environ.get("APP_MAX_UPLOAD_MB", "10")) * MEGABYTE,
        SECRET_KEY=os.environ.get("APP_SECRET_KEY", os.urandom(32)),
    )
    if test_config:
        app.config.update(test_config)

    configure_logging()

    app.register_blueprint(conversion_blueprint)
    app.register_blueprint(health_blueprint)

    @app.errorhandler(413)
    def upload_too_large(_error):
        limit_mb = app.config["MAX_CONTENT_LENGTH"] // MEGABYTE
        return render_template("error.html", message=f"The file is larger than {limit_mb} MB."), 413

    return app


def configure_logging() -> None:
    """Log to stdout (collected by Container Apps) and, when configured, to Application Insights."""
    logging.basicConfig(level=os.environ.get("APP_LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(name)s %(message)s")
    if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
        from azure.monitor.opentelemetry import configure_azure_monitor

        configure_azure_monitor(logger_name="app")
