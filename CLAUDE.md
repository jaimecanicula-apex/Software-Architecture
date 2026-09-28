# CLAUDE.md

This repository holds APEX **golden templates**: approved, parameterized Terraform starting points that any team can copy to build Azure infrastructure without redesigning it. Each template is self-contained. Some templates also ship example site content that they deploy.

The repository starts with three static-website templates. Standalone templates for virtual networks and virtual machines will be added next. See [GOLDEN-TEMPLATES.md](GOLDEN-TEMPLATES.md) for the catalogue and for what is still needed before a template is published.

## Layout

```
infrastructure/                  One folder per golden template (Terraform)
  <template-name>/
content/                         Example site content, one folder per template that deploys content
  <template-name>/               Same name as the template that deploys it
.github/workflows/               GitHub Actions delivery pipelines (GitHub requires this location)
GOLDEN-TEMPLATES.md              Template catalogue and roadmap
PRODUCT.md                       Product and design context for the example sites
```

Current templates:

| Template | Infrastructure | Example content |
| --- | --- | --- |
| Public static website | `infrastructure/publicly-accessible-static-website/` | `content/publicly-accessible-static-website/` |
| Public static website, sign-in required | `infrastructure/public-signin-static-website/` | `content/public-signin-static-website/` |
| Private (internal) static website | `infrastructure/privately-accessible-static-website/` | `content/privately-accessible-static-website/` |
| Private (internal) container app | `infrastructure/privately-accessible-container-app/` | `content/python-mvc-app/` |
| Private (internal) container app with database and storage | `infrastructure/privately-accessible-container-app-with-database-and-storage/` | `content/python-crud-app/` |

## Naming conventions

- **Template folders:** kebab-case and named for what the template deploys, not for a client or project. Examples: `virtual-network`, `virtual-machine`, `publicly-accessible-static-website`.
- **Content folders:** static sites use `content/<template-name>/`, with exactly the same name as the template that deploys them. Everything in a static-site folder is uploaded as-is, so keep pipelines, docs and other non-site files out of it. Application source code that is built into a container image is named for what it is, `content/<language>-<pattern>-app/` (for example `content/python-mvc-app/`), because any container template can run it. Only templates that deploy something have content.
- **Azure resources:** `<type>-<workload>-<environment>-<region>-<instance>`, using Cloud Adoption Framework abbreviations, for example `rg-sws-dev-weu-001`. Each template's `modules/naming` module computes these names. Reuse that module; don't hand-write names.
- **Environments:** `dev`, `qa`, `uat`, `prod`.
- **Files:** Terraform uses the standard `main.tf`, `variables.tf`, `outputs.tf` and `versions.tf` split. Documentation uses `README.md` for how to use a template and `ARCHITECTURE.md` for its C4 model.

## Template anatomy

Every template in `infrastructure/` follows the same shape. New templates such as the virtual network and virtual machine ones must follow it too:

```
infrastructure/<template-name>/
  README.md                      How to use it: design decisions, cost estimate, first-time setup, deploy, outputs
  ARCHITECTURE.md                C4 model (context, containers, components) in Mermaid
  c4-context.drawio              Required: C4 level 1 in draw.io
  c4-containers.drawio           Required: C4 level 2 in draw.io
  *.drawio                       Optional extra diagrams; *-lucidchart.drawio copies import cleanly into Lucidchart
  bootstrap/                     One-time Terraform remote-state storage (local state)
  modules/<module>/              Reusable modules: no provider or backend blocks
  stacks/<stack>/                Root module: composes the modules, one stack for all environments
    tests/*.tftest.hcl           terraform test suites with mocked providers
  environments/<env>/
    terraform.tfvars             All environment-specific settings
    backend.hcl                  Where that environment's state lives
  scripts/tf.sh, tf.ps1          Wrapper: picks the environment, isolates TF_DATA_DIR per environment
  pipelines/                     Azure DevOps pipelines for this template
  .gitignore
```

Module sources are relative paths inside the template (`../../modules/<name>`). Templates must not reference each other's files, so any one of them can be copied out on its own.

## Commands

Run these from the repository root. `<t>` is a template folder name, for example `publicly-accessible-static-website`, and `<stack>` is the folder under its `stacks/` (`static-website` or `container-app`).

```sh
# Format and validate (no Azure access needed)
terraform fmt -recursive infrastructure/<t>
terraform -chdir=infrastructure/<t>/stacks/<stack> init -backend=false
terraform -chdir=infrastructure/<t>/stacks/<stack> validate

# Tests (mocked providers, no Azure access needed)
cd infrastructure/<t>/stacks/<stack> && terraform test -var-file=../../environments/dev/terraform.tfvars

# Deploy one environment (needs az login and a filled-in environments/<env>/)
./infrastructure/<t>/scripts/tf.sh dev init|plan|apply
./infrastructure/<t>/scripts/tf.ps1 -Environment dev -Command plan      # PowerShell
```

Nothing has been planned or applied against Azure yet. Only `terraform validate` and `terraform test` have passed.

The Python app in `content/python-mvc-app/` has its own tests: `pip install -r requirements-dev.txt && pytest` in that folder.

## Rules

- **Parameterize everything that varies:** subscription, tenant, region, SKUs, address ranges, group IDs, thresholds, tags. These values belong in `environments/<env>/terraform.tfvars`, never in modules or stacks.
- **Region, zones and subnets are parameters.**
  - **Region:** `location` is required in every stack and in `bootstrap/`, with no default, and set in each environment's `terraform.tfvars`. Validate it where a service only exists in some regions.
  - **Availability zones:** every resource that supports zone redundancy exposes it as a variable (for example `zone_redundancy_enabled`), off in dev and qa and on in uat and prod unless there is a reason not to. Validate the combinations a service refuses, such as zone redundancy on a SKU that lacks it. Where zone redundancy needs more than one instance to help, set that too or add a `check` that warns.
  - **Storage redundancy:** a variable, never hard-coded; the Terraform state storage defaults to GZRS.
  - **Subnets:** address prefixes come from tfvars (the IP plan); subnet and NSG names come from the naming module.
  - **Not applicable:** when a template has nothing zonal (global services such as Front Door or Static Web Apps), its README's Design decisions table says so in an "Availability zones" row, with the trade-off.
- **Every environment gets its own subscription and state.** Never change the `key` in an existing `backend.hcl`: that key is where the environment's state already lives.
- **Every design decision states its reason and its trade-off.** Each template's `README.md` has a `## Design decisions` table with the columns Concern, Decision, Why and Trade-off, and the "Why pick this design, and its trade-offs" panel in `c4-containers.drawio` gives both for every choice. A decision without a trade-off hasn't been thought through yet.
- **Every template states its cost with numbers.** Its `README.md` has a `## Cost estimate` section priced from the Azure pricing calculator's data (the [Azure Retail Prices API](https://prices.azure.com/api/retail/prices)), per environment, with the region, retrieval date, unit prices, fixed monthly totals, traffic-driven costs, a comparison against the budgets in tfvars, and any meter still to confirm. The "Cost:" line in the diagram's "What to keep in mind" panel quotes the totals. Refresh the prices when a template changes.
- **Every template ships draw.io C4 diagrams:** `c4-context.drawio` and `c4-containers.drawio` next to its `ARCHITECTURE.md`, kept in step with it. Generate and check them with the `c4-drawio` skill (`.claude/skills/c4-drawio/`) whenever a template is added or its architecture changes.
- **Governance is part of every template:** mandatory governance tags, delete locks in uat and prod, budgets, least-privilege viewer and operator roles, and monitoring that cannot be turned off in prod.
- **Pin provider versions and commit `.terraform.lock.hcl`.**
- **Keep templates and example content generic.** Never put client or customer names in `infrastructure/`, `content/` or `PRODUCT.md`.
- **Moving or renaming anything:** update the paths in `.github/workflows/`, each template's `pipelines/`, its `README.md` and `ARCHITECTURE.md`, and `.impeccable/`.
- **Azure DevOps pipeline definitions point at a YAML path.** When a pipeline file moves, update the path in Azure DevOps too.
- **The example sites are build-free:** plain HTML, CSS and JavaScript with no build step. Design context for them is in `PRODUCT.md`.
