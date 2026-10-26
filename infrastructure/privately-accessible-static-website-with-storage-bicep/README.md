# Privately accessible static website with storage (Bicep)

> **Golden template candidate.** See [../../GOLDEN-TEMPLATES.md](../../GOLDEN-TEMPLATES.md) for what still has to happen before it is published as one.

This is the **Bicep version** of [../privately-accessible-static-website-with-storage](../privately-accessible-static-website-with-storage) (Terraform). It deploys the same design: an internal static website behind a private endpoint with APEX Entra sign-in, plus a shared file library in private Blob storage that signed-in users reach with their own token. No database, no server code, nothing exposed to the internet.

Read the Terraform README for the full picture: what the file library does, who can do what, the file library page, and the first-time admin steps. This README covers what is specific to Bicep. It deploys the same site content, `content/privately-accessible-static-website-with-storage/`, and its architecture is the same (see [ARCHITECTURE.md](ARCHITECTURE.md), [c4-context.drawio](c4-context.drawio) and [c4-containers.drawio](c4-containers.drawio)).

**Keep the two in step.** A change to the design is made in both templates: same resources, same names, same parameters.

```
az login ─▶ scripts/deploy.sh <env> deploy
              ├─ 1. Entra app registration + client secret + allowed groups   (az ad ...)
              ├─ 2. main.bicep as a deployment stack, subscription scope      (az stack sub create)
              └─ 3. app registration redirect URIs, from the site's host name (az ad app update)
```

## Where each part lives

| Part | Terraform | Bicep |
| --- | --- | --- |
| Entry point | `stacks/static-website/main.tf` | `main.bicep` (subscription scope: creates the resource group, then every module inside it) |
| Names | `modules/naming` | `modules/naming.bicep` (exported functions, see the decision below) |
| Network, DNS zones, peering | `modules/network` | `modules/network.bicep` |
| Private endpoint | `modules/private-endpoint` | `modules/private-endpoint.bicep` |
| Static Web App | `modules/static-web-app` | `modules/static-web-app.bicep`, `modules/site-private-link.bicep` (the app's own DNS zone and endpoint) |
| File library | `modules/storage` | `modules/storage.bicep` |
| Sign-in | `modules/entra-app-auth` | `scripts/deploy.sh`, `deploy.ps1` |
| Monitoring | `modules/monitoring` | `modules/monitoring.bicep` |
| Monitor Private Link | `modules/monitor-private-link` | `modules/monitor-private-link.bicep` |
| Availability probe | `modules/availability-probe` | `modules/availability-probe.bicep`, `modules/probe.sh` |
| Lock and budget | in the stack | `modules/governance.bicep` |
| Settings per environment | `environments/<env>/terraform.tfvars`, `backend.hcl` | `environments/<env>/main.bicepparam`, `deployment.env` |
| Deploy | `scripts/tf.sh`, `tf.ps1` | `scripts/deploy.sh`, `deploy.ps1` |
| Checks without Azure | `terraform validate`, `terraform test` | `bicep build`, the linter (rules are errors in `bicepconfig.json`) |

## Design decisions

The design is the same as the Terraform template's, so its table applies (region, subnets, entry, network, sign-in, the file access path, storage account, who can do what, recovery, malware scanning, upload limits, availability, telemetry, alerts, dashboard access, governance). These are the decisions that are specific to Bicep.

| Concern | Decision | Why | Trade-off |
| --- | --- | --- | --- |
| Availability zones | The same as the Terraform template: `probeZoneRedundancyEnabled` for the probe's Container Apps environment (on in uat and prod), and `storageReplicationType` for the file library (ZRS in dev and qa, GZRS in uat and prod). The Static Web App, private endpoints and Private DNS have no zone setting | A zone failure should not silence the probe or take the files offline in prod | The probe setting is fixed at creation. GZRS costs about twice ZRS per GB. Switching replication type later is a migration, not an edit |
| State | A **deployment stack** per environment (`az stack sub create`, named `stack-<workload>-<env>`) with `--action-on-unmanage deleteAll`. uat and prod also use `--deny-settings-mode denyDelete` | A stack removes what you remove from the template, like Terraform state does, and needs no storage account to bootstrap. It keeps each environment in its own subscription | The stack is the only record: there is no plan file and no `bootstrap/`. `what-if` shows the change, but stacks have no plan of their own. Deny settings also block operators in uat and prod until the stack is changed |
| Entra app registration | Created by `scripts/deploy.sh` with the Azure CLI (app, service principal, assignment required, groups, a fresh secret, redirect URIs), not by Bicep. The client ID and secret reach Bicep through environment variables | Bicep's Microsoft Graph extension cannot create client secrets, and the Static Web App needs one | The secret is replaced on **every** deploy, and the app registration is not in the stack: deleting the stack leaves it in Entra. Terraform rotates the secret every 180 days instead. The deployer needs Entra rights to create apps and assign groups |
| Allowed groups | `ALLOWED_GROUP_IDS` in `environments/<env>/deployment.env`, read by the script and by `main.bicepparam` | The script assigns the groups to the app, and Bicep gives the same groups the file library role: one list for both | Terraform keeps the list in `terraform.tfvars` instead; keep the two aligned when you copy settings |
| Names | `modules/naming.bicep` holds exported functions, used with `import * as naming`. The storage account name carries 4 characters of `uniqueString(subscription ID)` | A resource name must be known when the deployment starts, and a module output is not | Same names as Terraform, except the 4-character hash, which differs. Do not deploy both templates into one environment |
| Prod rules | Prod forces monitoring and malware scanning **on**, whatever the parameter file says | Bicep has no check that stops a deployment, so it enforces the rule instead of refusing | A parameter file that says `false` in prod is silently overridden. Terraform refuses it with an error |
| Checks | `bicep build` and the linter, with rules set to errors. There are no mocked tests | The Bicep toolchain has no mock framework for these checks | Weaker than Terraform's `terraform test`: nothing proves "never public" or "keys off" other than reading the template. Review `what-if` output before every deploy |
| Dashboard | The workbook has the availability and alert panels. The Front Door panels of the Terraform workbook are left out | The private design has no Front Door, so those panels would be empty | A small difference between the two templates' dashboards |

## Cost estimate

The Bicep and Terraform templates deploy the same resources, so the cost is the same. Retail list prices in USD for West Europe from the [Azure Retail Prices API](https://prices.azure.com/api/retail/prices), retrieved on 2026-10-26, for 100 GB stored, 10,000 writes, 100,000 reads and 5 GB uploaded a month. Taxes, discounts and currency conversion are not included.

| Item | dev, qa (ZRS, no scanning) | uat, prod (GZRS, scanning) |
| --- | --- | --- |
| Static Web App, Standard ($9) | $9.00 | $9.00 |
| 3 private endpoints at $0.01 an hour | $21.90 | $21.90 |
| 6 Private DNS zones at $0.50 | $3.00 | $3.00 |
| Blob data, writes and reads (ZRS $0.024, GZRS $0.046 per GB) | $2.51 | $4.76 |
| Defender for Storage plan ($0.006849 an hour) and scanning ($0.15 per GB) | $0 | $5.75 |
| Alerts | about $2 | about $2 |
| Probe, Log Analytics (first 5 GB free), VNet, role, budget | $0 | $0 |
| **Total** | **about $38** | **about $46** |

Traffic-driven: storage per GB, writes and reads, and scanning per GB uploaded. Budgets in the parameter files are 100, 150, 200 and 300 a month. The meters still to confirm are listed in the Terraform README's cost section (the Container Apps environment hour, and what Defender bills when only malware scanning is on).

## Folder layout

```
infrastructure/privately-accessible-static-website-with-storage-bicep/
├── main.bicep                 Subscription scope: resource group, then the modules
├── bicepconfig.json           Linter rules as errors
├── modules/                   naming (functions), network, private-endpoint, static-web-app,
│                              site-private-link, storage, monitoring, monitor-private-link,
│                              availability-probe (+ probe.sh), governance
├── environments/dev|qa|uat|prod/  main.bicepparam + deployment.env
├── scripts/deploy.sh · deploy.ps1
├── ARCHITECTURE.md
├── c4-context.drawio · c4-containers.drawio
└── .gitignore
```

## First-time setup

1. In `environments/<env>/deployment.env` set the subscription, the tenant and `ALLOWED_GROUP_IDS`. In `main.bicepparam` set the governance tags, the IP ranges from the APEX IP plan, the alert receivers and the viewer and operator groups. Replace every `<...>` placeholder.
2. **Identity for the deployment:** the same roles as the Terraform template (Contributor and User Access Administrator on the subscription, Security Admin for malware scanning, Network Contributor on the hub if you set `hubVirtualNetworkId`), plus Entra rights to create app registrations and assign groups. Deployment stacks need Azure CLI 2.61 or later.
3. Review, then deploy:
   ```
   ./privately-accessible-static-website-with-storage-bicep/scripts/deploy.sh dev what-if
   ./privately-accessible-static-website-with-storage-bicep/scripts/deploy.sh dev deploy
   ```
   PowerShell: `./privately-accessible-static-website-with-storage-bicep/scripts/deploy.ps1 -Environment dev -Command deploy`
4. Do what the script prints at the end: grant admin consent for the Azure Storage permission, and store the pipeline secrets.
5. **Delivery:** the site is the same content folder as the Terraform template's, so its pipelines deploy it: `.github/workflows/deploy-internal-static-web-app-with-storage.yml` and `infrastructure/privately-accessible-static-website-with-storage/pipelines/azure-pipelines.yml`. Their secret names are listed in the Terraform README.

Platform-team items (hub peering, corporate DNS for the `privatelink` zones, central DNS zones in a landing zone) are the same as in the Terraform template. `./deploy.sh <env> show` prints the outputs, including `privateDnsZones`.

## Not included

- Everything in the Terraform template's "Not included" list.
- An infrastructure pipeline (plan on pull request, apply with approval). The same gap is on the golden-template list for Terraform.
- Teardown of the Entra app registration: `deploy.sh <env> delete` removes the stack but leaves the registration.

## To verify in dev before production

`bicep build` and the linter pass for `main.bicep` and for all four `main.bicepparam` files. **Nothing has been run against Azure**, not even `what-if`. Check these first:

- `az stack sub create` with `--deny-settings-mode` and a `.bicepparam` file on your Azure CLI version, and `readEnvironmentVariable()` in the parameter files.
- The `deploy.sh` flow end to end: app registration, groups, secret, redirect URIs.
- The custom role and its assignment right after creation (role definitions can take a moment to replicate; a first deploy may need a re-run).
- `Microsoft.Security/defenderForStorageSettings` on a subscription that already has Defender for Storage settings.
- Everything on the Terraform README's "To verify" list that is about the design rather than the tool: the file library page, CORS for previews, deployment with public access off.
