# Privately accessible container app (Terraform)

> **Golden template candidate.** This folder is written to become an APEX golden template. See [../../GOLDEN-TEMPLATES.md](../../GOLDEN-TEMPLATES.md) for what still has to happen before it is published as one.

Use this design to run a **containerised backend application for internal users only**, for example a Python web app for a small group of testers. Users open an internal URL from the corporate network and sign in with Entra ID. Nothing is reachable from the internet, and nobody installs a runtime locally.

The example workload is [content/python-mvc-app](../../content/python-mvc-app). Any image works that listens on port 8000 and answers `GET /healthz`.

```
User on the corporate network ──hub peering + private DNS──▶ internal load balancer
   ──▶ Container App (Entra sign-in, assigned groups only) ──▶ container, port 8000
Container logs ──▶ Log Analytics      Traces, requests and exceptions ──▶ Application Insights ──▶ alerts
Delivery pipeline ──az acr build──▶ Container Registry ◀──AcrPull (managed identity)── Container App
```

## Design decisions

| Concern | Decision | Why | Trade-off |
| --- | --- | --- | --- |
| Region | `location`, required in every environment's `terraform.tfvars` (no default) | Data residency and latency are choices per organisation and environment; a silent default could place an environment in the wrong region | Changing it later recreates every regional resource. For zone redundancy the region must have availability zones |
| Availability zones | `zone_redundancy_enabled` spreads the Container Apps environment and its replicas across zones: on in uat and prod, with `min_replicas = 2`. `registry_zone_redundancy_enabled` does the same for a Premium registry. The Terraform state storage is zone- and geo-redundant (GZRS) through `replication_type` in `bootstrap/` | In prod a zone failure leaves a replica serving while the platform replaces the other; uat rehearses the same layout. A check warns when zone redundancy runs with one replica, where it gains little | Fixed at creation: switching it recreates the environment. The second always-on replica costs about $32 a month per environment. Registry zone redundancy needs Premium, about $51 a month instead of $5 |
| Subnets | One subnet delegated to `Microsoft.App/environments`; prefix from `container_apps_subnet_prefix`, name `snet-cae-<suffix>` and NSG `nsg-cae-<suffix>` from the naming module | Address ranges come from each environment's IP plan, and names follow the convention like every other resource | A workload-profiles environment needs at least a /27 to itself; the subnet cannot host other resources |
| Hosting | Azure Container Apps, workload-profiles environment on the Consumption profile, **internal load balancer only**, in a spoke subnet | Runs any container image with no App Service plan to size and no Kubernetes cluster to run. The internal load balancer gives the app no public address, because every user is internal | Anyone off the corporate network (partners, home without VPN) cannot reach it. Less control than AKS (no custom sidecars or cluster add-ons), and the environment needs its own delegated /27 subnet |
| Internal URL | `https://<app>.<environment domain>`. A Private DNS zone for the environment domain is linked to the spoke and, when set, the hub | The environment's domain exists only in private DNS, so the name resolves only on the spoke, the hub and networks that use the hub's DNS | Depends on the platform team's DNS, and users see the environment's generated domain, not a friendly custom name |
| Sign-in | Container Apps built-in authentication with an Entra app registration. **Assignment required**: only the groups in `allowed_group_ids` can sign in. `/healthz` is the only anonymous path | Azure signs users in before the app sees a request, so the app never handles passwords or tokens and works in any language. Entra itself refuses anyone outside the allowed groups. `/healthz` stays open so the platform's health probes work | Tied to Entra and to the platform feature: fine-grained roles still need code that reads the claims, and the client secret expires if the environment is not re-applied within about 210 days |
| Image | Azure Container Registry, Basic tier, admin user off. The app pulls with a user-assigned managed identity (AcrPull) | Admin off and a managed identity mean no registry password to store or rotate. Basic is enough for one small app; a private registry would need Premium | The Basic registry keeps a public endpoint and has no geo-replication; moving to Premium later adds cost and a private endpoint to manage |
| Files | No storage account: the web application is expected to be stateless. Add Blob storage only if the app must keep files between requests or run jobs longer than the 240-second request limit | A stateless app can be restarted, moved or scaled out at any time without losing data, and there is no storage to secure or back up | Nothing survives a restart. Any feature that needs files, sessions or long jobs must add storage first |
| Config and secrets | App settings are plain environment variables. The sign-in secret and the Application Insights connection string are container app secrets | Environment variables keep the image the same across dev, qa, uat and prod. Secrets are stored encrypted by the platform and never appear in tfvars or the image | Secret values sit in Terraform state, so the state storage must be locked down. There is no Key Vault, and every settings change creates a new revision (a restart) |
| Logging | Container console and system logs go to Log Analytics; the app sends distributed traces (requests and dependencies), exceptions and logs to Application Insights with OpenTelemetry. Alerts on restarts and on 5xx responses | Console logs work for any app with no code; OpenTelemetry adds traces that show where a slow or failed request spent its time. The two alerts catch crashes and error bursts without tuning | Telemetry uses a connection-string key over a public endpoint, ingestion cost grows with traffic, and there is no synthetic availability test from users' networks |
| Scale | Always on: 1 replica in dev and qa, 2 in uat and prod (`min_replicas`), one per zone. Set 0 in dev to save cost if a cold start after idle is acceptable | A warm replica avoids a cold start on the first request. Two replicas in uat and prod keep serving through a crash, a platform update or a zone failure. The app keeps no state, so scaling out is safe | Dev and qa with one replica have short outages on a crash or platform update. Always-on pays for idle hours: the second replica adds about $32 a month |
| Governance | Mandatory tags, budget, delete lock in uat and prod, read-only monitoring access for `monitoring_viewer_principal_ids` | Required for every golden template: tags show owner and cost centre, the budget warns before overspend, the lock stops accidental deletion where it matters, and viewers can read monitoring without changing anything | The lock also blocks legitimate teardown until removed through change control, and a budget only warns; it never stops spending |

## Cost estimate

Retail list prices in USD for West Europe from the Azure Retail Prices API, the data source of the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/), retrieved on 2026-09-27. A month is 730 hours. Taxes, discounts, reservations and currency conversion are not included; re-check in the calculator before committing a budget.

Per environment, with low traffic and the settings in `terraform.tfvars`: 1 vCPU and 2 GiB per replica, `min_replicas = 1` in dev and qa, `min_replicas = 2` with zone redundancy in uat and prod. Each environment has its own subscription, so each gets the Container Apps monthly free grant (180,000 vCPU-seconds, 360,000 GiB-seconds, 2 million requests).

| Item | Price used | Per month |
| --- | --- | --- |
| Container Apps, 1 replica always on, mostly idle | Idle rate $0.000004 per vCPU-second and per GiB-second, after the free grant | $29.37 |
| Same replica busy all month (upper bound per replica) | Active vCPU $0.000034 per second, memory $0.000004 per GiB-second | $102.81 |
| Second replica in uat and prod, mostly idle | Same idle rate, no free grant left | $31.54 |
| Zone redundancy of the environment (Consumption profile) | No extra charge | $0 |
| Container Registry, Basic | $0.1666 per day, 10 GB storage included | $5.07 |
| Container Registry, Premium (only if `registry_zone_redundancy_enabled`) | $1.6666 per day | $50.70 instead of $5.07 |
| Private DNS zone, 1 | $0.50 per zone | $0.50 |
| Metric alerts, 2, every 5 minutes | $0.15 per rule | $0.30 |
| Log Analytics and Application Insights | First 5 GB a month free per billing account, then $2.99 per GB; 31 days retention included, then $0.13 per GB a month | $0 up to 5 GB |
| VNet, NSG, managed identity, Entra app, budget | No charge | $0 |
| **Total, mostly idle** | | **about $35** in dev and qa; **about $67** in uat and prod |
| **Total, busy all month** | | **about $109** in dev and qa; **about $219** in uat and prod (the second replica gets no free grant) |

- **Cheapest option:** `min_replicas = 0` drops the compute line to nearly $0 for light use, at the cost of a cold start after idle.
- **To confirm:** the price list also has a Container Apps "Environment Management Hour" meter at $0.143 an hour (about $104 a month). Check in the calculator whether it applies to a Consumption-only workload-profiles environment; it is not in the totals above.
- **Budgets** (50, 100, 150, 200) cover the idle estimate in every environment. A prod that is busy all month with 2 replicas would pass 200.
- **State storage:** GZRS instead of GRS changes a few cents a month for a state file of a few megabytes.

## Folder layout

```
privately-accessible-container-app/
├── ARCHITECTURE.md             C4 model (Mermaid)
├── c4-context.drawio · c4-containers.drawio   C4 levels 1 and 2 in draw.io
├── bootstrap/                  One-time: storage account for Terraform remote state
├── modules/
│   ├── naming/                 <type>-<workload>-<env>-<region>-<instance>
│   ├── network/                Spoke VNet, delegated subnet, NSG, hub peering
│   ├── container-app/          Registry, identity, internal environment, private DNS, the app
│   ├── entra-app-auth/         App registration, assignment required, allowed groups
│   └── monitoring/             Log Analytics, Application Insights, Action Group, viewer access
├── stacks/container-app/       Root module (one stack, many environments) + tests/
├── environments/<env>/         terraform.tfvars + backend.hcl for dev, qa, uat, prod
├── pipelines/azure-pipelines.yml   Test, build with ACR Tasks, deploy the image
└── scripts/tf.sh · tf.ps1      ./infrastructure/privately-accessible-container-app/scripts/tf.sh dev plan
```

## First-time setup

The registry is empty on the first apply, so the app is created in a second pass.

1. **State storage**, once per state subscription:
   ```
   cd infrastructure/privately-accessible-container-app/bootstrap
   cp example.tfvars dev.tfvars    # edit it
   terraform init
   terraform apply -var-file=dev.tfvars
   ```
   Copy the `backend_config` output into `environments/dev/backend.hcl`.
2. **Settings:** fill in `environments/dev/terraform.tfvars`: subscription, tenant, tags, address ranges from the IP plan, the hub VNet and DNS servers, the Entra group of testers, alert emails. Keep `create_container_app = false`.
3. **Sign in** with `az login`. The identity needs Contributor and User Access Administrator on the subscription (for the AcrPull role assignment), Storage Blob Data Contributor on the state account, and the right to create Entra app registrations.
4. **Platform:**
   ```
   ./infrastructure/privately-accessible-container-app/scripts/tf.sh dev init
   ./infrastructure/privately-accessible-container-app/scripts/tf.sh dev plan
   ./infrastructure/privately-accessible-container-app/scripts/tf.sh dev apply
   ```
5. **First image:**
   ```
   az acr build --registry <registry name> --image python-mvc-app:initial content/python-mvc-app
   ```
   The registry name is the host part of the `registry_login_server` output.
6. **App:** set `create_container_app = true`, then run plan and apply again. The `app_url` output is the internal URL.
7. **DNS in the hub:** give the platform team the `environment_dns` output. They must make the corporate DNS resolve that zone: link it to the hub, or forward it to the hub's DNS resolver.

## Delivering new versions

Set up `pipelines/azure-pipelines.yml` in Azure DevOps (the steps are in its header). On every merge to `main` it runs the tests, builds the image with ACR Tasks, and after approval points the app at the new image. Terraform ignores the image after the first apply, so the two never conflict.

## Is persistent storage needed?

Not for this design. The web application is generic and expected to be stateless: anything it handles lives in memory for one request, and its configuration ships inside the image or comes from `app_settings`. (The example, `content/python-mvc-app`, works this way.) Add a storage account only if one of these becomes true:

- Users must create or edit data in the app while it runs. Store it in Blob storage (or a database) with managed-identity access, never on the container's local disk or in SQLite on a file share.
- A request takes longer than the 240-second request limit. Run the work in the background, write the output to a private Blob container, and hand out a short-lived user-delegation SAS link, with a lifecycle rule that deletes it after a day.

## Notes

- Validated with Terraform 1.16, azurerm 4.81 and azapi 2.12 (`terraform validate` and `terraform test` with mocked providers). Nothing has been planned or applied against Azure yet.
- `azapi` is used only for the sign-in settings (`Microsoft.App/containerApps/authConfigs`), which azurerm does not cover.
- The public counterpart (Front Door Premium with WAF in front, Private Link to the environment) is planned as `publicly-accessible-container-app`.
