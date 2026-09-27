"""Render a .drawio file to PNG to check the layout by eye.

    python render_png.py diagram.drawio out.png [width height]

Loads the diagrams.net viewer script in headless Chrome or Edge. The diagram
itself is rendered locally; only the viewer script is downloaded. The PNG is a
check, not a deliverable: write it to a scratch folder, not the repository.
"""

import html
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

BROWSERS = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "google-chrome", "chromium", "microsoft-edge",
]


def find_browser() -> str:
    for candidate in BROWSERS:
        if Path(candidate).exists() or shutil.which(candidate):
            return candidate
    sys.exit("No Chrome or Edge found.")


def main() -> None:
    if len(sys.argv) not in (3, 5):
        sys.exit("usage: python render_png.py diagram.drawio out.png [width height]")
    source, out = Path(sys.argv[1]), Path(sys.argv[2]).resolve()
    width, height = (sys.argv[3], sys.argv[4]) if len(sys.argv) == 5 else ("2000", "1300")

    config = html.escape(json.dumps({"xml": source.read_text(encoding="utf-8"), "toolbar": "", "lightbox": False, "nav": False}))
    with tempfile.TemporaryDirectory() as scratch:
        page = Path(scratch) / "diagram.html"
        page.write_text(f'<!doctype html><body style="margin:0;background:#fff"><div class="mxgraph" data-mxgraph="{config}"></div>'
                        '<script src="https://viewer.diagrams.net/js/viewer-static.min.js"></script></body>', encoding="utf-8")
        subprocess.run([find_browser(), "--headless=new", "--disable-gpu", "--no-first-run", f"--user-data-dir={Path(scratch) / 'profile'}",
                        "--virtual-time-budget=15000", f"--window-size={width},{height}", f"--screenshot={out}", page.as_uri()], check=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
