# Runtime image for the Python MVC app. No build tools, runs as a non-root user.
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /srv

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app ./app

RUN useradd --create-home --uid 10001 appuser
USER 10001

EXPOSE 8000

# Two workers suit 1 vCPU. Uploads are processed in memory, so no shared disk is needed.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--timeout", "120", "--access-logfile", "-", "app:create_app()"]
