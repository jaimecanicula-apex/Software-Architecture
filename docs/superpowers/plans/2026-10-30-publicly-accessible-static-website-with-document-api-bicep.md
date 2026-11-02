# Publicly Accessible Static Website with Document API (Bicep) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the golden template `publicly-accessible-static-website-with-document-api-bicep`: Front Door Premium + WAF, Static Web App, private Function API and private Blob storage, with draw.io and Lucidchart diagrams.

**Architecture:** Subscription-scope `main.bicep` composes one module per concern. Per-environment `main.bicepparam` files hold every varying value. Patterns (naming, network, monitoring, governance, private-endpoint, deploy scripts) are copied from `infrastructure/privately-accessible-static-website-with-storage-bicep/`; Front Door and WAF logic is ported from the Terraform `publicly-accessible-static-website` modules.

**Tech Stack:** Bicep (`az bicep`), Azure CLI, Mermaid, draw.io XML (`c4-drawio` skill).

**Spec:** `docs/superpowers/specs/2026-10-30-publicly-accessible-static-website-with-document-api-bicep-design.md`

## Global Constraints

- Template folder: `infrastructure/publicly-accessible-static-website-with-document-api-bicep/` (T below). It must not reference other templates' files.
- No client or customer names in `infrastructure/`, `content/` or docs.
- Names: `<type>-<workload>-<environment>-<region>-<instance>` from the `naming` module; never hand-written.
- Environments: `dev`, `qa`, `uat`, `prod`; each in its own subscription; `location` required, no default.
- Zone redundancy and storage redundancy are parameters; zones off in dev/qa, on in uat/prod.
- Governance: mandatory tags, delete locks in uat and prod, budgets, viewer/operator roles, monitoring not disable-able in prod.
- Storage: one account for documents and Function host, shared key on, anonymous access off, private endpoints for blob and file.
- Function: public network access disabled, Front Door reaches it through Private Link; no caching on `/api/*`.
- README has `## Design decisions` (Concern, Decision, Why, Trade-off) and `## Cost estimate` (Azure Retail Prices API, region, retrieval date, unit prices, per-environment totals).
- Nothing is deployed to Azure; the README says so.

## Review Focus

- A `location` outside the supported regions must fail validation with a clear message.
- Zone redundancy enabled on an SKU that lacks it must fail validation.
- A storage account name over 24 characters or with uppercase must be impossible from the naming module.
- Monitoring disabled in prod must be rejected.
- A subnet prefix overlapping another must be caught before deploy (what-if or a documented check).

## File Structure

T = `infrastructure/publicly-accessible-static-website-with-document-api-bicep/`

- `T/main.bicep`: composes modules at subscription scope.
- `T/modules/{naming,network,private-endpoint,front-door,front-door-waf,static-web-app,function-app,storage,monitoring,governance}.bicep`: one concern each.
- `T/environments/{dev,qa,uat,prod}/{main.bicepparam,deployment.env}`.
- `T/scripts/deploy.sh`, `deploy.ps1`; `T/pipelines/`; `T/bicepconfig.json`; `T/.gitignore`.
- `T/README.md`, `T/ARCHITECTURE.md`, `T/c4-*.drawio`, `T/c4-*-lucidchart.drawio`.
- Modify: `CLAUDE.md` (template table), `GOLDEN-TEMPLATES.md`.

---

### Task 1: Scaffold, naming and parameter contract

**Files:**
- Create: `T/bicepconfig.json`, `T/.gitignore`, `T/main.bicep`, `T/modules/naming.bicep`, `T/environments/*/main.bicepparam`, `T/environments/*/deployment.env`

**Interfaces:**
- Produces: `naming` module outputs `names` object with keys `resourceGroup, vnet, nsgIntegration, nsgEndpoints, frontDoor, frontDoorEndpoint, waf, staticWebApp, plan, functionApp, storage, container, logAnalytics, appInsights, actionGroup`. `main.bicep` params: `environment` (`'dev'|'qa'|'uat'|'prod'`), `location`, `workload`, `instance`, `tags`, plus per-module params added by later tasks.

- [ ] **Step 1:** Copy `bicepconfig.json`, `.gitignore`, `modules/naming.bicep`, `environments/*/deployment.env` from the `privately-accessible-static-website-with-storage-bicep` template. Extend `naming` with the keys above; storage name is lowercase alphanumerics, truncated to 24 characters.
- [ ] **Step 2:** `main.bicep` (`targetScope = 'subscription'`) declares `@allowed` environment, required `location` validated against the supported-region list in a `@allowed` decorator, creates the resource group.
- [ ] **Step 3:** Write four `main.bicepparam` files with address ranges, SKUs, tags, budgets, `zoneRedundancyEnabled` (false dev/qa, true uat/prod), storage redundancy.
- [ ] **Step 4:** Run `az bicep build --file T/main.bicep` and `az bicep build-params` for each environment. Expected: no errors.
- [ ] **Step 5:** Commit `feat: scaffold document-api bicep template`.

### Task 2: Network and private endpoints

**Files:** Create `T/modules/network.bicep`, `T/modules/private-endpoint.bicep`.

**Interfaces:**
- Produces: `network` outputs `vnetId, integrationSubnetId, endpointSubnetId`; `private-endpoint` params `name, targetResourceId, groupId, subnetId, dnsZoneName`, outputs `privateEndpointId`.

- [ ] **Step 1:** Port `network.bicep` and `private-endpoint.bicep` from the with-storage Bicep template. Integration subnet delegated to `Microsoft.Web/serverFarms`; prefixes from params; names from `naming`.
- [ ] **Step 2:** Add a `@validation`-style check (param assertion in `main.bicep`) that integration and endpoint prefixes differ.
- [ ] **Step 3:** Build `main.bicep` after wiring both modules; expected: no errors. Commit.

### Task 3: Storage

**Files:** Create `T/modules/storage.bicep`.

**Interfaces:**
- Consumes: `naming.names.storage`, `container`, `endpointSubnetId`, `private-endpoint` module.
- Produces: outputs `storageAccountId, storageAccountName, containerName`.

- [ ] **Step 1:** Port `storage.bicep`: StorageV2, SKU from parameter `storageRedundancy`, TLS 1.2, HTTPS only, `allowBlobPublicAccess: false`, shared key on, private container, blob and container soft delete 30 days, versioning off.
- [ ] **Step 2:** Private endpoints for `blob` and `file` through `private-endpoint`.
- [ ] **Step 3:** Parameters `functionPrincipalId` and `publisherGroupObjectId`; assign Storage Blob Data Reader and Contributor respectively.
- [ ] **Step 4:** Build; expected no errors. Commit.

### Task 4: Function App

**Files:** Create `T/modules/function-app.bicep`.

**Interfaces:**
- Consumes: `integrationSubnetId, endpointSubnetId`, storage outputs, App Insights connection string.
- Produces: outputs `functionAppId, functionDefaultHostName, principalId`.

- [ ] **Step 1:** EP1 Linux plan (`zoneRedundant` from `zoneRedundancyEnabled`; with a minimum of 2 instances when true; validation rejects zones on a SKU without support). Function App `node|24`, Functions v4, HTTPS only, TLS 1.2, FTPS disabled, system-assigned identity, VNet integration with `vnetRouteAllEnabled`, `publicNetworkAccess: 'Disabled'`.
- [ ] **Step 2:** App settings `FUNCTIONS_WORKER_RUNTIME=node`, `DATA_STORAGE_ACCOUNT`, `DATA_CONTAINER`, `WEBSITE_RUN_FROM_PACKAGE=1`, `APPLICATIONINSIGHTS_CONNECTION_STRING`.
- [ ] **Step 3:** Private endpoint for sub-resource `sites`. Build; expected no errors. Commit.
- [ ] **Step 4:** Since the identity is needed by Task 3's role assignment, `main.bicep` deploys function-app first, then storage with `functionPrincipalId`.

### Task 5: Static Web App, Front Door and WAF

**Files:** Create `T/modules/static-web-app.bicep`, `front-door.bicep`, `front-door-waf.bicep`.

**Interfaces:**
- Produces: `front-door` outputs `frontDoorId` (the `X-Azure-FDID` value) and `endpointHostName`; `static-web-app` outputs `defaultHostName`, `deploymentTokenSecretNote` (documentation only; the token is never output).

- [ ] **Step 1:** `static-web-app.bicep`: Standard SKU, no repository source.
- [ ] **Step 2:** `front-door-waf.bicep`: WAF policy, Prevention in uat/prod and Detection in dev/qa via parameter, Microsoft default and bot rule sets, logging.
- [ ] **Step 3:** `front-door.bicep`: Premium profile, endpoint, web and API origin groups, SWA origin, Function origin via Private Link (`sites`), routes `/*` and `/api/*`, HTTPS only, redirect HTTP to HTTPS, API caching disabled, security policy linking the WAF, optional `customDomains` array parameter.
- [ ] **Step 4:** Add a `scripts/` step description (Task 8) for approving the Private Link connection. Build; expected no errors. Commit.

### Task 6: Monitoring and governance

**Files:** Create `T/modules/monitoring.bicep`, `T/modules/governance.bicep`.

- [ ] **Step 1:** Port both from the with-storage Bicep template. Monitoring adds Front Door and WAF diagnostics and availability tests for `/` and `/api/documents`; `enabled` must be true when `environment == 'prod'` (rejected otherwise).
- [ ] **Step 2:** Governance: mandatory tags, `CanNotDelete` lock in uat/prod, budget from params, viewer and operator role assignments.
- [ ] **Step 3:** Wire everything in `main.bicep`; build every `main.bicepparam`. Expected: no errors. Commit.

### Task 7: Deploy scripts and pipelines

**Files:** Create `T/scripts/deploy.sh`, `deploy.ps1`, `T/pipelines/*.yml`.

- [ ] **Step 1:** Port the deploy scripts: select environment, create the deployment stack, then (a) approve the Function Private Link connection, (b) print the Front Door ID and endpoint host for `staticwebapp.config.json`.
- [ ] **Step 2:** Port the Azure DevOps pipeline definitions with paths updated to the new folder.
- [ ] **Step 3:** Run `bash -n scripts/deploy.sh` and the PowerShell parser check. Expected: no syntax errors. Commit.

### Task 8: Documentation

**Files:** Create `T/README.md`, `T/ARCHITECTURE.md`.

- [ ] **Step 1:** README: overview, `## Design decisions` table (including Availability zones row and the shared-storage trade-off), first-time setup, deploy, outputs, `## Cost estimate`.
- [ ] **Step 2:** Fetch prices from `https://prices.azure.com/api/retail/prices` for Front Door Premium, SWA Standard, Functions EP1, Storage, Log Analytics, App Insights; record region, retrieval date, unit prices, per-environment fixed totals and budget comparison.
- [ ] **Step 3:** ARCHITECTURE.md: C4 context, containers and components in Mermaid.
- [ ] **Step 4:** Commit.

### Task 9: Diagrams (draw.io and Lucidchart)

**Files:** Create `T/c4-context.drawio`, `T/c4-containers.drawio`, `T/c4-context-lucidchart.drawio`, `T/c4-containers-lucidchart.drawio`.

- [ ] **Step 1:** Invoke the `c4-drawio` skill; generate the two required diagrams, including the "Why pick this design, and its trade-offs" and "What to keep in mind" panels (the Cost line quotes the README totals).
- [ ] **Step 2:** Produce the `*-lucidchart.drawio` copies following the repo's Lucidchart-import conventions used by existing templates.
- [ ] **Step 3:** Run the skill's check; expected: pass. Commit.

### Task 10: Catalogue and final verification

**Files:** Modify `CLAUDE.md` (template table), `GOLDEN-TEMPLATES.md`.

- [ ] **Step 1:** Add the table row; no content folder (state "none yet").
- [ ] **Step 2:** Run `az bicep build` and lint for `main.bicep` and all four param files. Expected: zero errors.
- [ ] **Step 3:** Grep the template for client names (`hotel`, `liera`, `socimi`, `apex-logo`). Expected: no matches.
- [ ] **Step 4:** Commit and summarize results truthfully, noting nothing was deployed.
