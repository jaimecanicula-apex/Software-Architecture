# Privately accessible static website (Terraform)

> **Golden template candidate.** This folder is written to become an APEX golden template. See [../GOLDEN-TEMPLATES.md](../GOLDEN-TEMPLATES.md) for what still has to happen before it is published as one.

Use this design when the site is for **internal users only**: anyone who signs in with APEX Entra ID, including IT and business colleagues, people from APEX companies, and contractors. It has no internet exposure and no connection outside the APEX tenant. For external clients or users, use [../publicly-accessible-static-website](../publicly-accessible-static-website) instead.

```
APEX user on the corporate network (VPN / ExpressRoute / office)
   │  resolves the site through Private DNS
   ▼
Private endpoint ──▶ Azure Static Web App (public network access OFF)
                        │  APEX Entra sign-in, assigned groups only
                        ▼
                     app-internal/ (build-free HTML, CSS, JS)

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
| Site folder | `app/` | `app-internal/` |
| Pipelines | `deploy-static-web-app.yml`, `azure-pipelines.yml` | `deploy-internal-static-web-app.yml`, `azure-pipelines-internal.yml` |

## Folder layout

```
privately-accessible-static-website/
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
5. **Pipeline secrets:** store `static_web_app_deployment_token` and `staticwebapp_config_json` as the internal pipeline secrets. The internal pipelines write the config into `app-internal/` before uploading.

## What the platform team must do

- **Hub peering:** create the hub side of the peering. This stack only creates the spoke side, and only when `hub_virtual_network_id` is set.
- **DNS:** make corporate DNS resolve the zones in the `private_dns_zones` output. Either link them to the hub, which the stack does when `hub_virtual_network_id` is set, or forward them to the hub DNS resolver.
- **Monitor DNS zones:** this design creates its own `privatelink.*` zones for Azure Monitor. In a landing zone with central Private DNS zones, point to those zones instead. That is one of the golden-template changes.

## To verify in dev before production

These have not been tested against Azure yet (`terraform validate` passes):

- Deployment from GitHub Actions or Azure Pipelines still works with public network access disabled.
- Pull-request preview environments resolve through the private DNS zone.
- The probe image is pulled from MCR over outbound internet. For a fully closed network, mirror the image into an APEX registry and set `probe_image`.
