# Privately accessible static website (Bicep)

> **Golden template candidate.** This folder is written to become an APEX golden template. It is self-contained: copy it out and it works on its own.

It deploys with Bicep and Azure DevOps pipelines. The example site it serves is in `content/privately-accessible-static-website/`.

Use this design when the site is for **internal users only**: anyone who signs in with APEX Entra ID, including IT and business colleagues, people from APEX companies, and contractors. It has no internet exposure and no connection outside the APEX tenant. It is not for external clients or users: they need a publicly reachable site with its own entry point and protection.

```
APEX user on the corporate network (VPN / ExpressRoute / office)
   │  resolves the site through Private DNS
   ▼
Private endpoint ──▶ Azure Static Web App (public network access OFF)
                        │  APEX Entra sign-in, assigned groups only
                        ▼
                     content/privately-accessible-static-website/ (build-free HTML, CSS, JS)

In-VNet probe (Container Apps job, every 5 min) ──▶ site /healthz.html
Probe + diagnostics ──▶ Azure Monitor Private Link ──▶ Log Analytics / App Insights
                                                        ├─▶ alerts ─▶ Action Group
                                                        └─▶ workbook dashboard (viewer groups)
```

The C4 model is in [ARCHITECTURE.md](ARCHITECTURE.md), with draw.io diagrams [c4-context.drawio](c4-context.drawio) and [c4-containers.drawio](c4-containers.drawio).

## Contents

1. [How it is deployed](#how-it-is-deployed)
2. [Design decisions](#design-decisions)
3. [Cost estimate](#cost-estimate)
4. [Folder layout](#folder-layout)
5. [Parameters](#parameters)
6. [Tagging](#tagging)
7. [How to use it, step by step](#how-to-use-it-step-by-step)
8. [Deploy with Azure DevOps, step by step](#deploy-with-azure-devops-step-by-step)
9. [Monitoring](#monitoring)
10. [Sign-in](#sign-in)
11. [What the platform team must do](#what-the-platform-team-must-do)
12. [Operating it](#operating-it)
13. [Troubleshooting](#troubleshooting)
14. [To verify in dev before production](#to-verify-in-dev-before-production)

## How it is deployed

| Piece | How it works here |
| --- | --- |
| Entry point | `main.bicep` at subscription scope, with settings per environment in `environments/<env>/main.bicepparam` |
| State | A **deployment stack** per environment (`stack-<workload>-<env>`) in the subscription; there is no state storage to set up |
| Run it | `scripts/deploy.sh` or `scripts/deploy.ps1`, or the Azure DevOps pipelines |
| Entra app registration | Created by `scripts/deploy.sh`, because Bicep cannot create app registrations or secrets |
| Client secret | A new 1-year secret on every deploy |
| Allowed sign-in groups | `ALLOWED_GROUP_IDS` in `environments/<env>/deployment.env` |
| Subscription and tenant | `SUBSCRIPTION_ID` and `TENANT_ID` in `deployment.env` |
| Deletes outside the template | Blocked in uat and prod by the delete lock **and** the stack's `denyDelete` |
| Pipelines | `pipelines/azure-pipelines-infra.yml` (infrastructure) and `pipelines/azure-pipelines-content.yml` (site) |
| Resource tags | `managed-by = bicep` and `golden-template = privately-accessible-static-website-bicep`, plus the governance tags |

## Design decisions

| Concern | Decision | Why | Trade-off |
| --- | --- | --- | --- |
| Region | `location`, required in every environment's `main.bicepparam` (no default), allowed only in the 5 regions that offer Static Web Apps | Data residency and latency are choices per organisation and environment; a silent default could place an environment in the wrong region | Only westus2, centralus, eastus2, westeurope and eastasia. Changing it later recreates the Static Web App and the regional monitoring resources |
| Availability zones | `probeZoneRedundancyEnabled` spreads the availability probe's Container Apps environment across zones: on in uat and prod. The Static Web App, private endpoints and Private DNS have no zone setting; Azure keeps them resilient. There is no state storage to make redundant, because the deployment stack lives in the subscription | A zone failure should not silence the probe and raise a false alert in prod | Fixed at creation: switching it recreates the probe's environment. The site's own resilience is whatever Static Web Apps provides; there is nothing to tune |
| Subnets | Two subnets: private endpoints (`privateEndpointSubnetPrefix`) and the probe (`probeSubnetPrefix`, delegated to Container Apps). Names `snet-pe-<suffix>` and `snet-probe-<suffix>`, each with its own NSG, from `modules/naming.bicep` | Address ranges come from each environment's IP plan, and separating the probe keeps its delegation away from the private endpoints | Two ranges to allocate per environment; the probe subnet needs at least a /27 to itself |
| Entry | Private endpoint in the spoke VNet; Static Web App public network access **off** | Every user is internal, so there is no internet entry to defend at all | Users off the corporate network cannot reach it, the design depends on the hub and corporate DNS, and deployment and preview environments with public access off still need verifying |
| Network | Own spoke VNet, NSGs denying internet inbound, Private DNS zones, optional hub peering | The template works on its own and joins the hub when the platform team is ready | More to own: IP ranges from the IP plan, peering and DNS coordination. Its own Private DNS zones can clash with central zones in a landing zone |
| Sign-in | APEX Entra ID, single tenant, *assignment required* for the groups in `ALLOWED_GROUP_IDS`; secret created by `deploy.sh` | Entra refuses everyone else in the tenant, before the site sees a request | The client secret lasts one year and is replaced on each deploy, so an environment not redeployed within a year loses sign-in |
| App registration | Created by `scripts/deploy.sh` through the Azure CLI, not by Bicep | Bicep has no way to create an app registration or a secret | The deploying identity needs Entra rights, and the app registration lives outside the deployment stack: deleting the stack leaves it behind |
| State | A deployment stack per environment (`stack-<workload>-<env>`) with `--action-on-unmanage deleteAll` | Resources removed from the template are removed from Azure, so there is no separate state to host | The stack is a subscription-level object: whoever can delete stacks can delete the environment, and it cannot be moved |
| Availability | Container Apps job inside the VNet requests `/healthz.html` every 5 minutes | Internet web tests cannot reach a private site; the job takes the same private path as users, with no server, code package or storage account | One location, from inside the VNet only: it does not test users' VPN or ExpressRoute path or warn about certificate expiry, and the job image is pulled from the internet |
| Telemetry | Azure Monitor Private Link Scope with private-only ingestion | Monitoring data about a private site stays on the private network | The Private Link Scope changes Azure Monitor DNS for the whole network, adds cost, and is one more link that can fail |
| Alerts | Availability below threshold, probe silent for 15 minutes, destructive changes, resource and service health, budget | A silent probe means the check itself or its private path failed, which availability alone would not show | A probe-silent alert says something broke but not whether it is the probe, the network or the site; someone must diagnose it |
| Dashboard access | `monitoringQueryFromInternet = true` by default | Viewers can open the dashboard from the portal anywhere they sign in; set false to limit it to the APEX network | Open from anywhere means any device where viewers sign in; limiting it means viewers need the corporate network |
| Governance | Mandatory tags, recommended tags, budget, delete lock in uat and prod, viewer and operator groups | Required for every golden template | The lock blocks legitimate teardown until removed through change control, and a budget only warns; it never stops spending |
| Tags | Four mandatory tags (owner, cost centre, data classification, support) must be set; three recommended tags (business unit, criticality, project code) are applied when set | Cost reports, incident routing and audits work from tags; recommended ones add reporting detail without blocking a deployment | Recommended tags can be left out and then silently missing from reports; criticality and project code need someone to keep them current |

## Cost estimate

Retail list prices in USD for West Europe from the Azure Retail Prices API, the data source of the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/). A month is 730 hours. Taxes, discounts, reservations and currency conversion are not included; re-check in the calculator before committing a budget.

**Price provenance:** the Private DNS zone price ($0.50 per zone) was re-confirmed against the API on 2026-10-29. The other unit prices below were retrieved on 2026-09-27 and not re-fetched since; refresh them before this template is published.

Per environment. The same resources run in dev, qa, uat and prod; only log retention differs.

| Item | Price used | Per month |
| --- | --- | --- |
| Static Web App, Standard | $9 per app | $9.00 |
| Private endpoints, 2 (site and Azure Monitor Private Link Scope) | $0.01 an hour each, plus $0.01 per GB processed in and out | $14.60 |
| Private DNS zones, 6 (site plus 5 for Azure Monitor) | $0.50 per zone | $3.00 |
| Availability probe: Container Apps job, 0.25 vCPU and 0.5 GiB, every 5 minutes | About 22,000 vCPU-seconds a month, inside the free grant | $0 |
| Alerts, including the probe-silent log alert | $0.15 to $1.00 per rule; activity log alerts free | about $2 |
| Azure Monitor Private Link Scope | No charge for the scope itself | $0 |
| Log Analytics and Application Insights | First 5 GB free, then $2.99 per GB; retention past 31 days $0.13 per GB a month | $0 up to 5 GB |
| VNet, NSGs, deployment stack, Entra app, budget | No charge | $0 |
| **Total** | | **about $29** |

- **The private networking adds about $18 a month** (two private endpoints and six DNS zones) over a public site with no Front Door.
- **To confirm:** the price list has a Container Apps "Environment Management Hour" meter at $0.143 an hour (about $104 a month). Check in the calculator whether it applies to the probe's Consumption-only environment; it is not in the total above.
- **Budgets** (100, 150, 200, 300 for dev, qa, uat, prod) are several times the estimate; they can be lowered unless the environment meter above applies.
- **Monitoring off** in dev or qa (`enableMonitoring = false`) removes the Azure Monitor private endpoint, five DNS zones, alerts and the probe: about $12 a month (leaving about $17: the app, one private endpoint and one DNS zone).

## Folder layout

```
infrastructure/privately-accessible-static-website-bicep/
├── main.bicep                 Subscription-scope entry point: composes the modules
├── bicepconfig.json           Linter rules (unused parameters and secrets in outputs are errors)
├── modules/
│   ├── naming.bicep           Names, including vnet-, ampls-, pe-, app- prefixes
│   ├── network.bicep          Spoke VNet, private-endpoint and probe subnets, NSGs,
│   │                          Azure Monitor Private DNS zones, optional hub peering
│   ├── private-endpoint.bicep Generic private endpoint + DNS zone group
│   ├── static-web-app.bicep   Static Web App with public network access off
│   ├── site-private-link.bicep The site's private DNS zone, links and private endpoint
│   ├── monitoring.bicep       Log Analytics, App Insights (private ingestion), alerts,
│   │                          workbook, viewer/operator roles
│   ├── monitor-private-link.bicep  Azure Monitor Private Link Scope + endpoint
│   ├── availability-probe.bicep    Scheduled Container Apps job inside the VNet (probe.sh)
│   └── governance.bicep       Delete lock and budget
├── environments/dev|qa|uat|prod/
│   ├── main.bicepparam        All environment-specific settings
│   └── deployment.env         Subscription, tenant and the sign-in groups
├── scripts/deploy.sh · deploy.ps1   Entra app, deployment stack, redirect URI
└── pipelines/
    ├── azure-pipelines-infra.yml     Validate, what-if, approved deploy
    └── azure-pipelines-content.yml   Build, PR preview, approved release of the site
```

## Parameters

Set these in `environments/<env>/main.bicepparam`. Required ones have no default.

| Parameter | Required | Default | Meaning |
| --- | --- | --- | --- |
| `environment` | yes | | `dev`, `qa`, `uat` or `prod` |
| `location` | yes | | One of westus2, centralus, eastus2, westeurope, eastasia |
| `workload`, `instance` | no | `swi`, `001` | Parts of every resource name |
| `applicationName` | no | `Internal Static Website` | The `application` tag |
| `governanceTags` | yes | | Mandatory and recommended tags, see [Tagging](#tagging) |
| `extraTags` | no | `{}` | Any other tags; they win over the template's tags with the same name |
| `enableDeleteLock` | no | `false` | On in uat and prod |
| `monthlyBudget`, `budgetStartDate`, `budgetContactEmails` | no | `0` (off) | Resource-group budget; contacts are needed when monitoring is off |
| `previewEnvironmentsEnabled` | no | `true` | Pull-request previews, also private. Off in uat and prod |
| `vnetAddressSpace`, `privateEndpointSubnetPrefix`, `probeSubnetPrefix` | yes | | From the IP plan; probe subnet at least /27 |
| `dnsServers` | no | Azure DNS | For example the hub DNS resolver |
| `hubVirtualNetworkId`, `useHubGateway` | no | none, `false` | Spoke-side peering and DNS links to the hub |
| `entraClientId`, `entraClientSecret` | yes | | Set by `deploy.sh` through environment variables; never written in the file |
| `enableMonitoring` | no | `true` | Always on in prod, whatever this says |
| `logRetentionDays`, `logDailyQuotaGb` | no | `90`, no cap | Log Analytics |
| `monitoringQueryFromInternet` | no | `true` | `false` limits the dashboard to the APEX network |
| `probeZoneRedundancyEnabled` | no | `false` | On in uat and prod. Fixed at creation |
| `probeCron`, `probeImage` | no | every 5 minutes, MCR azure-cli | Mirror the image into an APEX registry for a closed network |
| `alertEmailReceivers`, `alertWebhookReceivers`, `alertThresholds` | no | none | Alert targets; `alertThresholds = { availabilityPercent: 95 }` in prod |
| `enableServiceHealthAlert` | no | `true` | Keep it on in only one environment per subscription |
| `exportActivityLog` | no | `false` | On in at most one environment per subscription |
| `monitoringViewerPrincipalIds`, `monitoringOperatorPrincipalIds` | no | none | Entra group object IDs for the dashboard and operations roles |

### Outputs

| Output | Use |
| --- | --- |
| `resourceGroupName`, `staticWebAppName` | Finding the resources |
| `privateUrl`, `staticWebAppHostName` | The site's address, resolvable only through the private DNS |
| `privateDnsZones` | The zones corporate DNS must resolve |
| `virtualNetworkId` | For the hub's side of the peering |
| `monitoringDashboardUrl` | The workbook, empty when monitoring is off |
| `staticWebAppConfigJson` | Store as the pipeline secret `SWA_CONFIG_JSON` |

## Tagging

Every resource and the resource group carry these tags.

| Tag | Source | Kind |
| --- | --- | --- |
| `environment` | `environment` | Set by the template |
| `application` | `applicationName` | Set by the template |
| `workload` | `workload` | Set by the template |
| `audience` | always `internal` | Set by the template |
| `managed-by` | always `bicep` | Set by the template |
| `golden-template` | always `privately-accessible-static-website-bicep` | Set by the template: tells anyone who finds the resource where it came from |
| `owner` | `governanceTags.owner` | **Mandatory**: the team accountable for the service |
| `cost-centre` | `governanceTags.costCentre` | **Mandatory**: where the bill goes |
| `data-classification` | `governanceTags.dataClassification` | **Mandatory**: for example `Internal` |
| `support` | `governanceTags.support` | **Mandatory**: group or mailbox that takes incidents |
| `business-unit` | `governanceTags.businessUnit` | **Recommended**: for cost reports by business area |
| `criticality` | `governanceTags.criticality` | **Recommended**: `Low`, `Medium`, `High` or `Mission-critical`. The parameter files suggest Low for dev and qa, Medium for uat, High for prod |
| `project-code` | `governanceTags.projectCode` | **Recommended**: the project or programme code, when one exists |

Leave a recommended line out of `governanceTags` and its tag is not applied; mandatory ones fail the deployment if missing. Add anything else (for example `expiry-date` for a temporary environment) in `extraTags`.

Deliberately not tagged: a creation date or deploying user. They change on every deployment and would make every what-if show a difference. Azure's activity log already records who deployed.

## How to use it, step by step

This is the path from nothing to a working private site on your own machine. To run it from Azure DevOps instead, go straight to the [next section](#deploy-with-azure-devops-step-by-step).

### 1. Install the tools

- A recent Azure CLI (it must have `az stack sub` for deployment stacks), with `az bicep install` run once.
- Bash (Git Bash, WSL or Linux or macOS) for `deploy.sh`, or PowerShell 7 for `deploy.ps1`.

### 2. Get what you need from the platform team

- An Azure subscription for each environment, and the tenant ID.
- Free IP ranges for the spoke VNet and its two subnets.
- The hub VNet resource ID and hub DNS resolver address, if the site must be reachable from the corporate network.
- The Entra group object IDs for the people who may sign in, and for monitoring viewers and operators.

### 3. Sign in and check your rights

```sh
az login --tenant <tenant id>
```

You need **Contributor** and **User Access Administrator** on the subscription, **Network Contributor** on the hub if you set `hubVirtualNetworkId`, and Entra rights to create app registrations and assign groups (Application Developer or Cloud Application Administrator, plus the right to assign groups to the app). Without Entra rights, ask for the app registration to be created for you, see [If you may not create app registrations](#if-you-may-not-create-app-registrations).

### 4. Fill in the environment

Open `environments/dev/` and replace every `<...>` placeholder:

1. `deployment.env`: `SUBSCRIPTION_ID`, `TENANT_ID` and `ALLOWED_GROUP_IDS` (comma separated, no spaces).
2. `main.bicepparam`:
   - `governanceTags`: the four mandatory tags and the recommended ones ([Tagging](#tagging))
   - `vnetAddressSpace`, `privateEndpointSubnetPrefix`, `probeSubnetPrefix`
   - `dnsServers` and `hubVirtualNetworkId`, if used: remove the leading `//`
   - `alertEmailReceivers`, `monitoringViewerPrincipalIds`, `monitoringOperatorPrincipalIds`
   - `monthlyBudget` and `budgetStartDate`

### 5. Preview

```sh
./infrastructure/privately-accessible-static-website-bicep/scripts/deploy.sh dev what-if
```

```powershell
./infrastructure/privately-accessible-static-website-bicep/scripts/deploy.ps1 -Environment dev -Command what-if
```

Read the output. On a first run everything is a create. No app registration or secret is made for a what-if.

### 6. Deploy

```sh
./infrastructure/privately-accessible-static-website-bicep/scripts/deploy.sh dev deploy
```

The script does three things in order:

1. Creates or reuses the Entra app registration, makes the service principal require assignment, assigns the groups in `ALLOWED_GROUP_IDS`, and creates a fresh 1-year client secret.
2. Deploys `main.bicep` as the deployment stack `stack-swi-dev`. Re-running it changes only what differs.
3. Sets the app registration's redirect URI to `https://<site>/.auth/login/aad/callback`, which needs the site's host name from step 2.

It ends by printing the commands for the next step.
### 7. Store the pipeline secrets

```sh
az staticwebapp secrets list --name <static web app> --resource-group <resource group> --query properties.apiKey -o tsv
./infrastructure/privately-accessible-static-website-bicep/scripts/deploy.sh dev show
```

Store the first as `AZURE_STATIC_WEB_APPS_API_TOKEN` and `outputs.staticWebAppConfigJson.value` as `SWA_CONFIG_JSON` in the content pipeline's variable group (or GitHub environment secrets).

### 8. Ask the platform team for the network pieces

Give them the `privateDnsZones` and `virtualNetworkId` outputs (see [What the platform team must do](#what-the-platform-team-must-do)). Until the hub peering and DNS forwarding exist, the site resolves only from inside the spoke VNet.

### 9. Publish the content

Run the content pipeline ([Azure DevOps step 8](#deploy-with-azure-devops-step-by-step)) or upload from a machine inside the network with the Static Web Apps CLI and the token from step 7.

### 10. Check it works

From a machine on the corporate network, not your home network:

1. `nslookup <site host name>` returns a private address (10.x), not a public one.
2. `https://<site host name>/healthz.html` returns the health page without signing in.
3. `https://<site host name>/` sends you to the Microsoft sign-in. A member of an allowed group reaches the site; anyone else in APEX is refused by Entra.
4. After about 10 minutes, the dashboard (`monitoringDashboardUrl`) shows probe results.

### 11. Repeat for qa, uat and prod

Same steps with `qa`, `uat` and `prod`. Each has its own subscription, address range and deployment stack. In uat and prod, the delete lock and `denyDelete` are on.

### If you may not create app registrations

Ask an Entra administrator to create a single-tenant app named `app-<workload>-<env>-<instance>` (for example `app-swi-dev-001`), a service principal with *assignment required*, the groups assigned, and a client secret. Then run `deploy.sh` with that name: it finds the existing app and only resets its secret, which still needs the right to manage that app's credentials. If even that is refused, deploy with `az stack sub create` directly after exporting `ENTRA_CLIENT_ID` and `ENTRA_CLIENT_SECRET` yourself, and set the redirect URI by hand.

## Deploy with Azure DevOps, step by step

Two pipelines do the work: the **infrastructure** pipeline deploys one environment per run, and the **content** pipeline publishes the site. Do the steps in this order.

### 1. Prerequisites

- An Azure DevOps project with this repository in Azure Repos.
- The Project Administrator role, or the right to create pipelines, environments, variable groups and service connections.
- The platform team's inputs from [How to use it, step 2](#2-get-what-you-need-from-the-platform-team).
- A decision on the build agent. A Microsoft-hosted agent (`ubuntu-latest`) runs the infrastructure pipeline. Whether it can upload the site to a private Static Web App is unproven; see [step 8](#8-run-the-content-pipeline).

### 2. Fill in the environments in the repository

Edit `environments/<env>/main.bicepparam` and `deployment.env` as in [How to use it, step 4](#4-fill-in-the-environment), commit and push. The subscription and tenant IDs in `deployment.env` are not secrets. **Never** put a client secret or deployment token in these files.

### 3. Create one service connection per environment

**Project settings, Service connections, New service connection, Azure Resource Manager, Workload identity federation (automatic)**:

| Setting | Value |
| --- | --- |
| Scope level | Subscription |
| Subscription | That environment's subscription |
| Resource group | Leave empty |
| Service connection name | `sc-swa-internal-dev`, `sc-swa-internal-qa`, `sc-swa-internal-uat`, `sc-swa-internal-prod` |
| Grant access permission to all pipelines | Off; authorise the pipeline on its first run |

Workload identity federation means no secret to store or rotate.

### 4. Give each connection's identity its roles

Find the app registration that Azure DevOps created for each connection, and give it:

| Role | Where | Why |
| --- | --- | --- |
| Contributor | The environment's subscription | Creates the resources |
| User Access Administrator | The environment's subscription | Grants the monitoring viewer and operator roles |
| Network Contributor | The hub VNet, when `hubVirtualNetworkId` is set | Creates the spoke-side peering |
| Microsoft Graph application permission `Application.ReadWrite.OwnedBy`, admin consented | The tenant | Lets `deploy.sh` create and update its own app registration and secret |
| Microsoft Graph application permission `AppRoleAssignment.ReadWrite.All`, admin consented | The tenant | Lets `deploy.sh` assign the sign-in groups |

Tenant-wide Graph permissions need an administrator and are often refused. **If they are:** run `deploy.sh <env> deploy` once from a person's machine with the needed rights ([How to use it](#how-to-use-it-step-by-step)); the app registration then exists. In the pipeline, grant the connection's identity ownership of that app and the *Cloud Application Administrator* role scoped to it, or ask for a one-off exception. The trade-off is a manual step per environment and a secret that expires after a year unless someone redeploys.

### 5. Create the environments and approvals

**Pipelines, Environments, New environment** (resource: None), one for each of:

- `swa-internal-infra-dev`, `swa-internal-infra-qa`, `swa-internal-infra-uat`, `swa-internal-infra-prod`
- `swa-internal-production`, for the content release

On each, **Approvals and checks, Approvals**, and add the approvers. Use at least two approvers for uat and prod. The approval is what stops a deployment after the what-if is read.

### 6. Create the variable group

**Pipelines, Library, Variable group** named `swa-internal-deployment`, with two variables marked secret: `AZURE_STATIC_WEB_APPS_API_TOKEN` and `SWA_CONFIG_JSON`. Leave them empty until the first deployment has produced the values (step 9). Authorise the content pipeline to use the group.

The content pipeline uses the variable group `swa-internal-deployment` and the environment `swa-internal-production`. If another site in the same Azure DevOps project already uses those names, rename them in the YAML or use a separate project.

### 7. Create the pipelines

**Pipelines, New pipeline, Azure Repos Git, your repository, Existing Azure Pipelines YAML file**, once for each:

| Pipeline name | YAML path |
| --- | --- |
| `swa-internal-infra` | `/infrastructure/privately-accessible-static-website-bicep/pipelines/azure-pipelines-infra.yml` |
| `swa-internal-content` | `/infrastructure/privately-accessible-static-website-bicep/pipelines/azure-pipelines-content.yml` |

Add a branch policy on `main` with required reviewers and build validation using `swa-internal-content`, so pull requests get a preview.

### 8. Deploy the infrastructure

1. **Run pipeline** on `swa-internal-infra`, choose `environment = dev`, leave `agentPool` as `Microsoft-hosted`.
2. On the first run, click **Permit** for each service connection and environment the run asks for.
3. **Validate** builds and lints the Bicep. A failure here is a template or parameter mistake: read the log line.
4. **WhatIf** prints the planned changes. Open the log and read it: on a first run it is all creates.
5. **Deploy** waits for the approval on `swa-internal-infra-dev`. An approver reads the what-if, then approves.
6. When it finishes, the log ends with the deployed host name and the commands for the secrets. If a group assignment fails with "already assigned, or you lack the right", check the identity's Graph rights from step 4.
7. Repeat with `qa`, `uat` and `prod`. Deploy dev first and check it before the others.

### 9. Store the secrets from the first deployment

Read the values with the commands from the deploy log, or run `deploy.sh <env> show` from a machine signed in to Azure. Put them in the variable group `swa-internal-deployment`:

| Variable | Value |
| --- | --- |
| `AZURE_STATIC_WEB_APPS_API_TOKEN` | `az staticwebapp secrets list --name <swa> --resource-group <rg> --query properties.apiKey -o tsv` |
| `SWA_CONFIG_JSON` | `outputs.staticWebAppConfigJson.value` from `deploy.sh <env> show` |

The group holds one set of values, for one site. With several environments, create one group and one pipeline copy per environment, or move the values into per-environment groups: this is the main thing to settle for a multi-environment rollout.

### 10. Run the content pipeline

1. Open a pull request that changes anything under `content/privately-accessible-static-website/`. Build validation runs `swa-internal-content`: it checks the files, writes `staticwebapp.config.json` from `SWA_CONFIG_JSON`, publishes the `site` artifact, and deploys a preview named `pr<id>`.
2. Merge to `main`. The Release stage waits for the approval on `swa-internal-production`, then deploys.
3. **If the deploy step cannot connect:** the Microsoft-hosted agent cannot reach the private Static Web App. Install a self-hosted agent on a machine or VM inside the VNet or the hub, with outbound access to Azure DevOps and `login.microsoftonline.com`; create an agent pool for it; run the pipeline with `agentPool` set to that pool. The trade-off is a machine to patch and pay for.

### 11. Verify

From the corporate network, run the checks in [How to use it, step 10](#10-check-it-works).

### 12. Change something later

- **Infrastructure:** edit the `.bicepparam` or Bicep, push, run `swa-internal-infra` for the environment. Read the what-if first.
- **Site content:** open a pull request; merge to release.
- **Secret expiry:** the client secret lasts one year. Redeploy each environment at least every 9 months; a calendar reminder is enough, or schedule the infrastructure pipeline.
- **Clean up previews:** `az staticwebapp environment delete --name <static-web-app> --environment-name pr<id>`.

## Monitoring

Every environment gets the full set, and none of it uses the internet:

- **Availability:** a Container Apps job inside the VNet requests `https://<site>/healthz.html` every 5 minutes and writes the result to Application Insights.
- **Alerts:**
  - availability below threshold (sev 1)
  - the probe stops reporting for 15 minutes (sev 1)
  - destructive or security changes: deletions, role assignments, removed locks
  - resource health, Azure service health, and budget
- **Private telemetry:** the probe's results go through the Azure Monitor Private Link Scope, and ingestion is private-only.
- **Who can see it:**
  - `monitoringViewerPrincipalIds` and `monitoringOperatorPrincipalIds` get reader and operator roles on this resource group only.
  - `monitoringQueryFromInternet = true` (the default) lets them open the dashboard from the Azure portal anywhere they can sign in. `false` limits it to the APEX network.
- **Switch:** `enableMonitoring = false` is allowed in dev and qa to save about $12 a month; prod ignores it.

## Sign-in

- **App registration:** `deploy.sh` creates a single-tenant registration named `app-<workload>-<env>-<instance>`. Its redirect URI is `https://<site>/.auth/login/aad/callback`.
- **Who gets in:** *assignment required* is on, so only the groups in `ALLOWED_GROUP_IDS` can sign in. Everyone else in APEX is refused by Entra itself.
- **To add or remove a group:** edit `ALLOWED_GROUP_IDS` and run `deploy.sh <env> deploy` again. The script only adds assignments; remove a group in Entra (Enterprise applications, Users and groups).
- **Client secret:** one year, replaced on every deploy, written to the Static Web App's settings.
- **Unauthenticated routes:** `/healthz.html` is the only anonymous page, so the probe can check the site without signing in. It is still reachable only from the private network.

## What the platform team must do

- **Hub peering:** create the hub side of the peering. This template only creates the spoke side, and only when `hubVirtualNetworkId` is set.
- **DNS:** make corporate DNS resolve the zones in the `privateDnsZones` output. Either link them to the hub, which the template does when `hubVirtualNetworkId` is set, or forward them to the hub DNS resolver.
- **Firewall:** allow the build agent to reach `management.azure.com`, `login.microsoftonline.com`, `graph.microsoft.com` and the Static Web Apps deployment endpoint; allow the probe to pull `mcr.microsoft.com/azure-cli`, or mirror it.
- **Monitor DNS zones:** this design creates its own `privatelink.*` zones for Azure Monitor. In a landing zone with central Private DNS zones, point to those zones instead. That is one of the golden-template changes.
- **IP plan:** hand out a non-overlapping range per environment.

## Operating it

| Task | How |
| --- | --- |
| See what is deployed | `deploy.sh <env> show` |
| Change an environment | Edit the files, `deploy.sh <env> what-if`, then `deploy` |
| Rotate the sign-in secret | `deploy.sh <env> deploy` |
| Remove an environment | Remove the lock first in uat and prod through change control, then `deploy.sh <env> delete`. The Entra app registration is left behind: delete it by hand |
| Recover deleted resources | The stack uses `deleteAll`: a resource removed from the template is deleted. Restoring means redeploying |

## Troubleshooting

| Symptom | Likely cause and fix |
| --- | --- |
| `deploy.sh` stops at "Signed in to tenant ..., expected ..." | `az login` to the tenant in `deployment.env` |
| "Insufficient privileges" on `az ad app create` | Entra rights missing; use [If you may not create app registrations](#if-you-may-not-create-app-registrations) |
| Group assignment prints "already assigned, or you lack the right" | Either is possible; check Enterprise applications, Users and groups |
| Site name does not resolve, or resolves to a public address | The zone in `privateDnsZones` is not forwarded or linked from your network |
| The sign-in page loops or shows a redirect error | The redirect URI is missing: redeploy, or set `https://<site>/.auth/login/aad/callback` |
| `403` after signing in | The user is not in an allowed group |
| `/healthz.html` returns 404 | The content has not been deployed yet |
| Alert "probe silent" | The probe, its network path or the site failed; start with the Container Apps job's last executions |
| Stack deploy refuses a change in uat or prod | `denyDelete` is on; the change deletes something. Review it and go through change control |
| `bicep` linter reports an unused parameter | A parameter the template no longer uses; remove it from `main.bicep` and the parameter files |

## To verify in dev before production

Nothing has been deployed to Azure yet. Only `bicep build` and lint are intended checks, and the Bicep compiler was not available when this template was written, so even those need to be run:

```sh
az bicep build --file infrastructure/privately-accessible-static-website-bicep/main.bicep --stdout > /dev/null
az bicep lint  --file infrastructure/privately-accessible-static-website-bicep/main.bicep
```

Then confirm in dev:

- Deployment from Azure Pipelines still works with public network access disabled.
- Pull-request preview environments resolve through the private DNS zone.
- The probe image is pulled from MCR over outbound internet. For a fully closed network, mirror the image into an APEX registry and set `probeImage`.
- The service connection's identity gets the Graph rights it needs, or the manual fallback is agreed.
- The `deploy.sh` flow when `ALLOWED_GROUP_IDS` is empty: it skips group assignment, so no one can sign in until groups are assigned.
