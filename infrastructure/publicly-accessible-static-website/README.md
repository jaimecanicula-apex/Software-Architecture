# Publicly accessible static website (Terraform)

> **Golden template candidate.** This folder is written to become an APEX golden template. See [../../GOLDEN-TEMPLATES.md](../../GOLDEN-TEMPLATES.md) for what still has to happen before it is published as one.

Use this design when the audience is **external**: clients or users outside APEX. For sites used only by internal APEX users, use [../privately-accessible-static-website](../privately-accessible-static-website).

Reusable, parameterized Terraform for a **static website with no backend** on Azure. It deploys one environment at a time (`dev`, `qa`, `uat`, `prod`), and each environment can live in its own Azure subscription and keep its state in its own storage.

```
Visitor ──HTTPS──▶ Azure Front Door (+ WAF) ──▶ Azure Static Web App (content/publicly-accessible-static-website/)
                        │                              │
                        └──── diagnostics ─────────────┴──▶ Log Analytics ◀── Application Insights
                                                             │                (multi-region availability tests)
                                                             ├──▶ Alerts ──▶ Action Group (email / webhook)
                                                             └──▶ Workbook dashboard (shared with viewers)
```

This is the architecture from `WEBSITES-(Azure)/` without the Function App, managed identity, Blob Storage, private endpoints or VNet, because nothing here needs a backend.

## Design decisions

| Concern | Decision | Why | Trade-off |
| --- | --- | --- | --- |
| Region | `location`, required in every environment's `terraform.tfvars` (no default), validated against the 5 regions that offer Static Web Apps | Data residency and latency are choices per organisation and environment; a silent default could place an environment in the wrong region | Only westus2, centralus, eastus2, westeurope and eastasia. Changing it later recreates the Static Web App and the regional monitoring resources |
| Availability zones | No zone setting exists: Front Door and Static Web Apps content are global, and Azure manages zone placement for Log Analytics and Application Insights. The Terraform state storage is zone- and geo-redundant (GZRS) through `replication_type` in `bootstrap/` | Nothing in this design is pinned to one zone, so there is nothing to spread | No control over the platform's zone placement. An outage of the whole region still stops deployments and the monitoring workspace, though Front Door keeps serving cached pages |
| Hosting | Azure Static Web App: Free in dev, Standard in qa, uat and prod | The site is build-free HTML, CSS and JavaScript with no backend, so a managed host with free TLS and pull-request previews needs no server to patch. Standard is needed for the origin lock | No server-side code (an API would need Functions), only 5 regions, and dev on Free lacks some Standard features, so dev differs from prod |
| Edge | Azure Front Door: off in dev, Standard in qa, Premium in uat and prod. TLS 1.2, HTTPS redirect, caching, security headers | One global entry point for speed, custom domains and headers; Premium only where real visitors arrive, to keep cost down elsewhere | Front Door Premium is the largest cost line; dev without Front Door never exercises the edge; cached pages can stay stale after a deploy until they expire or are purged |
| WAF | Per-client rate limit and optional geo block on every tier; Default Rule Set and Bot Manager on Premium. Detection in qa, Prevention in uat and prod | Blocks floods and common attacks before they reach the site. Detection first shows what would be blocked, so real visitors are not stopped by false positives | Detection blocks nothing, and managed rules can block legitimate visitors until tuned. qa on Standard has no managed rules, so it cannot rehearse prod's WAF |
| Origin lock | `staticwebapp.config.json` allows only the `AzureFrontDoor.Backend` range with this Front Door's `X-Azure-FDID` | Stops anyone bypassing the WAF through the default `azurestaticapps.net` host, without paying for private networking | It is a header and IP-range check, not network isolation, and it only holds if the pipeline writes the config on every deploy |
| Sign-in | None | The content is public, so a login would protect nothing and add an identity setup to maintain | Nothing on this site can ever be private; restricted content needs the sign-in or private template |
| Availability | Application Insights standard web tests from 5 regions on the home page and each monitored custom domain | They follow the real visitor path from outside Azure and warn 14 days before the certificate expires | Only the home page and monitored domains are tested, not other pages or content correctness, and each test location adds a small cost |
| Monitoring | Logs, alerts and a workbook dashboard in every environment; one `enable_monitoring` switch that cannot be off in prod | Problems show up in dev too; the switch exists only to save cost outside prod | Log Analytics and web-test costs apply in every environment, including dev |
| Governance | Mandatory tags, budget, delete lock in uat and prod, viewer and operator groups | Required for every golden template: ownership and cost are visible, overspend warns early, and access is least privilege | The lock blocks legitimate teardown until removed through change control, and a budget only warns; it never stops spending |

## Cost estimate

Retail list prices in USD for West Europe from the Azure Retail Prices API, the data source of the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/), retrieved on 2026-09-27. A month is 730 hours. Taxes, discounts, reservations and currency conversion are not included; re-check in the calculator before committing a budget.

Fixed monthly cost per environment, with the settings in `terraform.tfvars` and one availability test (custom domains start with `monitor = false`):

| Item | Price used | dev | qa | uat | prod |
| --- | --- | --- | --- | --- | --- |
| Static Web App | Free $0; Standard $9 per app | $0 | $9 | $9 | $9 |
| Front Door base fee | Standard $35; Premium $330 (WAF managed rules included) | off | $35 | $330 | $330 |
| Standard web test, 5 locations every 5 minutes | $0.000645 per run, 43,800 runs a month | $28.25 | $28.25 | $28.25 | $28.25 |
| Alerts (metric, log and activity log) | $0.15 to $0.50 per rule; activity log alerts free | about $1 | about $1 | about $1 | about $1 |
| Log Analytics | First 5 GB free, then $2.99 per GB; retention past 31 days $0.13 per GB a month | $0 | $0 | $0 | $0 |
| **Fixed total** | | **about $29** | **about $73** | **about $368** | **about $368** |

Traffic adds, per month:

| Item | Price used | Example: 1 million requests, 50 GB |
| --- | --- | --- |
| Front Door requests | Standard $0.009, Premium $0.015 per 10,000 | $0.90 Standard, $1.50 Premium |
| Front Door data out (Europe and North America) | $0.0825 per GB for the first 10 TB | $4.13 |
| Static Web App bandwidth | 100 GB included on Standard, then $0.20 per GB | $0 |
| Each custom domain with `monitor = true` | One more web test | $28.25 |

- **Front Door Premium is 90 % of the cost** in uat and prod.
- **uat budget is tight:** 400 against about $368 fixed. Monitoring the uat domain (+$28.25) plus traffic reaches the 100 % forecast warning.
- **prod** with both domains monitored is about $425 plus traffic, inside its 500 budget.

## Folder layout

```
infrastructure/publicly-accessible-static-website/
├── bootstrap/                  One-time: storage account for Terraform remote state
├── modules/                    Reusable building blocks (no provider or backend config)
│   ├── naming/                 Naming convention: <type>-<workload>-<env>-<region>-<instance>
│   ├── static-web-app/         Azure Static Web App
│   ├── front-door/             Front Door profile, endpoint, origin, route, custom domains, security headers
│   ├── front-door-waf/         WAF policy (rate limit, geo block, managed rules on Premium) + security policy
│   └── monitoring/             Log Analytics, App Insights, availability tests, diagnostics,
│                               alerts, Action Group, workbook dashboard, viewer access
├── stacks/
│   └── static-website/         Root module that composes the modules (one stack, many environments)
│       └── templates/          staticwebapp.config.json template (origin lock to Front Door)
├── environments/
│   ├── dev/  qa/  uat/  prod/  terraform.tfvars (settings) + backend.hcl (state location)
└── scripts/
    ├── tf.sh                   Wrapper: ./publicly-accessible-static-website/scripts/tf.sh <env> <command>
    └── tf.ps1                  Same for PowerShell
```

## What each environment gets

| Setting | dev | qa | uat | prod |
| --- | --- | --- | --- | --- |
| Subscription | own `subscription_id` | own | own | own |
| Static Web App SKU | Free | Standard | Standard | Standard |
| Front Door | off (cost) | Standard | Premium | Premium |
| WAF | n/a | Detection, custom rules | Prevention, custom + managed rules | Prevention, custom + managed rules |
| Custom domains | none | none | `uat.example.com` | `example.com`, `www.example.com` |
| PR preview environments | on | on | off | off |
| Log retention | 30 days | 30 days | 90 days | 180 days |
| Delete lock | no | no | yes | yes |
| Monthly budget | 50 | 100 | 400 | 500 |

Everything in that table is a variable in `environments/<env>/terraform.tfvars`, so change it freely.

## Monitoring

Every environment gets the full monitoring set, including dev.

| What | How | Alert |
| --- | --- | --- |
| Site availability from 5 regions | App Insights standard web tests on the public URL and each custom domain | Availability below threshold (sev 1) |
| TLS certificate expiry | Web tests fail when the certificate has under 14 days left | Same availability alert |
| Origin health | Front Door metric `OriginHealthPercentage` | Below 90% (sev 1) |
| Server errors | Front Door metric `Percentage5XX` | Above 5% (sev 1) |
| Client errors / probing | Front Door metric `Percentage4XX` | Above 25% (sev 3) |
| Latency | Front Door metric `TotalLatency` | Above 2000 ms (sev 2) |
| Attacks / WAF false positives | WAF log query | More than 100 blocks in 15 min (sev 2) |
| Destructive or security changes | Activity Log: SWA or Front Door deleted, WAF changed or deleted, role assignment added, lock deleted | Every occurrence |
| Resource health | Activity Log ResourceHealth | Degraded or unavailable |
| Azure incidents | Service Health | Incident, maintenance or security advisory |
| Cost | Resource group budget | 80% actual, 100% forecast |

Front Door access, health probe and WAF logs, plus all metrics, go to Log Analytics. Set `export_activity_log = true` to also send the subscription Activity Log there, but only if the subscription doesn't already export it.

All thresholds are in `alert_thresholds`. Recipients are in `alert_email_receivers` and `alert_webhook_receivers` (Teams, ITSM, PagerDuty and similar).

### Who can see it

Each environment has a shared **Azure Monitor workbook**, "Static website - <env>", with these panels:

- availability by test and by location
- requests by status class
- p50/p95 latency
- top paths
- cache hit ratio
- WAF actions and top rules
- origin health probes
- alerts fired

Get the link with:

```
./publicly-accessible-static-website/scripts/tf.sh prod output monitoring_dashboard_url
```

Access is granted through Entra ID groups in `terraform.tfvars`, scoped to that environment's resource group only:

| Variable | Roles | Can |
| --- | --- | --- |
| `monitoring_viewer_principal_ids` | Reader, Monitoring Reader, Log Analytics Reader | Open the dashboard, run log queries, see metrics and alerts |
| `monitoring_operator_principal_ids` | Reader, Monitoring Contributor, Log Analytics Reader, Workbook Contributor | The above, plus change alerts, action groups and dashboards |

Use group object IDs, not individual users, so access is managed by group membership.

## First-time setup

1. **Create the state storage**, once per state subscription:
   ```
   cd infrastructure/publicly-accessible-static-website/bootstrap
   cp example.tfvars prod.tfvars    # edit it
   terraform init
   terraform apply -var-file=prod.tfvars
   ```
   Copy the `backend_config` output into `environments/<env>/backend.hcl`.

2. **Fill in** `environments/<env>/terraform.tfvars`:
   - `subscription_id`
   - `governance_tags`
   - alert emails
   - viewer and operator group IDs
   - custom domains

   Replace every `<...>` placeholder.

3. **Sign in** with `az login`, or set `ARM_CLIENT_ID`, `ARM_TENANT_ID` and the OIDC or secret variables in CI. The identity needs these roles on the target subscription or resource group:
   - Contributor
   - User Access Administrator, for the viewer role assignments
   - Storage Blob Data Contributor, on the state account

4. **Deploy:**
   ```
   ./publicly-accessible-static-website/scripts/tf.sh dev init
   ./publicly-accessible-static-website/scripts/tf.sh dev plan
   ./publicly-accessible-static-website/scripts/tf.sh dev apply
   ```
   In PowerShell: `./publicly-accessible-static-website/scripts/tf.ps1 -Environment dev -Command plan`.

   Each environment uses its own `.terraform-<env>` directory, so switching environments never reuses the wrong backend.

## After apply

- **Deployment token:** run `terraform output -raw static_web_app_deployment_token` and store the result as `AZURE_STATIC_WEB_APPS_API_TOKEN`, either as a GitHub environment secret or in the Azure DevOps `swa-deployment` variable group. Use one token per environment.
- **Origin lock:** the `staticwebapp_config_json` output is that environment's `staticwebapp.config.json`. It lets the Static Web App accept traffic only from this Front Door (`X-Azure-FDID`) and sets the Content-Security-Policy. Have the delivery pipeline write it into `content/publicly-accessible-static-website/` before deploying, because the Front Door ID differs per environment. This needs the Standard SKU.
- **Custom domains:** `custom_domain_dns_records` lists the TXT validation record and CNAME target for each domain. Create them at the DNS provider. An apex domain needs an ALIAS/ANAME or CNAME-flattening record. Once DNS points at Front Door, set `monitor = true` on the domain to add its availability test.

## Notes

- Static Web Apps is available only in `westus2`, `centralus`, `eastus2`, `westeurope` and `eastasia`. Front Door is global.
- WAF managed rule sets (Default Rule Set 2.1, Bot Manager 1.1) need `Premium_AzureFrontDoor`. On Standard, only the custom rate-limit and geo rules apply.
- Start a new WAF in `Detection`, review the "Top WAF rules triggered" panel, then switch to `Prevention`.
- Validated with Terraform 1.16 and azurerm 4.81 (`terraform validate`). Nothing has been planned or applied against Azure yet.
