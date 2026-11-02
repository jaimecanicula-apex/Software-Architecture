# privately-accessible-static-website-bicep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Bicep golden template that deploys the same private Static Web App as the Terraform template `privately-accessible-static-website`, with Azure DevOps pipelines and a step-by-step deploy guide.

**Architecture:** Copy `infrastructure/privately-accessible-static-website-with-storage-bicep/` to `infrastructure/privately-accessible-static-website-bicep/` and remove everything storage-related. Resources, names and parameters must equal the Terraform twin. The Entra app is created by `scripts/deploy.sh` through the Azure CLI. Two Azure DevOps pipelines (infrastructure, content) are added.

**Tech Stack:** Bicep (subscription scope, deployment stacks), Azure CLI, bash and PowerShell, Azure DevOps YAML, draw.io (via the `c4-drawio` skill).

**Spec:** `docs/superpowers/specs/2026-10-29-privately-accessible-static-website-bicep-design.md`

## Global Constraints

- Template folder: `infrastructure/privately-accessible-static-website-bicep/`. Content folder is shared: `content/privately-accessible-static-website/` (nothing is added there).
- Terraform twin for parity: `infrastructure/privately-accessible-static-website/` (variables in `stacks/static-website/variables.tf`, values in `environments/<env>/terraform.tfvars`). Copy per-environment values (budgets, retention, zone redundancy, lock) from its tfvars; do not invent them.
- Defaults: `workload = 'swi'`, `instance = '001'`, `applicationName = 'Internal Static Website'`. Tag `managed-by: bicep`, `audience: internal`.
- Region allowed list: westus2, centralus, eastus2, westeurope, eastasia. Environments: dev, qa, uat, prod.
- Static Web App SKU `Standard`, `publicNetworkAccessEnabled: false`. Monitoring forced on in prod. Probe zone redundancy on in uat and prod. Delete lock on in uat and prod.
- No client or customer names anywhere. No secrets in the repo (Entra secret comes from the environment only).
- Templates must not reference other templates' files. The only cross-template reference allowed is the documentation link to the Terraform twin.
- Nothing has been deployed to Azure; docs must say verification is `bicep build` and lint only.
- Do not commit unless the user asks; steps marked "Checkpoint" are where a commit would go.

## Review Focus

1. `enableMonitoring = false` outside prod: the template must still build, the Azure Monitor DNS zones, Private Link Scope and probe are skipped, and the site private endpoint remains. Pinned in Task 1.
2. `environment = 'prod'` with `enableMonitoring = false` in the param file: monitoring is still on. Pinned in Task 1.
3. `hubVirtualNetworkId` and `dnsServers` left unset: builds clean, no peering or hub link. Pinned in Task 1.
4. `allowedGroupIds` empty (`ALLOWED_GROUP_IDS` unset): param files still build and `deploy.sh` skips group assignment without failing. Pinned in Tasks 2 and 3.
5. Pipelines run on a Microsoft-hosted agent that cannot reach the private site: the agent pool is a parameter and the README names the fallback. Pinned in Task 4.

---

### Task 1: Scaffold the template and remove storage

**Files:**
- Create: `infrastructure/privately-accessible-static-website-bicep/` by copying the with-storage Bicep twin's `main.bicep`, `bicepconfig.json`, `.gitignore`, and `modules/` (not `storage.bicep`).
- Modify: `main.bicep`, `modules/naming.bicep`, and any module with a storage reference (found in the step below).

**Interfaces:**
- Produces: `main.bicep` params and outputs listed below. Later tasks (param files, scripts, docs) rely on these names.
  - Params: `environment`, `location`, `workload`, `instance`, `applicationName`, `governanceTags`, `extraTags`, `enableDeleteLock`, `monthlyBudget`, `budgetStartDate`, `budgetContactEmails`, `previewEnvironmentsEnabled`, `vnetAddressSpace`, `privateEndpointSubnetPrefix`, `probeSubnetPrefix`, `dnsServers`, `hubVirtualNetworkId`, `useHubGateway`, `allowedGroupIds`, `entraClientId`, `entraClientSecret` (`@secure()`), `enableMonitoring`, `logRetentionDays`, `logDailyQuotaGb`, `monitoringQueryFromInternet`, `probeZoneRedundancyEnabled`, `probeCron`, `probeImage`, `alertEmailReceivers`, `alertWebhookReceivers`, `alertThresholds`, `enableServiceHealthAlert`, `exportActivityLog`, `monitoringViewerPrincipalIds`, `monitoringOperatorPrincipalIds`.
  - Outputs: `resourceGroupName`, `staticWebAppName`, `privateUrl`, `staticWebAppHostName`, `entraClientId`, `virtualNetworkId`, `privateDnsZones`, `monitoringDashboardUrl`, `staticWebAppConfigJson`.
- Removed vs the twin: params `storageReplicationType`, `softDeleteRetentionDays`, `malwareScanningEnabled`, `malwareScanCapGbPerMonth`, `maxUploadMb`, `allowedExtensions`, `additionalSiteOrigins`; the `storage` module; outputs `storageAccountName`, `filesConfigJson`; naming funcs `privateEndpointStorageName`, `storageRoleName`, `storageAccountName`.

- [ ] **Step 1: Find the storage references.** Run `grep -rniE "storage|blob" infrastructure/privately-accessible-static-website-bicep/modules infrastructure/privately-accessible-static-website-bicep/main.bicep` after the copy. Expected: hits in `main.bicep`, `naming.bicep`, and one line each in `private-endpoint`, `governance`, `monitoring`, `availability-probe`, `static-web-app`. Decide for each: remove if it is about the file library, keep if it is about Azure Monitor (for example the `privatelink.blob.core.windows.net` zone, which Azure Monitor needs).
- [ ] **Step 2: Edit `main.bicep`.** Remove the params, module, names and outputs listed above, the storage role and CORS wiring, and `dependsOn: storage` in governance. In `network`, pass `privateDnsZones: monitoringOn ? monitorDnsZones : []` (the blob zone is only for Azure Monitor now; delete the `blobDnsZone` var). In `staticWebAppConfigJson`, drop the storage host from `connect-src` so it matches the Terraform template `stacks/static-website/templates/staticwebapp.config.json.tftpl` exactly. Header comment: describe this template, link its Terraform twin `../privately-accessible-static-website`.
- [ ] **Step 3: Edit `naming.bicep`.** Delete the three storage functions. Everything else is unchanged.
- [ ] **Step 4: Remove the file-library references found in Step 1** from the other modules, keeping Azure Monitor ones.
- [ ] **Step 5: Build.** Run `az bicep build --file infrastructure/privately-accessible-static-website-bicep/main.bicep --stdout > /dev/null`. Expected: exit 0, no errors. Then `az bicep lint --file` on the same file. Expected: no errors (fix warnings you introduced).
- [ ] **Step 6: Review Focus checks.** In the scratchpad directory, write three throwaway `.bicepparam` files that `using` the real `main.bicep` and supply all required params: (a) `environment = 'dev'`, `enableMonitoring = false`; (b) `environment = 'prod'`, `enableMonitoring = false`; (c) no `hubVirtualNetworkId`, no `dnsServers`. Run `az bicep build-params --file <each>`. Expected: all three exit 0. Then read `main.bicep` and confirm `monitoringOn` is `enableMonitoring || environment == 'prod'` and that every `monitoring.outputs`, `monitorPrivateLink` and `availabilityProbe` use is guarded by `monitoringOn`.
- [ ] **Step 7: Parity check.** Print the sorted `param` names from `main.bicep` and the sorted `variable` names from `stacks/static-website/variables.tf` (snake_case converted to camelCase). Expected differences only: Terraform's `subscription_id`, `tenant_id`, `create_entra_app`, `existing_entra_client_id`, `existing_entra_client_secret`, `entra_app_owners` (Terraform-only), and Bicep's `entraClientId`, `entraClientSecret`. Anything else is a bug; fix it.
- [ ] **Checkpoint:** commit `feat: add privately-accessible-static-website-bicep module and main template`.

### Task 2: Environment parameter files

**Files:**
- Create: `environments/dev|qa|uat|prod/main.bicepparam` and `environments/dev|qa|uat|prod/deployment.env`

**Interfaces:**
- Consumes: Task 1 param names.
- Produces: `deployment.env` defines `SUBSCRIPTION_ID`, `TENANT_ID`, `ALLOWED_GROUP_IDS` (used by Task 3). Each `main.bicepparam` has `param workload = '...'`, `param instance = '...'`, `param location = '...'` on one line each (the script reads them with `sed`).

- [ ] **Step 1: Write `dev/main.bicepparam`** from the with-storage Bicep twin's dev file, minus the file-library block, with the same values as `infrastructure/privately-accessible-static-website/environments/dev/terraform.tfvars`. Keep `entraClientId` and `entraClientSecret` reading from `readEnvironmentVariable`, and `allowedGroupIds` from `ALLOWED_GROUP_IDS` split on commas, empty-safe.
- [ ] **Step 2: Write qa, uat, prod** by copying the corresponding Terraform tfvars values (budget, retention days, `enableDeleteLock`, `probeZoneRedundancyEnabled`, address ranges). Expected: uat and prod have delete lock and zone redundancy true; prod has monitoring on.
- [ ] **Step 3: Write the four `deployment.env` files** with placeholder IDs in the same style as the twin, and a comment line saying which values the platform team provides.
- [ ] **Step 4: Verify.** For each environment run, with `ENTRA_CLIENT_ID=00000000-0000-0000-0000-000000000000 ENTRA_CLIENT_SECRET=x` set and `ALLOWED_GROUP_IDS` unset, `az bicep build-params --file environments/<env>/main.bicepparam`. Expected: exit 0 for all four (this covers the empty-groups case).
- [ ] **Checkpoint:** commit `feat: add environment parameter files for the Bicep template`.

### Task 3: Deploy scripts

**Files:**
- Create: `scripts/deploy.sh`, `scripts/deploy.ps1`

**Interfaces:**
- Consumes: Task 2 `deployment.env` and `main.bicepparam` conventions; Task 1 outputs `staticWebAppHostName`, `staticWebAppName`, `resourceGroupName`, `staticWebAppConfigJson`.
- Produces: command `deploy.sh <env> <what-if|deploy|show|delete>` (same for `deploy.ps1 -Environment <env> -Command <...>`), used by Task 4 pipelines and the Task 5 README.

- [ ] **Step 1: Copy the twin's `deploy.sh`** and remove the storage API constants, the `requiredResourceAccesses` argument on `az ad app create`, the `spa.redirectUris` setting, and the `files.html` redirect. Keep the web redirect URI `https://$host/.auth/login/aad/callback`. Update the usage line to the new folder name. Step 3 in the closing hint (admin consent) is removed; the closing hint lists the secrets `AZURE_STATIC_WEB_APPS_API_TOKEN` and `SWA_CONFIG_JSON` only.
- [ ] **Step 2: Make it non-interactive friendly.** It must work under `AzureCLI@2` (already logged in): no prompts, `--yes` on stack commands, exit non-zero on failure.
- [ ] **Step 3: Port to `deploy.ps1`** with identical behaviour, following the structure of the twin's `deploy.ps1` with the same removals.
- [ ] **Step 4: Verify.** Run `bash -n scripts/deploy.sh`. Expected: no output. Run `shellcheck scripts/deploy.sh` if installed. Run `pwsh -NoProfile -Command "[void][scriptblock]::Create((Get-Content -Raw scripts/deploy.ps1))"` (or `powershell` if `pwsh` is absent). Expected: no error. Run `scripts/deploy.sh dev nonsense`. Expected: "Unknown command" and exit 1. Read the script to confirm an unset `ALLOWED_GROUP_IDS` skips group assignment without failing.
- [ ] **Checkpoint:** commit `feat: add deploy scripts for the Bicep template`.

### Task 4: Azure DevOps pipelines

**Files:**
- Create: `pipelines/azure-pipelines-infra.yml`, `pipelines/azure-pipelines-content.yml`

**Interfaces:**
- Consumes: Task 3 `deploy.sh`.
- Produces: pipeline names, variable group `swa-internal-deployment`, environments `swa-internal-production` (content) and `swa-internal-infra-<env>` (infrastructure), service connection names `sc-swa-internal-<env>`. Task 5 documents exactly these names.

- [ ] **Step 1: `azure-pipelines-infra.yml`.** Parameters: `environment` (values dev, qa, uat, prod), `agentPool` (default `ubuntu-latest` as vmImage; string, selects `pool: name:` when not the default). Trigger on changes under `infrastructure/privately-accessible-static-website-bicep/**` for `main`. Stages: `Validate` (install Bicep through `az bicep install`, then `az bicep build` and `az bicep lint` on `main.bicep`, build-params on the chosen environment's file with placeholder Entra env vars), `WhatIf` (`AzureCLI@2` with `azureSubscription: sc-swa-internal-${{ parameters.environment }}`, runs `deploy.sh <env> what-if`), `Deploy` (deployment job on environment `swa-internal-infra-${{ parameters.environment }}`, runs `deploy.sh <env> deploy`). Header comment lists the one-time setup, the same style as the Terraform twin's pipeline.
- [ ] **Step 2: `azure-pipelines-content.yml`.** Copy `infrastructure/privately-accessible-static-website/pipelines/azure-pipelines.yml`, change only the path in the comment and the trigger path to this template's pipeline file, and add the same `agentPool` parameter. Header comment: the secret `AZURE_STATIC_WEB_APPS_API_TOKEN` and `SWA_CONFIG_JSON` come from `deploy.sh <env> show`, not `terraform output`.
- [ ] **Step 3: Verify.** Parse both with `python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" <file>`. Expected: no error. Read each file and confirm: the infra pipeline's Deploy stage depends on WhatIf; the content pipeline still has Build, Preview and Release stages with the same conditions as the Terraform twin; the pool parameter is used in both.
- [ ] **Checkpoint:** commit `feat: add Azure DevOps pipelines for the Bicep template`.

### Task 5: Documentation and diagrams

**Files:**
- Create: `README.md`, `ARCHITECTURE.md`, `c4-context.drawio`, `c4-containers.drawio`

**Interfaces:**
- Consumes: names from Tasks 1 to 4.

- [ ] **Step 1: `README.md`** follows the sections of the Terraform twin's README (intro, differences from public, Design decisions table with Concern, Decision, Why, Trade-off including an "Availability zones" row, Cost estimate, Folder layout, Monitoring, Sign-in, What the platform team must do, To verify in dev). Differences: Bicep wording (deployment stack replaces state, `deploy.sh` creates the Entra app), the "Entra app by script" trade-off row, and a title naming the Terraform twin.
- [ ] **Step 2: Cost estimate.** Re-price from `https://prices.azure.com/api/retail/prices` (West Europe, Static Web Apps Standard, private endpoint hours and data, Private DNS zones, Container Apps environment meter, alerts) using `WebFetch` or `curl`. Use the date of retrieval. Resources equal the Terraform twin, so totals should be about $29 a month; state any difference.
- [ ] **Step 3: "Deploy with Azure DevOps" section** with the nine numbered steps from the spec's step-by-step, using the exact names from Task 4. Each step says what to click or run and what to expect. Include the Graph-rights fallback and the self-hosted-agent fallback, each with its trade-off.
- [ ] **Step 4: `ARCHITECTURE.md`** with C4 context, containers and components in Mermaid, modelled on the Terraform twin's `ARCHITECTURE.md` with Terraform replaced by Bicep.
- [ ] **Step 5: Diagrams.** Invoke the `c4-drawio` skill to generate `c4-context.drawio` and `c4-containers.drawio`, based on the Terraform twin's diagrams, including the "Why pick this design, and its trade-offs" and "What to keep in mind" panels with the cost line.
- [ ] **Step 6: Verify.** Check every relative link in the README and ARCHITECTURE resolves (`grep -o '](\.[^)]*)'` and test each path). Confirm each `.drawio` parses as XML (`python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1])" <file>`). Confirm no file contains "storage account" or "file library" (`grep -ril`). Expected: nothing found.
- [ ] **Checkpoint:** commit `docs: add README, architecture and C4 diagrams for the Bicep template`.

### Task 6: Catalogue and repo updates, final verification

**Files:**
- Modify: `CLAUDE.md` (template table), `GOLDEN-TEMPLATES.md`, and any `.github/workflows/` or `.impeccable/` file that lists templates or content paths.

- [ ] **Step 1: `CLAUDE.md`.** Add a row to the template table: "Private (internal) static website, Bicep", `infrastructure/privately-accessible-static-website-bicep/`, content `content/privately-accessible-static-website/` (shared with the Terraform version).
- [ ] **Step 2: `GOLDEN-TEMPLATES.md`.** Add the template to the catalogue in the same format as the other Bicep entry, with the same "still needed before publishing" items.
- [ ] **Step 3: Search for path lists.** `grep -rn "privately-accessible-static-website-with-storage-bicep" .github .impeccable GOLDEN-TEMPLATES.md CLAUDE.md`. For each place that enumerates templates, decide whether the new one belongs; add it if so.
- [ ] **Step 4: Final verification** (run all, report actual output): `az bicep build` and `az bicep lint` on `main.bicep`; `az bicep build-params` for all four environments; YAML parse of both pipelines; `bash -n` on `deploy.sh`; `grep -rniE "storage|blob" infrastructure/privately-accessible-static-website-bicep` and confirm remaining hits are only Azure Monitor's blob DNS zone and `Microsoft.Storage` mentions that Azure Monitor needs; `git status` shows only intended files.
- [ ] **Checkpoint:** commit `docs: list the Bicep private static website in the catalogue`.
