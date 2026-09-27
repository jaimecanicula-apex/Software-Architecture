# Python MVC app (example)

A small Flask application in Model-View-Controller style. It is the example workload for [infrastructure/privately-accessible-container-app](../../infrastructure/privately-accessible-container-app). Replace it with your own application: the infrastructure only needs a container image that listens on port 8000 and answers `GET /healthz`.

What it does: a user uploads a CSV file, picks a conversion template, and downloads the result as CSV or JSON.

## Structure

```
app/
  __init__.py                  Application factory: config, logging, controllers
  models/                      Model: conversion logic, templates, signed-in user
  views/                       View: Jinja templates
  controllers/                 Controller: HTTP routes (Flask blueprints)
  config/conversion_templates.json   Templates, shipped in the image
  static/                      CSS
tests/                         pytest suite
Dockerfile                     Runtime image (python:3.13-slim, non-root, gunicorn on port 8000)
```

## Design choices

| Concern | How the app handles it |
| --- | --- |
| Sign-in | None in the app. Container Apps built-in authentication signs users in with Entra ID and passes the name in `X-MS-CLIENT-PRINCIPAL-NAME` |
| Uploaded files | Read in memory, never written to disk, discarded after the response. Size limit `APP_MAX_UPLOAD_MB` (default 10), `.csv` only |
| Output | Streamed back in the same response as a download (`Cache-Control: no-store`). Nothing is stored |
| Templates and config | `app/config/conversion_templates.json`, versioned in git and baked into the image. No database or storage account |
| Logging | Standard output, collected by Container Apps into Log Analytics. Application Insights too when `APPLICATIONINSIGHTS_CONNECTION_STRING` is set. File contents are never logged |

## Run locally

```sh
python -m venv .venv
.venv/Scripts/activate            # Windows; use .venv/bin/activate on Linux or macOS
pip install -r requirements-dev.txt
pytest
flask --app app run               # http://127.0.0.1:5000, signed in as "local-developer"
```

With Docker:

```sh
docker build -t python-mvc-app .
docker run --rm -p 8000:8000 python-mvc-app
```

## Settings

| Environment variable | Default | Purpose |
| --- | --- | --- |
| `APP_MAX_UPLOAD_MB` | `10` | Largest accepted upload |
| `APP_LOG_LEVEL` | `INFO` | Log level |
| `APP_SECRET_KEY` | random per process | Flask secret key; only matters if you add sessions |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | not set | Sends logs and requests to Application Insights |
