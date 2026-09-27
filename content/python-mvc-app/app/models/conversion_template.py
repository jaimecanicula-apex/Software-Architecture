"""Conversion templates: which source columns to keep and what to call them.

Templates are configuration, not business data. They ship inside the image
(app/config/conversion_templates.json) and change through pull requests, so the
app needs no database or persistent storage.
"""

import json
from dataclasses import dataclass
from pathlib import Path

TEMPLATES_FILE = Path(__file__).resolve().parent.parent / "config" / "conversion_templates.json"


@dataclass(frozen=True)
class ConversionTemplate:
    template_id: str
    name: str
    description: str
    # Source column name -> output column name. Empty means keep every column as-is.
    column_mapping: dict[str, str]


def load_templates(templates_file: Path = TEMPLATES_FILE) -> dict[str, ConversionTemplate]:
    raw_templates = json.loads(templates_file.read_text(encoding="utf-8"))
    return {
        entry["id"]: ConversionTemplate(
            template_id=entry["id"],
            name=entry["name"],
            description=entry["description"],
            column_mapping=entry.get("column_mapping", {}),
        )
        for entry in raw_templates
    }
