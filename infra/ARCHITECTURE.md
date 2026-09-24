# Static website stack: C4 architecture

## 1. Scope

This document covers the Terraform stack in `infra/` and the runtime system it provisions: a static website on Azure with an edge firewall and full monitoring, deployed once per environment (`dev`, `qa`, `uat`, `prod`).

- **Inside the boundary:** everything Terraform creates, meaning the edge, hosting, monitoring, access and governance resources.
- **Adjacent, shown for context:**
  - the site content in `app/`
  - the delivery pipelines (`.github/workflows/deploy-static-web-app.yml`, `azure-pipelines.yml`)
  - the Terraform state storage created by `infra/bootstrap`
- **Outside the boundary:** Entra ID, the DNS provider, Azure platform services and notification endpoints. The stack consumes them but does not own them.

The architecture is the pattern in `WEBSITES-(Azure)/` without a backend: there is no Function App, Blob Storage, managed identity, private endpoint or VNet.

## 2. Observations from the codebase

| Evidence | What it shows |
| --- | --- |
| `stacks/static-website/main.tf` | One root module composes 5 modules and adds the resource group, delete lock and budget |
| `stacks/static-website/versions.tf` | Terraform >= 1.9, azurerm `~> 4.60`, empty `backend "azurerm" {}` (partial config) |
| `stacks/static-website/providers.tf` | `subscription_id` and `tenant_id` come from variables, so each environment targets its own subscription |
| `environments/<env>/terraform.tfvars` + `backend.hcl` | The same stack runs with 4 settings files and 4 state locations |
| `modules/front-door` | Front Door profile, endpoint, origin group with an HTTPS health probe, the Static Web App as the only origin, route `/*` with HTTPS redirect and caching, managed-TLS custom domains, a security-headers rule set |
| `modules/front-door-waf` | WAF policy (per-IP rate limit, optional geo block, DRS 2.1 + Bot Manager 1.1 on Premium) bound to every domain through a security policy |
| `modules/static-web-app` | Static Web App, Free or Standard, with preview environments toggle |
| `modules/monitoring` | Log Analytics, workspace-based Application Insights, standard web tests, diagnostic settings, metric/log/activity alerts, Action Group, workbook, role assignments |
| `stacks/static-website/templates/staticwebapp.config.json.tftpl` | Generated config that restricts the Static Web App to `AzureFrontDoor.Backend` + `X-Azure-FDID` and sets the CSP |
| `enable_front_door` (count on `module.front_door` / `module.waf`) | Front Door is optional per environment; dev turns it off |
| `bootstrap/main.tf` | Separate root with local state; creates the state storage account (Entra ID auth only, GRS, versioning, soft delete, lock) |
| `scripts/tf.sh`, `tf.ps1` | Operators run `tf <env> <command>`; `TF_DATA_DIR` is isolated per environment |

## 3. Assumptions and inferences

- **Inferred:** the people who run Terraform are a platform or cloud team, and the people in `monitoring_viewer_principal_ids` are support, service owners and security operations. The tfvars comments suggest this, but no roles are fixed in code.
- **Inferred:** the public audience is anonymous web visitors. There is no authentication on the site.
- **Inferred:** DNS lives outside Azure (as with MarkMonitor in the wiki), because `dns_zone_id` is optional and `custom_domain_dns_records` is emitted for manual creation.
- **Observed but unverified:** nothing has been planned or applied against Azure. Only `terraform validate` has passed.

## 4. System context

Who and what interacts with the static website system.

```mermaid
flowchart LR
    Visitor["👤 Website visitor<br/>Anonymous public user reading the site"]
    Viewer["👤 Monitoring viewer<br/>Support, service owner or security analyst"]
    Operator["👤 Platform engineer<br/>Runs Terraform and manages alerts"]

    subgraph System["Static website system (one per environment)"]
        Site["Static website on Azure<br/>Edge firewall, hosting, monitoring"]
    end

    Delivery["🚀 Delivery pipeline<br/>GitHub Actions or Azure Pipelines"]
    DNS["🌍 DNS provider<br/>External registrar or Azure DNS"]
    Entra["🔑 Microsoft Entra ID<br/>Identities and groups"]
    Notify["📣 Notification endpoints<br/>Email, Teams, ITSM webhooks"]

    Visitor -->|"Browses over HTTPS"| Site
    Viewer -->|"Opens dashboard, queries logs"| Site
    Operator -->|"Provisions with Terraform"| Site
    Delivery -->|"Uploads app/ with deployment token"| Site
    DNS -->|"Resolves custom domains to the edge"| Site
    Site -->|"Authorizes viewers and operators by group"| Entra
    Site -->|"Sends alerts"| Notify
```

## 5. Container view

The runnable units inside one environment. Front Door and its WAF exist only when `enable_front_door = true`.

```mermaid
flowchart TB
    Visitor["👤 Website visitor"]
    Viewer["👤 Monitoring viewer"]
    Delivery["🚀 Delivery pipeline"]
    Notify["📣 Email / webhooks"]

    subgraph RG["Resource group rg-sws-&lt;env&gt;-&lt;region&gt;-001 (tags, optional delete lock, budget)"]
        subgraph Edge["Edge (global)"]
            AFD["Azure Front Door<br/>TLS, custom domains, HTTPS redirect,<br/>caching, security headers"]
            WAF["WAF policy<br/>Rate limit, geo block,<br/>managed rules on Premium"]
        end
        SWA["Azure Static Web App<br/>Serves the build-free app/ folder;<br/>accepts only Front Door traffic"]
        subgraph Mon["Monitoring"]
            LAW["Log Analytics workspace<br/>Front Door, WAF and availability data"]
            AI["Application Insights<br/>Multi-region availability tests,<br/>certificate expiry checks"]
            Alerts["Azure Monitor alerts<br/>Metric, log, activity, health, budget"]
            AG["Action Group<br/>Routes notifications"]
            WB["Workbook dashboard<br/>Availability, traffic, latency, WAF"]
        end
    end

    Visitor -->|"HTTPS"| AFD
    WAF -.->|"Inspects every request"| AFD
    AFD -->|"HTTPS, X-Azure-FDID header"| SWA
    Delivery -->|"Deploys content"| SWA
    AI -->|"Probes public URLs from 5 regions"| AFD
    AFD -->|"Access, probe and WAF logs + metrics"| LAW
    AI -->|"Stores results in"| LAW
    Alerts -->|"Evaluates metrics and queries"| LAW
    Alerts -->|"Fires"| AG
    AG -->|"Email, webhook"| Notify
    WB -->|"Queries"| LAW
    Viewer -->|"Reader roles on the resource group"| WB
```

### Environment deployment view

The same containers are deployed four times from `environments/<env>/terraform.tfvars`. The defaults are:

| | dev | qa | uat | prod |
| --- | --- | --- | --- | --- |
| Subscription | own | own | own | own |
| Front Door | off | Standard | Premium | Premium |
| WAF | n/a | Detection | Prevention + managed rules | Prevention + managed rules |
| Static Web App | Free | Standard | Standard | Standard |
| Log retention | 30 days | 30 days | 90 days | 180 days |
| Delete lock | no | no | yes | yes |

## 6. Component view: the Terraform stack

This view breaks down the Terraform codebase itself: how the modules divide responsibility, and how configuration and state flow into one apply.

```mermaid
flowchart TB
    Engineer["👤 Platform engineer"]
    Wrapper["scripts/tf.sh · tf.ps1<br/>Selects environment, isolates TF_DATA_DIR"]

    subgraph Env["environments/&lt;env&gt;/"]
        Vars["terraform.tfvars<br/>Subscription, SKUs, domains,<br/>thresholds, recipients, groups"]
        Backend["backend.hcl<br/>State location"]
    end

    subgraph Stack["stacks/static-website (root module)"]
        Root["main.tf<br/>Resource group, tags, lock, budget;<br/>wires modules together"]
        Tpl["templates/staticwebapp.config.json.tftpl<br/>Origin lock + CSP per environment"]
        Out["outputs.tf<br/>URL, deploy token, DNS records,<br/>dashboard link, config JSON"]
    end

    subgraph Modules["modules/"]
        Naming["naming<br/>CAF names: type-workload-env-region-instance"]
        SWAm["static-web-app<br/>Hosting"]
        AFDm["front-door<br/>Edge routing, TLS, headers"]
        WAFm["front-door-waf<br/>Firewall rules + security policy"]
        Monm["monitoring<br/>Logs, tests, alerts, dashboard, access"]
    end

    State[("Terraform state<br/>Storage account from bootstrap/")]

    Engineer --> Wrapper
    Wrapper -->|"-var-file"| Vars
    Wrapper -->|"-backend-config"| Backend
    Backend -->|"Locks and stores state in"| State
    Vars --> Root
    Root -->|"Names for every resource"| Naming
    Root --> SWAm
    Root -->|"Origin = SWA host name"| AFDm
    Root -->|"Profile ID + domain IDs"| WAFm
    Root -->|"Front Door ID, URLs to test,<br/>viewer/operator groups"| Monm
    Root --> Tpl
    Tpl --> Out
    SWAm --> Out
    AFDm --> Out
    Monm --> Out
```

### Monitoring module internals

`modules/monitoring` is the largest module. It is split by responsibility:

| File | Responsibility |
| --- | --- |
| `main.tf` | Log Analytics workspace, workspace-based Application Insights, Action Group (email + webhooks) |
| `diagnostics.tf` | Front Door access, health probe and WAF logs + metrics to the workspace; optional subscription Activity Log export |
| `availability.tf` | Standard web test per public URL from 5 regions; fails on non-200 or a certificate within 14 days of expiry |
| `alerts.tf` | Availability, origin health, 5xx, 4xx, latency, WAF block spikes, destructive/security control-plane changes, resource health, service health |
| `workbook.tf` | Shared dashboard with 10 KQL panels over the workspace |
| `access.tf` | Viewer roles (Reader, Monitoring Reader, Log Analytics Reader) and operator roles (+ Monitoring Contributor, Workbook Contributor) on the resource group |

## 7. Open questions

1. **Tokens per environment:** should each environment have its own delivery pipeline stage? The pipelines currently deploy with a single token, and the stack emits one per environment.
2. **Who writes the origin lock:** which process writes `staticwebapp_config_json` into `app/`? Until it is written, the Static Web App's default host name serves the site directly and bypasses the WAF.
3. **Who runs Terraform:** is Terraform run by a person with the wrapper script, or should a CI pipeline plan on pull requests and apply with approvals?
4. **Where alerts go:** is there a central Log Analytics workspace or SOC destination that these logs should also go to, instead of one workspace per environment?
5. **Subscriptions:** will environments really use separate subscriptions? The service-health alert is scoped to the whole subscription and would be noisy in a shared one.

## 8. Risks and mismatches

- **dev has no edge:** with `enable_front_door = false`, dev has no WAF, no Front Door alerts and empty Front Door panels. This is intentional, to save cost, but it differs from production.
- **Direct access until the origin lock ships:** see question 2.
- **Activity panel depends on export:** the workbook's "Alerts fired" panel reads `AzureActivity`, which only exists when `export_activity_log = true`.
- **Placeholders:** the tfvars and `backend.hcl` files contain placeholder subscription IDs, domains and storage names that must be replaced before any plan.

## 9. Suggested next refinements

- Add a Terraform CI pipeline (plan on PR, apply per environment with approval gates) and document it as a container in section 5.
- Extend the delivery pipelines to deploy through dev → qa → uat → prod and write the per-environment `staticwebapp.config.json`.
- Once applied, replace the inferred personas with the real Entra ID groups and record actual resource names in the wiki's configuration reference.
