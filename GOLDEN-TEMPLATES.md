# Golden templates: roadmap

This repository collects **APEX golden templates**: approved, versioned starting points that any team can use to build Azure infrastructure without redesigning it. Each template lives in `infrastructure/<template-name>/`. The example site content that a template deploys lives in `content/<template-name>/`. [CLAUDE.md](CLAUDE.md) describes the layout and conventions.

All current templates are proofs of concept.

| Template | Folder | Example content | Use when |
| --- | --- | --- | --- |
| Publicly accessible static website | `infrastructure/publicly-accessible-static-website/` | `content/publicly-accessible-static-website/` | The audience is **external**: clients or users outside APEX |
| Public sign-in static website | `infrastructure/public-signin-static-website/` | `content/public-signin-static-website/` | The audience is **approved external people** who must sign in with Entra ID (B2B guests of the APEX tenant) before seeing any page |
| Privately accessible static website | `infrastructure/privately-accessible-static-website/` | `content/privately-accessible-static-website/` | The audience is **internal**: anyone signing in with APEX Entra ID (colleagues, APEX companies, contractors). No internet exposure. |
| Privately accessible container app | `infrastructure/privately-accessible-container-app/` | `content/python-mvc-app/` | A containerised backend application (for example Python) for **internal users** in assigned Entra groups, reached on an internal URL from the corporate network |
| Privately accessible container app with database and storage | `infrastructure/privately-accessible-container-app-with-database-and-storage/` | `content/python-crud-app/` | A containerised backend with its own PostgreSQL database, Blob image storage and app-level username/password login, for **internal users** in assigned Entra groups |
| Privately accessible static website with storage | `infrastructure/privately-accessible-static-website-with-storage/` | `content/privately-accessible-static-website-with-storage/` | The audience is **internal** and needs a **shared file library**: signed-in users list, upload, download and delete files in private Blob storage, using their own Entra token. No database and no server code |
| Privately accessible static website (Bicep) | `infrastructure/privately-accessible-static-website-bicep/` | `content/privately-accessible-static-website/` | The audience is **internal**: anyone signing in with APEX Entra ID. No internet exposure. Deployed with Bicep (deployment stack per environment) and Azure DevOps infrastructure and content pipelines. Includes recommended tags (business unit, criticality, project code) |
| Privately accessible static website with storage (Bicep) | `infrastructure/privately-accessible-static-website-with-storage-bicep/` | `content/privately-accessible-static-website-with-storage/` | The same design as above, deployed with Bicep instead of Terraform |
| Publicly accessible static website with document API (Bicep) | `infrastructure/publicly-accessible-static-website-with-document-api-bicep/` | None yet | The audience is the **public**. Front Door Premium + WAF in front of a Static Web App and a private Function API (Private Link, public access off) that publishes approved PDFs from private Blob storage with its managed identity. Bicep first (deployment stack per environment); the Terraform twin is still to be written. Nothing built or deployed yet: the Bicep CLI was not available |

### Planned

| Template | Folder | Purpose |
| --- | --- | --- |
| Publicly accessible container app | `infrastructure/publicly-accessible-container-app/` | The same app published to the internet through Front Door Premium and WAF, still behind Entra sign-in |
| Virtual network | `infrastructure/virtual-network/` | A standalone VNet with subnets, NSGs and routing, deployed on its own |
| Virtual machine | `infrastructure/virtual-machine/` | Standalone Azure VMs deployed into an existing subnet |

## Already in place

- **Parameterized:** every environment-specific value comes from `terraform.tfvars`: subscription, tenant, region, SKUs, network ranges, groups, thresholds and tags. Nothing is hard-coded to one client.
- **Structured:** reusable modules sit behind one root stack per design, with separate settings and state per environment (dev, qa, uat, prod).
- **Governed:** mandatory governance tags, naming convention, delete locks, budgets and least-privilege viewer and operator roles.
- **Monitored:** all three designs include full monitoring by default. One switch, `enable_monitoring`, turns all of it off per environment (for example in dev to save cost); it cannot be off in prod.
- **Pinned:** provider versions are pinned and lock files are committed.
- **Resilient by parameter:** region (`location`) is required per environment; availability-zone redundancy is a variable wherever the service supports it (on in uat and prod); the Terraform state storage is GZRS by default; subnet prefixes come from tfvars and subnet names from the naming module.
- **Diagrammed:** every template ships its C4 system context and container diagrams in draw.io (`c4-context.drawio`, `c4-containers.drawio`) alongside the Mermaid model in `ARCHITECTURE.md`.

## Still needed before publishing as golden templates

1. **Versioned module source.** Move `modules/` into a module registry (a private Terraform registry, or a Git repo with semver tags). Stacks then reference `source = "<registry>/static-web-app/azurerm" version = "~> 1.0"` instead of relative paths.
2. **One shared module library.** The three designs currently carry their own copies of `naming`, `static-web-app`, `monitoring`, `front-door`, `front-door-waf` and `entra-app-auth`. Merge them into one versioned library, where the private variant's extra inputs (`public_network_access_enabled`, private ingestion, custom availability tests) are ordinary options.
3. **Landing-zone integration.** In the private design, replace the self-created Private DNS zones with the platform team's central zones, and accept an existing spoke subnet as an input.
4. **Policy alignment.** Check all three designs against the APEX Azure Policy assignments (allowed regions and SKUs, private endpoints, diagnostic settings, tags) and remove anything the policies already enforce.
5. **Tests.** Add `terraform test` suites and a CI pipeline: `fmt`, `validate`, `tflint`, `checkov` or `trivy`, and a plan per environment on every pull request.
6. **Infrastructure pipeline.** Add plan on pull request and apply per environment with approval gates, using OIDC (workload identity federation) instead of secrets.
7. **Documentation contract.** For each template, document its inputs, outputs, supported regions, cost baseline, RACI and support model, generated with `terraform-docs`.
8. **Release process.** Use semver releases, a changelog, and a deprecation policy, so consuming teams can upgrade on their own schedule.
9. **Ownership.** Name the owning team, the review board that approves changes, and the review cadence.
