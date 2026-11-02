# Publicly accessible static website with document API (Bicep): design

Date: 2026-10-30
Status: awaiting review
Path: architectural (new golden template)

## Purpose

A reference golden template, written in Bicep first, for a public, read-only website that publishes approved documents (PDFs). It is derived from a reviewed production design: Azure Front Door Premium with WAF in front of a Static Web App and a private Function API that reads a private Blob container through its managed identity. No client names appear anywhere in the template.

Success looks like: a team copies the folder, fills in `environments/<env>/main.bicepparam`, and deploys a working public document site without redesigning the architecture. The Terraform twin follows later and must match it resource for resource.

## Scope

In scope:
- `infrastructure/publicly-accessible-static-website-with-document-api-bicep/` with the full template anatomy from CLAUDE.md (Bicep variant).
- Environments `dev`, `qa`, `uat`, `prod`.
- README (design decisions, cost estimate), ARCHITECTURE.md (Mermaid C4), `c4-context.drawio`, `c4-containers.drawio`, and `*-lucidchart.drawio` copies for Lucidchart import.
- Catalogue rows in CLAUDE.md and GOLDEN-TEMPLATES.md.

Out of scope:
- The Terraform twin.
- Example application content (a later `content/node-document-api/`, named for what it is).
- Client-specific items: custom domain registration, DNS provider process, apex redirect via a third party, language and wording.
- Any deployment to Azure. Only build, lint and (if a subscription is supplied) what-if are run.

## Decisions taken

- Storage follows the reviewed design: one account for documents and Function host storage, shared-key access on because the Function host needs it, anonymous access off, every request authenticated, private endpoints for blob and file. This is a reference baseline; the hardening alternative (separate accounts, public access off) is recorded in the README Design decisions table as a trade-off.
- The template creates its own VNet and subnets, because templates must be self-contained.
- Key Vault is optional and off by default (nothing reads a secret).
- Lucid deliverable is the importable `*-lucidchart.drawio` copy.

## Architecture

```
Internet -> Front Door Premium + WAF (Prevention)
              |-- /*      -> Static Web App (Standard), accepts only AzureFrontDoor.Backend + X-Azure-FDID
              |-- /api/*  -> Function App (Private Link, public access disabled, no caching)
Function App (system-assigned identity, VNet-integrated, route-all)
  -> Storage account (private endpoints blob + file), Storage Blob Data Reader
Publisher (Entra ID group) -> Storage, Storage Blob Data Contributor
Monitoring: Log Analytics, App Insights availability tests, alerts, Action Group, diagnostics
```

## Modules

| Module | Deploys |
| --- | --- |
| `naming` | CAF names, `<type>-<workload>-<env>-<region>-<instance>` |
| `network` | VNet, integration subnet (delegated `Microsoft.Web/serverFarms`), private-endpoint subnet, NSGs; prefixes from params |
| `front-door` | Premium profile, endpoint, web and API origin groups and origins, routes, security policy, optional custom domains; API route uncached |
| `front-door-waf` | WAF policy, Prevention in uat and prod, managed rule sets, logging |
| `static-web-app` | Standard SWA; Front Door ID and endpoint host exposed as outputs for `staticwebapp.config.json` |
| `function-app` | EP1 Linux plan, Node 24 Function App, identity, VNet integration, public access disabled, private endpoint, Front Door Private Link origin approval |
| `storage` | Account, private container, soft delete, private endpoints, role assignments (Function reader, publisher contributor) |
| `private-endpoint` | Reusable endpoint with private DNS zone group |
| `monitoring` | Log Analytics, App Insights, availability tests (homepage, `/api/documents`), alerts, Action Group, diagnostic settings |
| `governance` | Mandatory tags, delete locks in uat and prod, budget, viewer and operator roles |

`main.bicep` is subscription scope and composes the modules. A deployment stack per environment replaces Terraform state.

## Parameters and environments

- Everything that varies lives in `environments/<env>/main.bicepparam`: subscription, region, SKUs, address ranges, group IDs, thresholds, tags, budgets, redundancy.
- `location` is required, with no default; validate regions where Static Web Apps or EP1 are unavailable.
- Zone redundancy is a parameter: off in dev and qa, on in uat and prod, with validation of combinations a service refuses (and a warning where more than one instance is needed).
- Storage redundancy is a parameter.
- Availability zones row in the README: Front Door and Static Web Apps are global, so nothing zonal applies to them; the trade-off is stated.
- Monitoring cannot be disabled in prod.

## Files

```
infrastructure/publicly-accessible-static-website-with-document-api-bicep/
  README.md, ARCHITECTURE.md
  c4-context.drawio, c4-containers.drawio
  c4-context-lucidchart.drawio, c4-containers-lucidchart.drawio
  bicepconfig.json, .gitignore
  main.bicep
  modules/*.bicep
  environments/{dev,qa,uat,prod}/main.bicepparam, deployment.env
  scripts/deploy.sh, deploy.ps1
  pipelines/
```

## Error handling and constraints

- Front Door Private Link to the Function needs approval on the Function; the deploy script performs or documents it.
- Function package deployment needs a network path to the Function's private endpoint; the README documents this.
- Front Door ID and endpoint host must be written into the Static Web App configuration after Front Door exists; the deploy script does it.
- Names must stay within Azure limits (storage 24 chars, lowercase); the naming module enforces this.

## Verification

- `az bicep build` and lint pass for every environment's parameter file.
- Optional `what-if` if a subscription is provided.
- draw.io files checked with the `c4-drawio` skill; Mermaid renders.
- README states plainly that nothing has been deployed.
- Cost estimate priced from the Azure Retail Prices API on the day it is written, with region and retrieval date.

## Open items

- Which region to use as the dev default (proposed: `westeurope`, matching existing templates).
- Whether `pipelines/` ships Azure DevOps only (as the other templates do).
