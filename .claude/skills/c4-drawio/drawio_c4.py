"""Generate a C4 diagram as a .drawio file from a small JSON spec.

    python drawio_c4.py spec.json out.drawio

The output matches the house style of the existing golden-template diagrams:
system in focus in red, external systems dashed grey, containers as white
cards with an Azure icon, resource groups and VNets as shaded zones. Icons are
embedded as data URIs, so the file is self-contained and can be copied with
its template. See SKILL.md for the spec format.
"""

import base64
import json
import sys
import xml.etree.ElementTree as ET
from html import escape
from pathlib import Path

ICONS = Path(__file__).resolve().parent / "icons"

TEXT = "#1c1c1c"
MUTED = "#5c5c5c"
ACCENT = "#b8321f"

CARD = "rounded=1;absoluteArcSize=1;whiteSpace=wrap;html=1;fontColor=#1c1c1c;fontSize=12;verticalAlign=top;"
STYLES = {
    # The context view uses the container view's look: same red card, grey zone and arrows.
    "system": CARD + f"arcSize=8;fillColor=#fbeeeb;strokeColor={ACCENT};strokeWidth=2;spacingTop=44;",
    "external": CARD + "arcSize=12;fillColor=#f7f6f4;strokeColor=#8a8781;dashed=1;dashPattern=5 4;spacingTop=37;",
    "container": CARD + "arcSize=8;fillColor=#ffffff;strokeColor=#c4c4d6;strokeWidth=1;spacingTop=40;",
    "focus": CARD + f"arcSize=8;fillColor=#fbeeeb;strokeColor={ACCENT};strokeWidth=2;spacingTop=40;",
    "person": "shape=image;html=1;verticalLabelPosition=bottom;verticalAlign=top;labelPosition=center;align=center;aspect=fixed;imageAspect=0;fontSize=12;fontColor=#1c1c1c;spacingTop=6;",
    "boundary": "rounded=1;absoluteArcSize=1;arcSize=10;html=1;fillColor=#e6e6ea;strokeColor=#a9a9b4;strokeWidth=1;fontColor=#ffffff;fontSize=10;align=left;verticalAlign=top;spacingLeft=10;spacingTop=8;labelBackgroundColor=#1c1c1c;",
    "rg": "rounded=1;absoluteArcSize=1;arcSize=10;html=1;fillColor=#e6e6ea;strokeColor=#a9a9b4;strokeWidth=1;fontColor=#ffffff;fontSize=10;align=left;verticalAlign=top;spacingLeft=10;spacingTop=8;labelBackgroundColor=#1c1c1c;",
    "vnet": "rounded=1;absoluteArcSize=1;arcSize=10;html=1;fillColor=#9c9cf2;strokeColor=#7a7ad6;strokeWidth=1;fontColor=#ffffff;fontSize=10;align=left;verticalAlign=top;spacingLeft=10;spacingTop=8;labelBackgroundColor=#1c1c1c;",
    "zone": "rounded=1;absoluteArcSize=1;arcSize=12;html=1;fillColor=#f7f7ff;strokeColor=#b9b9e6;dashed=1;dashPattern=4 4;fontColor=#1c1c1c;fontSize=12;align=left;verticalAlign=top;spacing=12;",
}
EDGE = {
    # Same stroke, arrowhead and label as the orthogonal style, drawn as direct lines (context view).
    "straight": "html=1;rounded=0;edgeStyle=none;endFill=1;strokeColor=#3f3f52;strokeWidth=1;fontSize=10;fontColor=#1c1c1c;labelBackgroundColor=#ffffff;endArrow=classic;endSize=6;",
    "orthogonal": "html=1;rounded=0;edgeStyle=orthogonalEdgeStyle;endFill=1;strokeColor=#3f3f52;strokeWidth=1;fontSize=10;fontColor=#1c1c1c;labelBackgroundColor=#ffffff;endArrow=classic;endSize=6;jettySize=auto;",
}
DEFAULT_SIZE = {"person": (44, 44), "system": (240, 140), "external": (200, 80), "container": (220, 100), "focus": (220, 100)}
GROUPS = {"boundary", "rg", "vnet", "zone"}


def icon_uri(name: str) -> str:
    data = base64.b64encode((ICONS / f"{name}.svg").read_bytes()).decode()
    return f"data:image/svg+xml,{data}"


def lines(text: str) -> str:
    return "<br>".join(escape(part) for part in text.split("\n"))


def card_label(node: dict) -> str:
    html = f'<b style="font-size:14px">{escape(node["label"])}</b>'
    if node.get("text"):
        html += f'<br><span style="color:{MUTED}">{lines(node["text"])}</span>'
    if node.get("tech"):
        html += f'<br><i style="color:{ACCENT}">[{escape(node["tech"])}]</i>'
    return html


def note_label(node: dict) -> str:
    """Title, then one line per item: "## Heading", ["Bold lead:", "text"], or plain text shown as a bullet."""
    parts = [f'<b style="font-size:14px">{escape(node["label"])}</b><br>']
    for item in node["items"]:
        if isinstance(item, list):
            parts.append(f"<b>{escape(item[0])}</b> {escape(item[1])}")
        elif item.startswith("## "):
            parts.append(f"<br><b>{escape(item[3:])}</b>")
        else:
            parts.append(f"• {escape(item)}")
    return "<br>".join(parts)


def build(spec: dict) -> ET.ElementTree:
    width, height = spec.get("width", 1000), spec.get("height", 650)
    mxfile = ET.Element("mxfile", host="drawio", type="device")
    diagram = ET.SubElement(mxfile, "diagram", name=spec["name"], id=spec["id"])
    model = ET.SubElement(diagram, "mxGraphModel", dx=str(width), dy=str(height), grid="1", gridSize="10", guides="1",
                          page="1", pageScale="1", pageWidth=str(width), pageHeight=str(height), math="0", shadow="0")
    root = ET.SubElement(model, "root")
    ET.SubElement(root, "mxCell", id="0")
    ET.SubElement(root, "mxCell", id="1", parent="0")

    def cell(cell_id, value, style, x, y, w, h, parent="1"):
        element = ET.SubElement(root, "mxCell", id=cell_id, parent=parent, value=value, style=style, vertex="1")
        ET.SubElement(element, "mxGeometry", x=str(x), y=str(y), width=str(w), height=str(h), attrib={"as": "geometry"})

    title = f'<b style="font-size:20px">{escape(spec["title"])}</b><br><span style="font-size:14px;color:{ACCENT}">{escape(spec["subtitle"])}</span>'
    cell("title", title, f"text;html=1;whiteSpace=wrap;align=left;verticalAlign=top;fontColor={TEXT};strokeColor=none;fillColor=none;", 20, 10, width - 40, 50)
    if spec.get("description"):
        cell("description", escape(spec["description"]), f"text;html=1;whiteSpace=wrap;align=left;verticalAlign=top;fontSize=12;fontColor={MUTED};strokeColor=none;fillColor=none;", 20, 62, width - 40, 60)

    ids = set()
    # Groups first, so they sit behind the cards they contain.
    for node in sorted(spec["nodes"], key=lambda n: n["kind"] not in GROUPS):
        kind, node_id = node["kind"], node["id"]
        if node_id in ids:
            raise ValueError(f"duplicate node id: {node_id}")
        ids.add(node_id)
        w, h = node.get("w"), node.get("h")
        if w is None or h is None:
            w, h = DEFAULT_SIZE[kind]
        x, y = node["x"], node["y"]

        if kind == "note":
            cell(node_id, note_label(node), STYLES["zone"] + "whiteSpace=wrap;", x, y, w, h)
        elif kind in GROUPS:
            label = escape(node["label"])
            cell(node_id, f" {label} " if kind in ("rg", "vnet", "boundary") else label, STYLES[kind], x, y, w, h)
        elif kind == "person":
            cell(node_id, card_label(node), STYLES["person"] + f"image={icon_uri(node.get('icon', 'users'))};", x, y, w, h)
        else:
            cell(node_id, card_label(node), STYLES[kind], x, y, w, h)
            if node.get("icon"):
                size = node.get("icon_size") or (24 if kind == "external" else 28)  # a number, or [w, h] for a wide wordmark
                iw, ih = size if isinstance(size, list) else (size, size)
                top = {"system": 10, "external": 11}.get(kind, 8)
                cell(f"{node_id}-icon", "", f"shape=image;html=1;aspect=fixed;imageAspect=0;image={icon_uri(node['icon'])};",
                     (w - iw) / 2, top + (28 - ih) / 2 if ih < 24 else top, iw, ih, parent=node_id)

    edge_style = EDGE[spec.get("edges_style", "orthogonal")]
    for index, edge in enumerate(spec.get("edges", [])):
        for end in (edge["from"], edge["to"]):
            if end not in ids:
                raise ValueError(f"edge {index} refers to unknown node: {end}")
        style = edge_style
        if edge.get("exit"):
            style += f"exitX={edge['exit'][0]};exitY={edge['exit'][1]};exitPerimeter=0;"
        if edge.get("entry"):
            style += f"entryX={edge['entry'][0]};entryY={edge['entry'][1]};entryPerimeter=0;"
        if edge.get("dashed"):
            style += "dashed=1;dashPattern=5 4;"
        element = ET.SubElement(root, "mxCell", id=f"e{index}", parent="1", value=escape(edge.get("label", "")),
                                style=style, edge="1", source=edge["from"], target=edge["to"])
        ET.SubElement(element, "mxGeometry", relative="1", attrib={"as": "geometry"})

    tree = ET.ElementTree(mxfile)
    ET.indent(tree)
    return tree


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python drawio_c4.py spec.json out.drawio")
    spec = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    build(spec).write(sys.argv[2], encoding="utf-8", xml_declaration=True)
    print(f"wrote {sys.argv[2]}")


if __name__ == "__main__":
    main()
