"""Converts an uploaded CSV file with a template. Everything happens in memory:
the upload is never written to disk and nothing is kept after the response."""

import csv
import io
import json
from dataclasses import dataclass

from app.models.conversion_template import ConversionTemplate

OUTPUT_FORMATS = {"csv": "text/csv", "json": "application/json"}


class ConversionError(ValueError):
    """The upload cannot be converted; the message is safe to show to the user."""


@dataclass(frozen=True)
class ConversionResult:
    content: bytes
    media_type: str
    file_name: str
    row_count: int


def convert(file_bytes: bytes, source_file_name: str, template: ConversionTemplate, output_format: str) -> ConversionResult:
    if output_format not in OUTPUT_FORMATS:
        raise ConversionError(f"Unsupported output format: {output_format}.")

    try:
        text = file_bytes.decode("utf-8-sig")
    except UnicodeDecodeError as error:
        raise ConversionError("The file is not UTF-8 text.") from error

    reader = csv.DictReader(io.StringIO(text))
    if not reader.fieldnames:
        raise ConversionError("The file has no header row.")

    column_mapping = template.column_mapping or {column: column for column in reader.fieldnames}
    missing_columns = [column for column in column_mapping if column not in reader.fieldnames]
    if missing_columns:
        raise ConversionError(f"Missing columns for template '{template.name}': {', '.join(missing_columns)}.")

    output_rows = [{output: row[source] for source, output in column_mapping.items()} for row in reader]
    output_columns = list(column_mapping.values())
    base_name = source_file_name.rsplit(".", 1)[0] or "output"

    if output_format == "json":
        content = json.dumps(output_rows, indent=2, ensure_ascii=False).encode("utf-8")
    else:
        buffer = io.StringIO()
        writer = csv.DictWriter(buffer, fieldnames=output_columns, lineterminator="\n")
        writer.writeheader()
        writer.writerows(output_rows)
        content = buffer.getvalue().encode("utf-8")

    return ConversionResult(
        content=content,
        media_type=OUTPUT_FORMATS[output_format],
        file_name=f"{base_name}-{template.template_id}.{output_format}",
        row_count=len(output_rows),
    )
