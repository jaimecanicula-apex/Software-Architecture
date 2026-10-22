---
name: c4-drawio
description: Generate the draw.io C4 diagrams (system context and containers) that every template in infrastructure/ must ship. Use whenever a template is added or its architecture changes, when writing or updating an ARCHITECTURE.md, or when asked for draw.io, diagrams.net or C4 diagrams.
---

# C4 diagrams in draw.io

Every template in `infrastructure/<template>/` ships these two files next to its `ARCHITECTURE.md`:

| File | Diagram id | Content |
| --- | --- | --- |
| `c4-context.drawio` | `c4-context` | C4 level 1: the system in focus, its people, and the external systems it talks to |
| `c4-containers.drawio` | `c4-containers` | C4 level 2: the Azure resources of one environment, grouped by resource group and VNet |

They show the same model as the Mermaid diagrams in `ARCHITECTURE.md`. When the architecture changes, update both. Other diagrams (`c4-terraform-components.drawio`, `sequence.drawio`, `*-lucidchart.drawio`) are welcome but optional.

## Workflow

1. **Model first.** Read the template's Terraform (stack, modules, tfvars), its pipeline and any content it deploys. If `ARCHITECTURE.md` is missing or stale, write it first (the `c4-codebase-architecture` skill covers that). Every box and arrow must trace back to code.
2. **Write a spec** for each diagram as JSON in the scratchpad, not in the repository. Start from `examples/private-container-app-context.json` and `examples/private-container-app-containers.json`.
3. **Generate:**
   ```sh
   python .claude/skills/c4-drawio/drawio_c4.py <scratch>/context.json infrastructure/<template>/c4-context.drawio
   python .claude/skills/c4-drawio/drawio_c4.py <scratch>/containers.json infrastructure/<template>/c4-containers.drawio
   ```
4. **Look at it.** Render each file and read the PNG:
   ```sh
   python .claude/skills/c4-drawio/render_png.py infrastructure/<template>/c4-containers.drawio <scratch>/containers.png 2150 1250
   ```
   Fix any edge that crosses a box or a label, any overlapping labels, and any clipped text by moving nodes or setting `exit`/`entry`, then regenerate. Repeat until clean. Never commit the PNG.
5. **Link them** from the top of `ARCHITECTURE.md` and from the folder layout in the template's `README.md`.

Once committed, the `.drawio` file is the source of truth: people edit it in draw.io. Regenerate from a spec only when the change is large enough to justify redoing manual touch-ups.

## Spec format

```json
{
  "id": "c4-containers",
  "name": "C4 L2 Containers - <short template name>",
  "title": "<Template display name>",
  "subtitle": "C4 level 2: Containers",
  "description": "One paragraph: what the diagram shows, in plain words.",
  "width": 1700, "height": 960,
  "edges_style": "orthogonal",
  "nodes": [ ... ],
  "edges": [ ... ]
}
```

- `edges_style`: `straight` for context diagrams (direct lines), `orthogonal` for container diagrams. Both use the same thin dark-grey stroke, arrowhead and 10 px labels.
- Title, description and all labels are plain text; the generator escapes them. Use `\n` for a line break inside `text`.

**Nodes:** `{"id", "kind", "x", "y", "w", "h", "label", "text", "tech", "icon"}`. Coordinates are absolute page coordinates. `w`/`h` are optional for cards.

| kind | Use for | Default size |
| --- | --- | --- |
| `person` | A human actor (icon with label below) | 44 × 44 |
| `system` | The system in focus on a context diagram: the same red card as `focus` | 240 × 140 |
| `external` | Anything outside the boundary: Entra ID, hub network, DevOps, email (dashed grey) | 200 × 80 |
| `container` | An Azure resource or runnable unit inside the boundary (white card) | 220 × 100 |
| `focus` | The main workload on a container diagram (red card) | 220 × 100 |
| `boundary` | The zone around the system on a context diagram: the same grey zone and black label pill as `rg` | set `w`, `h` |
| `rg` | Resource group zone (grey) | set `w`, `h` |
| `vnet` | VNet or subnet zone (violet) | set `w`, `h` |
| `zone` | Any other grouping, such as monitoring (dashed lilac) | set `w`, `h` |
| `note` | A text panel under the diagram (see below) | set `w`, `h` |

`tech` renders as `[tech]` in red under the text. Give it on container cards (for example `Azure Container Registry`), and use `software system` on the context system.

**Icons** (`icon`, file name without `.svg`, from `icons/`): ai-foundry, ai-search, alerts, api-management, app-registration, application-gateway, application-insights, azure-devops, bastion, branch, builds, code, container-app, container-apps-environment, container-registry, cost-budgets, dataverse, dev-console, dns-zones, firewall, front-door, function-apps, groups, key-vault, kubernetes-services, log-analytics, managed-identity, monitor, network-security-group, oracle-database, power-apps, power-automate, private-endpoint, private-link, resource-group, service-bus, service-health, servicenow, sharepoint, signalr, static-web-app, storage-account, subnet, subscription, tag, users, virtual-machine, virtual-network, waf, web-test, workbook. To add one, copy it unmodified from the Microsoft Azure Public Service Icons set (or another Microsoft icon set that permits architecture diagrams) and record it in `icons/NOTICE.txt`. Third-party product logos such as `servicenow` and `sharepoint` identify the product only. A wide wordmark needs `"icon_size": [w, h]` on the node, for example `[100, 15]`.

**Note panels:** `{"id", "kind": "note", "x", "y", "w", "h", "label", "items": [...]}`. `label` is the panel title. Each item is one line: `["Bold lead:", "text"]` for a labelled fact, `"## Heading"` for a sub-heading, or plain text, which is shown as a bullet.

Every container diagram carries four panels below the diagram, in a 2 × 2 grid of 800-wide panels (x = 40 and 860):

1. **The key mechanism, technically**, titled "<Mechanism>: what they <do> and why" (for example "Health checks and alerts: what they watch and why"). Use labelled facts: what it probes or does, why this way, how, pass condition, result, alerts, and always a closing **Does not prove:** line.
2. **The same story in plain language** for non-engineers: `## What happens` and `## Why we do it this way`, each with 3 or 4 short bullets and no jargon.
3. **What to keep in mind:** labelled facts covering dependencies on other teams, weak links, access, limits and **Cost:**. The cost line gives monthly estimates in numbers, taken from the `## Cost estimate` section of the template's `README.md`.
4. **Why pick this design, and its trade-offs:** one labelled fact per decision, written as "X, not Y:" followed by the reason, then "Trade-off:" and what the choice costs or gives up. The same decisions, reasons and trade-offs appear in the `## Design decisions` table of the template's `README.md`.

Every statement must trace back to the Terraform, the pipeline or the deployed content. Size each panel to its text after rendering.

If the template also has a `*-lucidchart.drawio` copy, it must carry the same four panels in its plain-text style (`html=0`: a panel box holding a bold title cell and a body cell). Update both files together; a copy with fewer panels is out of date.

**Edges:** `{"from", "to", "label", "exit": [x, y], "entry": [x, y], "dashed": true}`. `exit` and `entry` are optional connection points on the node's outline as fractions (0 to 1) of its width and height. Use them to steer an edge around boxes. Every edge needs a short verb-phrase label.

## Layout rules

- **One visual language:** context and container diagrams share colours, card styles, zones, icons, fonts and arrows. Never style a context diagram differently from its container diagram.

- **Context:** people on the left (x = 68, y = 180 / 370 / 560), the system (240 × 150 at 380, 335) inside its boundary zone (400 × 320 at 300, 250), and external systems on the right (200 × 80 at x = 770, y = 150 / 290 / 430 / 570). Put a person who only talks to an external system (for example a release approver) next to that system. Page about 1000 × 700.
- **Containers:** people and the hub on the left, outside the resource group; Entra ID, the pipeline and other externals on the right or top; email or other notification targets at the bottom. Inside the resource group, use a grid with 220-wide cards and 50 px gaps (columns at x = 340, 610, 880, 1170), with the request path in the top row inside the VNet zone and monitoring and governance in the rows below. Leave a free cell wherever a vertical edge must pass.
- **Notes:** the four panels sit below everything else; set the page `height` to include them.
- Use real resource names from the naming module (for example `rg-<workload>-<env>-<region>-001`) and nothing client-specific.
