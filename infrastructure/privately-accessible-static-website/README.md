# Privately accessible static website (Terraform)

> **Golden template candidate.** This folder is written to become an APEX golden template. See [../../GOLDEN-TEMPLATES.md](../../GOLDEN-TEMPLATES.md) for what still has to happen before it is published as one.

Use this design when the site is for **internal users only**: anyone who signs in with APEX Entra ID, including IT and business colleagues, people from APEX companies, and contractors. It has no internet exposure and no connection outside the APEX tenant. For external clients or users, use [../publicly-accessible-static-website](../publicly-accessible-static-website) instead.

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

## How it differs from the public design

| | Publicly accessible | Privately accessible (this folder) |
| --- | --- | --- |
| Who | External clients and users | Internal APEX users only |
| Entry | Azure Front Door + WAF, internet | Private endpoint, APEX network only |
| Static Web App | Public, locked to Front Door | Public network access **disabled** |
| Sign-in | None | APEX Entra ID, single tenant, assigned groups only |
| Network | None | Own spoke VNet, NSGs, Private DNS zones, optional hub peering |
| Availability tests | Internet web tests from 5 regions | In-VNet probe (Container Apps job) |
| Telemetry path | Public ingestion | Azure Monitor Private Link Scope, ingestion private-only |
| Site folder | `content/publicly-accessible-static-website/` | `content/privately-accessible-static-website/` |
| Pipelines | `deploy-static-web-app.yml`, `infrastructure/publicly-accessible-static-website/pipelines/azure-pipelines.yml` | `deploy-internal-static-web-app.yml`, `infrastructure/privately-accessible-static-website/pipelines/azure-pipelines.yml` |

## Design decisions

| Concern | Decision | Why | Trade-off |
| --- | --- | --- | --- |
| Region | `location`, required in every environment's `terraform.tfvars` (no default), validated against the 5 regions that offer Static Web Apps | Data residency and latency are choices per organisation and environment; a silent default could place an environment in the wrong region | Only westus2, centralus, eastus2, westeurope and eastasia. Changing it later recreates the Static Web App and the regional monitoring resources |
| Availability zones | `probe_zone_redundancy_enabled` spreads the availability probe's Container Apps environment across zones: on in uat and prod. The Static Web App, private endpoints and Private DNS have no zone setting; Azure keeps them resilient. The Terraform state storage is zone- and geo-redundant (GZRS) through `replication_type` in `bootstrap/` | A zone failure should not silence the probe and raise a false alert in prod | Fixed at creation: switching it recreates the probe's environment. The site's own resilience is whatever Static Web Apps provides; there is nothing to tune |
| Subnets | Two subnets: private endpoints (`private_endpoint_subnet_prefix`) and the probe (`probe_subnet_prefix`, delegated to Container Apps). Names `snet-pe-<suffix>` and `snet-probe-<suffix>`, each with its own NSG, from the naming module | Address ranges come from each environment's IP plan, and separating the probe keeps its delegation away from the private endpoints | Two ranges to allocate per environment; the probe subnet needs at least a /27 to itself |
| Entry | Private endpoint in the spoke VNet; Static Web App public network access **off** | Every user is internal, so there is no internet entry to defend at all | Users off the corporate network cannot reach it, the design depends on the hub and corporate DNS, and deployment and preview environments with public access off still need verifying |
| Network | Own spoke VNet, NSGs denying internet inbound, Private DNS zones, optional hub peering | The template works on its own and joins the hub when the platform team is ready | More to own: IP ranges from the IP plan, peering and DNS coordination. Its own Private DNS zones can clash with central zones in a landing zone |
| Sign-in | APEX Entra ID, single tenant, *assignment required* for `allowed_group_ids`; secret rotates every 180 days | Entra refuses everyone else in the tenant, before the site sees a request | The client secret expires if the environment is not re-applied within about 210 days |
| Availability | Container Apps job inside the VNet requests `/healthz.html` every 5 minutes | Internet web tests cannot reach a private site; the job takes the same private path as users, with no server, code package or storage account | One location, from inside the VNet only: it does not test users' VPN or ExpressRoute path or warn about certificate expiry, and the job image is pulled from the internet |
| Telemetry | Azure Monitor Private Link Scope with private-only ingestion | Monitoring data about a private site stays on the private network | The Private Link Scope changes Azure Monitor DNS for the whole network, adds cost, and is one more link that can fail |
| Alerts | Availability below threshold, probe silent for 15 minutes, destructive changes, resource and service health, budget | A silent probe means the check itself or its private path failed, which availability alone would not show | A probe-silent alert says something broke but not whether it is the probe, the network or the site; someone must diagnose it |
| Dashboard access | `monitoring_query_from_internet = true` by default | Viewers can open the dashboard from the portal anywhere they sign in; set false to limit it to the APEX network | Open from anywhere means any device where viewers sign in; limiting it means viewers need the corporate network |
| Governance | Mandatory tags, budget, delete lock in uat and prod, viewer and operator groups | Required for every golden template | The lock blocks legitimate teardown until removed through change control, and a budget only warns; it never stops spending |

## Cost estimate

Retail list prices in USD for West Europe from the Azure Retail Prices API, the data source of the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/), retrieved on 2026-09-27. A month is 730 hours. Taxes, discounts, reservations and currency conversion are not included; re-check in the calculator before committing a budget.

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
| VNet, NSGs, Entra app, budget | No charge | $0 |
| **Total** | | **about $29** |

- **The private networking adds about $18 a month** (two private endpoints and six DNS zones) over a public site with no Front Door.
- **To confirm:** the price list has a Container Apps "Environment Management Hour" meter at $0.143 an hour (about $104 a month). Check in the calculator whether it applies to the probe's Consumption-only environment; it is not in the total above.
- **Budgets** (100, 150, 200, 300) are several times the estimate; they can be lowered unless the environment meter above applies.

## Folder layout

```
infrastructure/privately-accessible-static-website/
├── bootstrap/                 One-time: Terraform state storage
├── modules/
│   ├── naming/                Names, including vnet-, ampls-, pe-, app- prefixes
│   ├── network/               Spoke VNet, private-endpoint and probe subnets, NSGs,
│   │                          Azure Monitor Private DNS zones, optional hub peering
│   ├── private-endpoint/      Generic private endpoint + DNS zone group
│   ├── static-web-app/        Static Web App with public_network_access_enabled
│   ├── entra-app-auth/        Single-tenant app registration, assigned groups, rotating secret
│   ├── monitoring/            Log Analytics, App Insights (private ingestion), alerts,
│   │                          workbook, viewer/operator roles
│   ├── monitor-private-link/  Azure Monitor Private Link Scope + endpoint
│   └── availability-probe/    Scheduled Container Apps job inside the VNet (probe.sh)
├── stacks/static-website/     Root module for this design
│   └── templates/             staticwebapp.config.json (APEX sign-in)
├── environments/dev|qa|uat|prod/  terraform.tfvars + backend.hcl
└── scripts/tf.sh · tf.ps1     ./privately-accessible-static-website/scripts/tf.sh dev plan
```

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
  - `monitoring_viewer_principal_ids` and `monitoring_operator_principal_ids` get the same roles as in the public design, on this resource group only.
  - `monitoring_query_from_internet = true` (the default) lets them open the dashboard from the Azure portal anywhere they can sign in. `false` limits it to the APEX network.

## Sign-in

- **App registration:** `entra-app-auth` creates a single-tenant registration. Its redirect URI is `https://<site>/.auth/login/aad/callback`.
- **Who gets in:** *assignment required* is on, so only `allowed_group_ids` can sign in. Everyone else in APEX is refused by Entra itself.
- **Client secret:** the secret rotates every 180 days (`time_rotating`). The next apply after rotation updates the Static Web App settings.
- **If pipelines may not create app registrations:** set `create_entra_app = false` and pass `existing_entra_client_id` and `existing_entra_client_secret`.
- **Unauthenticated routes:** `/healthz.html` is the only anonymous page, so the probe can check the site without signing in. It is still reachable only from the private network.

## First-time setup

1. Run `bootstrap/` for the state storage and fill in `environments/<env>/backend.hcl`.
2. In `environments/<env>/terraform.tfvars`, set these from the APEX platform team:
   - `tenant_id`
   - `subscription_id`
   - the IP ranges (`vnet_address_space`, subnet prefixes)
   - `dns_servers`
   - optionally `hub_virtual_network_id`
   - `allowed_group_ids`
   - viewer and operator groups
3. **Identity for `apply`:** the identity needs these roles:
   - Contributor and User Access Administrator on the subscription
   - Network Contributor on the hub, if you set `hub_virtual_network_id`
   - Entra rights to create app registrations (Application Developer or Cloud Application Administrator), or use `create_entra_app = false`
4. Deploy:
   ```
   ./privately-accessible-static-website/scripts/tf.sh dev init
   ./privately-accessible-static-website/scripts/tf.sh dev plan
   ./privately-accessible-static-website/scripts/tf.sh dev apply
   ```
5. **Pipeline secrets:** store `static_web_app_deployment_token` and `staticwebapp_config_json` as the internal pipeline secrets. The internal pipelines write the config into `content/privately-accessible-static-website/` before uploading.

## What the platform team must do

- **Hub peering:** create the hub side of the peering. This stack only creates the spoke side, and only when `hub_virtual_network_id` is set.
- **DNS:** make corporate DNS resolve the zones in the `private_dns_zones` output. Either link them to the hub, which the stack does when `hub_virtual_network_id` is set, or forward them to the hub DNS resolver.
- **Monitor DNS zones:** this design creates its own `privatelink.*` zones for Azure Monitor. In a landing zone with central Private DNS zones, point to those zones instead. That is one of the golden-template changes.

## To verify in dev before production

These have not been tested against Azure yet (`terraform validate` passes):

- Deployment from GitHub Actions or Azure Pipelines still works with public network access disabled.
- Pull-request preview environments resolve through the private DNS zone.
- The probe image is pulled from MCR over outbound internet. For a fully closed network, mirror the image into an APEX registry and set `probe_image`.
