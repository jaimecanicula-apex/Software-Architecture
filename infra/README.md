# Static website infrastructure (Terraform)

Reusable, parameterized Terraform for a **static website with no backend** on Azure. It deploys one environment at a time (`dev`, `qa`, `uat`, `prod`), and each environment can live in its own Azure subscription and keep its state in its own storage.

```
Visitor ──HTTPS──▶ Azure Front Door (+ WAF) ──▶ Azure Static Web App (app/)
                        │                              │
                        └──── diagnostics ─────────────┴──▶ Log Analytics ◀── Application Insights
                                                             │                (multi-region availability tests)
                                                             ├──▶ Alerts ──▶ Action Group (email / webhook)
                                                             └──▶ Workbook dashboard (shared with viewers)
```

This is the architecture from `WEBSITES-(Azure)/` without the Function App, managed identity, Blob Storage, private endpoints or VNet, because nothing here needs a backend.

## Folder layout

```
infra/
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
    ├── tf.sh                   Wrapper: ./infra/scripts/tf.sh <env> <command>
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
./infra/scripts/tf.sh prod output monitoring_dashboard_url
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
   cd infra/bootstrap
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
   ./infra/scripts/tf.sh dev init
   ./infra/scripts/tf.sh dev plan
   ./infra/scripts/tf.sh dev apply
   ```
   In PowerShell: `./infra/scripts/tf.ps1 -Environment dev -Command plan`.

   Each environment uses its own `.terraform-<env>` directory, so switching environments never reuses the wrong backend.

## After apply

- **Deployment token:** run `terraform output -raw static_web_app_deployment_token` and store the result as `AZURE_STATIC_WEB_APPS_API_TOKEN`, either as a GitHub environment secret or in the Azure DevOps `swa-deployment` variable group. Use one token per environment.
- **Origin lock:** the `staticwebapp_config_json` output is that environment's `staticwebapp.config.json`. It lets the Static Web App accept traffic only from this Front Door (`X-Azure-FDID`) and sets the Content-Security-Policy. Have the delivery pipeline write it into `app/` before deploying, because the Front Door ID differs per environment. This needs the Standard SKU.
- **Custom domains:** `custom_domain_dns_records` lists the TXT validation record and CNAME target for each domain. Create them at the DNS provider. An apex domain needs an ALIAS/ANAME or CNAME-flattening record. Once DNS points at Front Door, set `monitor = true` on the domain to add its availability test.

## Notes

- Static Web Apps is available only in `westus2`, `centralus`, `eastus2`, `westeurope` and `eastasia`. Front Door is global.
- WAF managed rule sets (Default Rule Set 2.1, Bot Manager 1.1) need `Premium_AzureFrontDoor`. On Standard, only the custom rate-limit and geo rules apply.
- Start a new WAF in `Detection`, review the "Top WAF rules triggered" panel, then switch to `Prevention`.
- Validated with Terraform 1.16 and azurerm 4.81 (`terraform validate`). Nothing has been planned or applied against Azure yet.
