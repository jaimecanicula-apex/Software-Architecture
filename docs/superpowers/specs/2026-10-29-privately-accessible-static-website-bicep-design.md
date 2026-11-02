# Design: privately-accessible-static-website-bicep

Date: 2026-10-29. Status: awaiting review.

## Goal

A Bicep golden template that is the twin of `infrastructure/privately-accessible-static-website/` (Terraform): same resources, names and parameters, internal APEX users only, no internet exposure. It must be copyable on its own, and an infrastructure team must be able to deploy it from Azure DevOps by following a written step-by-step.

## Location and shape

`infrastructure/privately-accessible-static-website-bicep/`, sharing `content/privately-accessible-static-website/`. Built from `privately-accessible-static-website-with-storage-bicep/` with the storage parts removed (storage module, storage role, CORS, CSP storage origin, `files-config.json`, storage Entra scope, `files.html` SPA redirect).

```
README.md  ARCHITECTURE.md  c4-context.drawio  c4-containers.drawio  bicepconfig.json  .gitignore
main.bicep                       subscription scope
modules/                         naming, network, static-web-app, site-private-link,
                                 monitoring, monitor-private-link, availability-probe,
                                 probe.sh, governance
environments/<env>/              main.bicepparam, deployment.env
scripts/                         deploy.sh, deploy.ps1
pipelines/                       azure-pipelines-infra.yml, azure-pipelines-content.yml
```

## Parity rules with the Terraform twin

- Same parameter names (camelCase), defaults, validation and tags (`managed-by: bicep`).
- Same naming (`rg-`, `vnet-`, `snet-pe-`, `snet-probe-`, `nsg-`, `ampls-`, `pe-`, `app-` prefixes).
- Same governance: mandatory tags, delete lock in uat and prod, budget, viewer and operator roles, monitoring forced on in prod.
- Region allowed list: westus2, centralus, eastus2, westeurope, eastasia.
- Probe zone redundancy is a parameter, on in uat and prod.
- Entra app: created by `deploy.sh` through the Azure CLI (Bicep cannot create secrets). This is the one deliberate difference, and the README says so.

## Networking for the infrastructure team

- Spoke VNet (address space from the IP plan), two subnets: private endpoints, and probe (at least /27, delegated to Container Apps). One NSG each, denying internet inbound.
- Private DNS zones: `privatelink.<partition>.azurestaticapps.net` for the site, plus the five Azure Monitor zones. Linked to the spoke and, optionally, to the hub VNet.
- Optional spoke-side hub peering (`hubVirtualNetworkId`, `useHubGateway`). Custom `dnsServers` supported.
- README section "What the platform team must do": hub-side peering, corporate DNS forwarding for the zones in the `privateDnsZones` output, central-zone clashes, firewall rules (agent to `management.azure.com`, `login.microsoftonline.com`, Static Web Apps deployment endpoint; probe image pull from MCR), IP plan inputs.

## Azure DevOps step-by-step (README section "Deploy with Azure DevOps")

Two pipelines, both in `pipelines/`:

1. **Infrastructure** (`azure-pipelines-infra.yml`): stages per environment, parameter `environment`.
   - Validate: `az bicep build` and lint.
   - WhatIf: `deploy.sh <env> what-if`, output attached to the run.
   - Deploy: deployment job on environment `swa-internal-infra-<env>` with an Approvals check, runs `deploy.sh <env> deploy` through `AzureCLI@2`.
2. **Content** (`azure-pipelines-content.yml`): same as the Terraform twin's pipeline (build, PR preview, approved production release), with the same variable group and environment names.

The step-by-step covers, in order:

1. Prerequisites: Azure DevOps project, repo, permission to create service connections.
2. One service connection per environment, Azure Resource Manager with workload identity federation, scoped to that environment's subscription.
3. Roles for the connection's principal: Contributor and User Access Administrator on the subscription, Network Contributor on the hub (if peering), and Microsoft Graph `Application.ReadWrite.OwnedBy` plus group-assignment rights. If the organisation refuses Graph rights, the fallback is a one-off manual `deploy.sh` run for the Entra step, then pipeline deploys with the app pre-created.
4. Fill `environments/<env>/main.bicepparam` and `deployment.env` (subscription, tenant, IP ranges, DNS servers, groups).
5. Create environments with Approvals checks, and the variable groups.
6. Create the pipelines from the YAML paths, and the branch policy on main.
7. Run what-if, approve, deploy. Then store the three pipeline secrets from the outputs.
8. Run the content pipeline.
9. Verify from the corporate network: DNS resolution, sign-in, `/healthz.html`, dashboard.

## Known risks to state in the README (not hidden)

- **Agent reachability:** with public network access off, Microsoft-hosted agents may not be able to upload content to the Static Web App. The pipelines take the agent pool as a parameter, and the README documents a self-hosted agent in the VNet as the fallback. This is the same open item as the Terraform README's "verify in dev".
- Nothing has been deployed to Azure. Verification is `az bicep build` and lint only.
- Cost estimate: same resources as Terraform, so the same figures, re-priced from the Retail Prices API on build day.

## Required repo updates

`CLAUDE.md` template table and Bicep notes, `GOLDEN-TEMPLATES.md` catalogue, and any `.github/workflows/` and `.impeccable/` path references.

## Out of scope

Landing-zone Azure Policy, a separate network handoff document, a CI test harness for Bicep.

## Verification

`bicep build` and `bicep lint` on `main.bicep` and each `main.bicepparam`, YAML syntax check on the pipelines, shellcheck-style read of the scripts, and a parity check of parameter names and resource names against the Terraform variables.
