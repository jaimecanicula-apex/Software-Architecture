"""Health endpoint for the Container Apps liveness and readiness probes."""

from flask import Blueprint

health_blueprint = Blueprint("health", __name__)


@health_blueprint.get("/healthz")
def health():
    return {"status": "ok"}
