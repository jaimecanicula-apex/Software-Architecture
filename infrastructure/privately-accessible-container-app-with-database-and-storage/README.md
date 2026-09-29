# Privately accessible container app with database and storage (Terraform)

> **Golden template candidate.** This folder is written to become an APEX golden template. See [../../GOLDEN-TEMPLATES.md](../../GOLDEN-TEMPLATES.md) for what still has to happen before it is published as one.

Use this design to run a **containerised backend application for internal users only** that needs its own database, its own image storage, and its own app-level username/password login — the [privately-accessible-container-app](../privately-accessible-container-app/) template's sibling, for a stateful workload instead of a stateless one. Users open an internal URL from the corporate network, sign in with Entra ID, and then sign in again to the app itself. Nothing is reachable from the internet, and nobody installs a runtime locally.

The example workload is [content/python-crud-app](../../content/python-crud-app): a Flask asset catalogue. Any image works that listens on port 8000, answers `GET /healthz`, and speaks to PostgreSQL and Blob storage the way that example does.

```
User on the corporate network ──hub peering + private DNS──▶ internal load balancer
   ──▶ Container App (Entra sign-in, assigned groups only) ──▶ app login (username/password)
   ──▶ container, port 8000
Container App ──managed identity──▶ Key Vault (DB password, session secret, seed passwords)
Container App ──password from Key Vault──▶ PostgreSQL Flexible Server (VNet-integrated)
Container App ──managed identity, no keys──▶ Blob storage (private endpoint)
Container logs ──▶ Log Analytics      Traces, requests and exceptions ──▶ Application Insights ──▶ alerts
Delivery pipeline ──az acr build──▶ Container Registry ◀──AcrPull (managed identity)── Container App
```

## Design decisions

| Concern | Decision | Why | Trade-off |
| --- | --- | --- | --- |
| Region | `location`, required in every environment's `terraform.tfvars` (no default) | Data residency and latency are choices per organisation and environment; a silent default could place an environment in the wrong region | Changing it later recreates every regional resource. For zone redundancy the region must have availability zones |
| Availability zones | `zone_redundancy_enabled` spreads the Container Apps environment and its replicas across zones: on in uat and prod, with `min_replicas = 2`. `registry_zone_redundancy_enabled` does the same for a Premium registry. `postgresql_ha_enabled` and `storage_replication_type` are the matching knobs for the database and images — see the two rows below. The Terraform state storage is zone- and geo-redundant (GZRS) through `replication_type` in `bootstrap/` | In prod a zone failure leaves a replica serving while the platform replaces the other; uat rehearses the same layout. A check warns when zone redundancy runs with one replica, where it gains little | Fixed at creation: switching it recreates the environment. The second always-on replica costs about $32 a month per environment. Registry zone redundancy needs Premium, about $51 a month instead of $5 |
| Subnets | Three subnets, all from `terraform.tfvars`, all named by the naming module: `snet-cae-<suffix>` (Container Apps, delegated), `snet-pg-<suffix>` (PostgreSQL, delegated), `snet-pe-<suffix>` (Key Vault and Storage private endpoints) | Address ranges come from each environment's IP plan; a delegated subnet can only host the service it's delegated to, so PostgreSQL and Container Apps can't share one | Three subnets to plan instead of one; each needs its own NSG |
| Hosting | Azure Container Apps, workload-profiles environment on the Consumption profile, **internal load balancer only**, in a spoke subnet | Runs any container image with no App Service plan to size and no Kubernetes cluster to run. The internal load balancer gives the app no public address, because every user is internal | Anyone off the corporate network (partners, home without VPN) cannot reach it. Less control than AKS (no custom sidecars or cluster add-ons), and the environment needs its own delegated /27 subnet |
| Internal URL | `https://<app>.<environment domain>`. A Private DNS zone for the environment domain is linked to the spoke and, when set, the hub | The environment's domain exists only in private DNS, so the name resolves only on the spoke, the hub and networks that use the hub's DNS | Depends on the platform team's DNS, and users see the environment's generated domain, not a friendly custom name |
| Sign-in | Two layers: Container Apps built-in authentication with an Entra app registration (**assignment required**: only the groups in `allowed_group_ids`), then the Flask app's own username/password login (session cookie, lockout after 5 failed attempts) behind it | The request needs app-level credentials and roles (admin/user), not just network-position trust; Entra keeps outsiders out first and the app never handles the Entra token itself | Two sign-ins for every user, and the app now owns a password database it must hash and lock out correctly. `/healthz` stays open at both layers so the platform's health probes work |
| Image | Azure Container Registry, Basic tier, admin user off. The app pulls with a user-assigned managed identity (AcrPull) | Admin off and a managed identity mean no registry password to store or rotate. Basic is enough for one small app; a private registry would need Premium | The Basic registry keeps a public endpoint and has no geo-replication; moving to Premium later adds cost and a private endpoint to manage |
| Database | Azure Database for PostgreSQL Flexible Server, VNet-integrated (delegated subnet, no public network access). `postgresql_ha_enabled` off in dev/qa, zone-redundant HA in uat/prod (needs a General Purpose or Memory Optimized `postgresql_sku_name`, never Burstable) | VNet integration keeps the database off the internet entirely; HA in uat/prod rehearses and covers a zone failure | Zone-redundant HA needs a non-Burstable SKU (about 10x a Burstable instance's cost) and doubles compute cost while it's on |
| Database credential | One administrator credential, generated by Terraform (`random_password`) and stored in Key Vault, used by both Terraform (to create the database) and the app (to connect) | Avoids a second Terraform provider — and the network path it would need into a private-only server — just to create a second, more restricted role | Not least-privilege: the app connects with the same credential Terraform uses. Acceptable because nothing else connects to this server; add a scoped role if that changes |
| Secrets | Terraform generates the DB password, Flask session key and seed users' passwords with `random_password` and writes them to a dedicated Key Vault (RBAC, private endpoint, no public access by default). The container app reads them as Key Vault-referenced secrets through its managed identity, alongside the sign-in secret and Application Insights connection string | Nothing sensitive sits in `terraform.tfvars` or the container image; rotation is a Terraform re-apply | Terraform's own write to the vault needs `key_vault_allowed_ip_ranges` opened during apply, or a self-hosted agent inside the spoke — the vault can't be both "write-only from Terraform" and "no public access at all" on the very first apply |
| Images (files) | Blob storage, private endpoint only, `shared_access_key_enabled = false` — the app reads and writes with its managed identity, never an account key. Replication is `storage_replication_type` (ZRS dev/qa, GZRS uat/prod) | No storage key to leak or rotate; matches the "storage redundancy is always a variable" rule | The role assignment (Storage Blob Data Contributor) is scoped to the whole account, not just the `images` container — the built-in role doesn't support container-level scoping |
| Logging | Container console and system logs go to Log Analytics; the app sends distributed traces (requests and dependencies), exceptions and logs to Application Insights with OpenTelemetry. PostgreSQL, Key Vault and storage also send diagnostics to Log Analytics. Alerts on container restarts, 5xx responses, PostgreSQL CPU and blob storage capacity | Console logs work for any app with no code; OpenTelemetry adds traces that show where a slow or failed request spent its time. The extra alerts catch the two ways the database or storage typically degrade | Telemetry uses a connection-string key over a public endpoint, ingestion cost grows with traffic, and there is no synthetic availability test from users' networks |
| Scale | Always on: 1 replica in dev and qa, 2 in uat and prod (`min_replicas`), one per zone. Set 0 in dev to save cost if a cold start after idle is acceptable | A warm replica avoids a cold start on the first request. Two replicas in uat and prod keep serving through a crash, a platform update or a zone failure — the app itself keeps no local state, only PostgreSQL and Blob storage do | Dev and qa with one replica have short outages on a crash or platform update. Always-on pays for idle hours: the second replica adds about $32 a month |
| Governance | Mandatory tags, budget, delete lock in uat and prod, read-only monitoring access for `monitoring_viewer_principal_ids` | Required for every golden template: tags show owner and cost centre, the budget warns before overspend, the lock stops accidental deletion where it matters, and viewers can read monitoring without changing anything | The lock also blocks legitimate teardown until removed through change control, and a budget only warns; it never stops spending |

## Cost estimate

Retail list prices in USD for West Europe from the Azure Retail Prices API, the data source of the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/), retrieved on 2026-09-28. A month is 730 hours. Taxes, discounts, reservations and currency conversion are not included; re-check in the calculator before committing a budget.

Per environment, with low traffic and the settings in `terraform.tfvars`: 1 vCPU and 2 GiB per Container Apps replica, `min_replicas = 1` in dev and qa, `min_replicas = 2` with zone redundancy in uat and prod; PostgreSQL Burstable B1ms in dev/qa, zone-redundant General Purpose D2ds_v5 in uat/prod; a few GiB of images in Blob storage. Each environment has its own subscription, so each gets the Container Apps monthly free grant.

**Carried over unchanged from the sibling template** (Container Apps compute, Container Registry, Private DNS zone for the environment domain, container-restart/5xx alerts, Log Analytics/Application Insights, VNet/NSG/identity/Entra app/budget): about **$35** in dev/qa and **$67** in uat/prod, mostly idle. See [../privately-accessible-container-app/README.md](../privately-accessible-container-app/README.md#cost-estimate) for the line-by-line breakdown.

**New for this template:**

| Item | Price used | Dev/QA monthly | UAT/Prod monthly |
| --- | --- | --- | --- |
| PostgreSQL compute | Burstable B1ms $0.0199/hr, or General Purpose D2ds_v5 $0.212/hr × 2 (zone-redundant HA) | ~$14.53 | ~$309.52 |
| PostgreSQL storage | Premium SSD $0.1369/GiB-month, 32 GiB | ~$4.38 | ~$4.38+ |
| PostgreSQL backup storage | LRS $0.103/GiB-month (dev/qa); geo-redundant backup roughly doubles it in prod | ~$1–3 | ~$3–8 |
| Key Vault | Standard, $0.03 per 10K operations | <$1 | <$1 |
| Blob storage (images) | Hot LRS $0.0196/GiB-month (dev/qa), Hot GZRS ~$0.046/GiB-month (uat/prod); a few GiB of images | <$1 | ~$1–2 |
| Private endpoints (Key Vault, Storage) | Published rate ~$0.01/hr per endpoint + data processed, 2 endpoints | ~$14.60 | ~$14.60+ |
| **New total** | | **~$35–43** | **~$333–345** |
| **Existing template's total** (Container Apps, Registry, DNS, alerts, monitoring) | | ~$35 | ~$67 |
| **Combined total, mostly idle** | | **~$70–78/month** | **~$400–410/month** |

The jump from dev/qa to uat/prod is dominated by zone-redundant PostgreSQL HA (two D2ds_v5 instances instead of one Burstable) — the same shape as the Container Apps replica cost in the sibling template, just larger. Re-check all prices in the calculator before committing a budget; the private-endpoint data-processing meter and the exact PostgreSQL backup-storage-included allowance are the two figures still worth confirming.

- **Cheapest option:** `min_replicas = 0` on Container Apps and Burstable PostgreSQL with HA off (the dev/qa default) keep this close to the sibling template's own cost.
- **Budgets** (75, 100, 450, 500) cover the idle estimate in every environment.
- **State storage:** GZRS instead of GRS changes a few cents a month for a state file of a few megabytes.

## Folder layout

```
privately-accessible-container-app-with-database-and-storage/
├── ARCHITECTURE.md             C4 model (Mermaid)
├── c4-context.drawio · c4-containers.drawio   C4 levels 1 and 2 in draw.io
├── bootstrap/                  One-time: storage account for Terraform remote state
├── modules/
│   ├── naming/                 <type>-<workload>-<env>-<region>-<instance>
│   ├── network/                Spoke VNet, three delegated/private-endpoint subnets, NSGs, hub peering
│   ├── container-app/          Registry, identity, internal environment, private DNS, the app
│   ├── entra-app-auth/         App registration, assignment required, allowed groups
│   ├── monitoring/              Log Analytics, Application Insights, Action Group, viewer access, diagnostics
│   ├── postgresql/              VNet-integrated PostgreSQL Flexible Server + database
│   ├── key-vault/               Generated secrets, RBAC, private endpoint
│   └── storage/                 Blob storage for images, private endpoint, no account key
├── stacks/container-app-with-database-and-storage/   Root module (one stack, many environments) + tests/
├── environments/<env>/         terraform.tfvars + backend.hcl for dev, qa, uat, prod
├── pipelines/azure-pipelines.yml   Test, build with ACR Tasks, deploy the image
└── scripts/tf.sh · tf.ps1      ./infrastructure/privately-accessible-container-app-with-database-and-storage/scripts/tf.sh dev plan
```

## First-time setup

The registry is empty on the first apply, so the app is created in a second pass. The database, storage account and Key Vault are all created on the **first** apply, since they don't depend on an image existing.

1. **State storage**, once per state subscription:
   ```
   cd infrastructure/privately-accessible-container-app-with-database-and-storage/bootstrap
   cp example.tfvars dev.tfvars    # edit it
   terraform init
   terraform apply -var-file=dev.tfvars
   ```
   Copy the `backend_config` output into `environments/dev/backend.hcl`.
2. **Settings:** fill in `environments/dev/terraform.tfvars`: subscription, tenant, tags, address ranges from the IP plan (three subnets now, not one), the hub VNet and DNS servers, the Entra group of testers, alert emails. Keep `create_container_app = false`. If Terraform won't run from inside the spoke's network, set `key_vault_allowed_ip_ranges` to the deploying machine's or agent's public IP so the first apply can write the generated secrets.
3. **Sign in** with `az login`. The identity needs Contributor and User Access Administrator on the subscription (for the AcrPull and Key Vault/Storage role assignments), Storage Blob Data Contributor on the state account, and the right to create Entra app registrations.
4. **Platform:**
   ```
   ./infrastructure/privately-accessible-container-app-with-database-and-storage/scripts/tf.sh dev init
   ./infrastructure/privately-accessible-container-app-with-database-and-storage/scripts/tf.sh dev plan
   ./infrastructure/privately-accessible-container-app-with-database-and-storage/scripts/tf.sh dev apply
   ```
5. **First image:**
   ```
   az acr build --registry <registry name> --image python-crud-app:initial content/python-crud-app
   ```
   The registry name is the host part of the `registry_login_server` output.
6. **App:** set `create_container_app = true`, then run plan and apply again. The `app_url` output is the internal URL. The app seeds an admin and a demo user from the Key Vault-sourced `SEED_ADMIN_PASSWORD`/`SEED_DEMO_PASSWORD` on first startup.
7. **First sign-in:** read the generated admin password back out of the vault (the `key_vault_id` output names it; the identity reading it needs `Key Vault Secrets User` or higher, the same role the app's managed identity has):
   ```
   az keyvault secret show --vault-name <key vault name> --name seed-admin-password --query value -o tsv
   ```
   Sign in at `app_url` as `admin` with that password (the `SEED_ADMIN_USERNAME` tfvar, default `admin`), then change it or create named accounts from **Users** in the app and delete the seed accounts.
8. **DNS in the hub:** give the platform team the `environment_dns` output. They must make the corporate DNS resolve that zone: link it to the hub, or forward it to the hub's DNS resolver.

## Delivering new versions

Set up `pipelines/azure-pipelines.yml` in Azure DevOps (the steps are in its header). On every merge to `main` it runs the tests, builds the image with ACR Tasks, and after approval points the app at the new image. Terraform ignores the image after the first apply, so the two never conflict.

## Notes

- Validated with Terraform 1.16, azurerm 4.81 and azapi 2.12 (`terraform validate` and `terraform test` with mocked providers). Nothing has been planned or applied against Azure yet.
- `azapi` is used only for the sign-in settings (`Microsoft.App/containerApps/authConfigs`), which azurerm does not cover.
- Not published as a separate GOLDEN-TEMPLATES.md row target for a public counterpart: a stateful workload with its own login is inherently internal-only in this catalogue.
