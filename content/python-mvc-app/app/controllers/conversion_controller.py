"""Upload a CSV, convert it with a template, and stream the result straight back."""

import logging

from flask import Blueprint, Response, render_template, request

from app.models.conversion import OUTPUT_FORMATS, ConversionError, convert
from app.models.conversion_template import load_templates
from app.models.current_user import current_user_name

ALLOWED_EXTENSIONS = {".csv"}

conversion_blueprint = Blueprint("conversion", __name__)
logger = logging.getLogger("app.conversion")
templates = load_templates()


@conversion_blueprint.get("/")
def show_form():
    return render_template(
        "index.html",
        templates=templates.values(),
        output_formats=OUTPUT_FORMATS,
        user_name=current_user_name(request),
    )


@conversion_blueprint.post("/convert")
def convert_upload():
    user_name = current_user_name(request)
    upload = request.files.get("file")
    template = templates.get(request.form.get("template_id", ""))
    output_format = request.form.get("output_format", "csv")

    if upload is None or not upload.filename:
        return show_error("Choose a file to convert.", user_name)
    if not any(upload.filename.lower().endswith(extension) for extension in ALLOWED_EXTENSIONS):
        return show_error("Only .csv files are accepted.", user_name)
    if template is None:
        return show_error("Choose a template.", user_name)

    try:
        result = convert(upload.read(), upload.filename, template, output_format)
    except ConversionError as error:
        return show_error(str(error), user_name)

    # Log who converted what, never the file contents.
    logger.info("conversion user=%s template=%s format=%s rows=%d", user_name, template.template_id, output_format, result.row_count)
    return Response(
        result.content,
        mimetype=result.media_type,
        headers={"Content-Disposition": f'attachment; filename="{result.file_name}"', "Cache-Control": "no-store"},
    )


def show_error(message: str, user_name: str):
    return render_template("error.html", message=message, user_name=user_name), 400
