# Publicly accessible static website with a document API (Bicep)

> **Golden template candidate.** See [../../GOLDEN-TEMPLATES.md](../../GOLDEN-TEMPLATES.md) for what still has to happen before it is published as one.

A public, read-only website that publishes approved documents (PDFs) to anyone on the internet. Azure Front Door Premium with a WAF is the only public entry point. It serves the static site from a Static Web App and sends `/api/*` through Private Link to a Function App, which reads a private Blob container with its managed identity. Nothing but the website and the documents it lists is public: storage has no anonymous access, and the Function has no public endpoint.

It is Bicep first. A Terraform twin (`publicly-accessible-static-website-with-document-api`) will follow and must keep the same resources, names and parameters. There is no example site or API content yet: the pipelines point at a folder you set.

```
Browser ──HTTPS──▶ Front Door Premium + WAF
                     ├─ /*      ─▶ Static Web App (Standard), accepts only this Front Door
                     └─ /api/*  ─▶ Private Link ─▶ Function App (EP1, public access off)
                                                     └─ managed identity ─▶ private Blob container
Publisher ──Entra ID──▶ Blob storage (uploads PDFs marked approved=true)
```

Architecture diagrams: [ARCHITECTURE.md](ARCHITECTURE.md), [c4-context.drawio](c4-context.drawio), [c4-containers.drawio](c4-containers.drawio). To open them in Lucidchart, import [c4-context-lucidchart.drawio](c4-context-lucidchart.drawio) and [c4-containers-lucidchart.drawio](c4-containers-lucidchart.drawio).

## How the pieces fit

| Piece | What it does | Where |
| --- | --- | --- |
| Front Door Premium + WAF | TLS, HTTPS redirect, routing, managed WAF rules, optional custom domains | `modules/front-door.bicep`, `modules/front-door-waf.bicep` |
| Static Web App (Standard) | Serves the build-free frontend; locked to this Front Door by `staticwebapp.config.json` (output `staticWebAppConfigJson`) | `modules/static-web-app.bicep` |
| Function App (Elastic Premium EP1, Linux) | `GET /api/documents` lists approved PDFs, `GET /api/documents/{id}` streams one. Public access off, VNet-integrated | `modules/function-app.bicep` |
| Storage account | The documents (private container) and the Function host's storage, in one account | `modules/storage.bicep` |
| Network | VNet, a subnet for Function VNet integration, a subnet for private endpoints, NSGs, three Private DNS zones | `modules/network.bicep`, `modules/private-endpoint.bicep` |
| Monitoring | Log Analytics, Application Insights, Action Group, availability tests, alerts | `modules/monitoring.bicep`, `modules/alerts.bicep` |
| Governance | Tags, delete lock (forced in uat and prod), budget, viewer and operator roles | `modules/governance.bicep` |
| Names | `<type>-<workload>-<env>-<region>-<instance>` | `modules/naming.bicep` |

**The document contract** the Function expects (the template deploys the container, your API code implements the contract): a blob is public only if it is a `.pdf` with metadata `approved=true`. The API returns 404 for both missing and unapproved blobs, and sets `Cache-Control: no-store`. Front Door does not cache `/api/*`, so a publication or withdrawal shows at once.

## Design decisions

| Concern | Decision | Why | Trade-off |
| --- | --- | --- | --- |
| Region | `location` is required with no default, limited to regions with Elastic Premium and private endpoints. `staticWebAppLocation` is separate (Static Web Apps exists in only five regions) | A region outside the list fails before anything deploys | Two settings to keep sensible; the app and the Function can end up in different regions |
| Availability zones | `zoneRedundancyEnabled` on the Function plan: off in dev and qa, on in uat and prod, with 2 instances when on. Storage uses `storageReplicationType`: ZRS in dev and qa, GZRS in uat and prod. Front Door and Static Web Apps are global, so nothing zonal applies to them | A zone failure should not take the API or the documents offline in prod | Zone redundancy doubles the compute cost (two EP1 instances). It is fixed at creation. Bicep cannot check that zones and LRS storage are not combined, so `scripts/deploy.sh` does |
| Public entry | Front Door Premium + WAF is the only public path. Premium in **every** environment | Private Link origins and managed WAF rule sets need Premium. One shape in all environments means dev tests what prod runs | Premium is $330 a month in dev too, about 60 % of a dev environment's cost. A cheaper dev needs a different (public) API origin, which is not this design |
| WAF mode | Prevention forced in uat and prod; dev and qa default to Detection | Rules can be tuned without blocking real users before prod | Dev can pass traffic prod would block. Test in uat before prod |
| Static site origin lock | The site accepts only `AzureFrontDoor.Backend` with this profile's `X-Azure-FDID` and listed forwarded hosts. Bicep outputs the file, the pipeline writes it | Without it anyone could skip the WAF by calling the default `*.azurestaticapps.net` host | Pull-request previews may not be browsable directly. The ID changes if Front Door is recreated, so the secret must be refreshed |
| API path | Front Door reaches the Function through **Private Link**; the Function has public network access disabled | The API cannot be called except through the WAF | The connection is created Pending and must be approved on the Function (`scripts/deploy.sh` does it). Deploying the Function package needs a network path to its private endpoint |
| Compute | Elastic Premium EP1, Linux, Node 24 | Premium is needed for VNet integration with private endpoints and keeps one instance warm, so there is no cold start | An always-on instance costs about $154 a month even with no traffic. Consumption would be cheaper but cannot do this |
| Storage account | One account for the documents and the Function host. Shared-key access **on**, anonymous access off, public endpoint accepts authenticated requests only | The Function host needs the key for its content share. Publishers upload with Entra ID and need no network path | **A weaker baseline than possible.** Anyone holding a key reaches the account from any network. The hardened alternative is two accounts with public access off and a private publishing path, at the cost of a harder upload workflow |
| Document access | The Function reads with its system-assigned identity (Storage Blob Data Reader). No storage key, SAS or connection string reaches the API code or the browser | A compromised API cannot write or delete documents | The role is account-wide, not per container |
| Publishing | Publishers are Entra groups with Storage Blob Data Contributor (`publisherGroupIds`). The container is separate from code deployment | Content changes need no code release | Approval discipline (what counts as `approved=true`) is a process control, not enforced by Azure |
| Recovery | Blob and container soft delete (30 days), versioning off | Accidental deletion is recoverable | Overwrites are not recoverable (no versioning). Turning versioning on costs storage and conflicts with retention rules for some clients |
| Network | The template creates its own VNet. Prefixes come from tfvars-style parameters (the IP plan). Three DNS zones: blob, file, azurewebsites | Templates must be copyable on their own | Peering to a hub and central DNS are not included; add them if your landing zone requires it |
| Custom domains | Optional list `customDomains`; managed certificates | The default `*.azurefd.net` host works without DNS | Each domain needs a DNS validation record before it works, and certificate renewal depends on the DNS provider |
| Monitoring | One switch, forced on in prod. Standard web tests from 3 locations hit `/` and `/api/documents`; alerts on availability, Front Door 5xx and origin health, Function 5xx; diagnostics to Log Analytics | The API path is only proven by testing it end to end | Two tests every 5 minutes cost about $34 a month. Alerts only help if the Action Group has owned, tested recipients |
| Governance | Mandatory tags, `CanNotDelete` lock and deny-delete stack settings in uat and prod, budget, Reader and Monitoring Contributor roles | Accidental deletes and overspend are the common failures | Locks block legitimate operators until the stack is changed |
| State | A **deployment stack** per environment (`stack-<workload>-<env>`), `--action-on-unmanage deleteAll`, in its own subscription | Removes what you remove from the template, with no state storage to bootstrap | The stack is the only record. `what-if` shows the change, but there is no plan file |
| Checks | `bicep build` and a linter with rules as errors. Cross-parameter checks that Bicep cannot express are in `scripts/deploy.sh` | Fails early, without Azure | Nothing proves "never public" except reading the template and `what-if`. A parameter file that says `false` for monitoring in prod is silently overridden |

## Cost estimate

Retail list prices in USD for West Europe (Front Door is global) from the [Azure Retail Prices API](https://prices.azure.com/api/retail/prices), retrieved on 2026-10-30. A month is 730 hours. Taxes, discounts, reservations and currency conversion are not included; re-check in the [pricing calculator](https://azure.microsoft.com/pricing/calculator/) before committing a budget.

Fixed monthly cost per environment:

| Item | Price used | dev, qa | uat, prod |
| --- | --- | --- | --- |
| Front Door Premium base fee (WAF managed rules included) | $330 a month | $330.00 | $330.00 |
| Static Web App, Standard | $9 per app a month | $9.00 | $9.00 |
| Function plan EP1 (1 vCPU, 3.5 GiB) | ($0.169 per vCPU-hour + 3.5 × $0.0121 per GiB-hour) × 730 = $154.29 per instance | $154.29 (1 instance) | $308.58 (2, zone redundant) |
| 3 private endpoints | $0.01 an hour | $21.90 | $21.90 |
| 3 Private DNS zones | $0.50 each a month | $1.50 | $1.50 |
| 2 standard web tests, 3 locations every 5 minutes | $0.000645 per run, 52,560 runs a month | $33.90 | $33.90 |
| Alerts (2 availability, 3 metric) | about $0.10 to $0.20 per rule | about $1 | about $1 |
| Storage (a few GB; ZRS or GZRS), Log Analytics (first 5 GB free) | small | about $1 | about $2 |
| **Fixed total** | | **about $553** | **about $707** |

Traffic-driven, per month: Front Door requests (Premium, about $0.015 to $0.017 per 10,000 in Europe and North America) and data out ($0.0825 per GB for the first 10 TB), Log Analytics beyond 5 GB ($2.99 per GB), storage and Function executions beyond the plan. Static Web Apps includes 100 GB of bandwidth. Each custom domain adds no test unless you add a URL to `availabilityUrls`.

Budgets in the parameter files: dev 600, qa 600, uat 800, prod 900 a month. Headroom over fixed cost is about $47 in dev and qa, $93 in uat and $193 in prod; uat is the tightest once traffic is added. Setting `enableMonitoring = false` in dev saves about $35 a month.

**Meters still to confirm.** Prices not returned by the API queries on the retrieval date are taken from the sibling templates' cost sections: Static Web Apps Standard (retrieved 2026-09-27), the private endpoint hour and the standard web test run (2026-09-27 and 2026-10-26), and Front Door Premium request price for Zone 1. The EP1 instance size (1 vCPU, 3.5 GiB) is from the Azure Functions Premium plan documentation; confirm it and the price per instance in the calculator.

## Folder layout

```
infrastructure/publicly-accessible-static-website-with-document-api-bicep/
├── main.bicep                    Subscription scope: resource group, then the modules
├── bicepconfig.json              Linter rules as errors
├── modules/                      naming (functions), network, private-endpoint, storage, function-app,
│                                 static-web-app, front-door, front-door-waf, monitoring, alerts, governance
├── environments/dev|qa|uat|prod/ main.bicepparam + deployment.env
├── scripts/                      deploy.sh · deploy.ps1
├── pipelines/                    azure-pipelines-site.yml · azure-pipelines-function.yml
├── ARCHITECTURE.md
├── c4-context.drawio · c4-containers.drawio
├── c4-context-lucidchart.drawio · c4-containers-lucidchart.drawio
└── .gitignore
```

## First-time setup

1. In `environments/<env>/deployment.env` set the subscription, the tenant and `PUBLISHER_GROUP_IDS`. In `main.bicepparam` set the governance tags, the IP ranges from your IP plan, the alert receivers and the viewer and operator groups. Replace every `<...>` placeholder.
2. **Identity for the deployment:** Contributor and User Access Administrator on the subscription (the template assigns roles), plus rights to approve private endpoint connections on the Function. Deployment stacks need Azure CLI 2.61 or later.
3. Review, then deploy:
   ```
   ./publicly-accessible-static-website-with-document-api-bicep/scripts/deploy.sh dev what-if
   ./publicly-accessible-static-website-with-document-api-bicep/scripts/deploy.sh dev deploy
   ```
   PowerShell: `./publicly-accessible-static-website-with-document-api-bicep/scripts/deploy.ps1 -Environment dev -Command deploy`
4. Do what the script prints: store the pipeline secrets (`AZURE_STATIC_WEB_APPS_API_TOKEN`, `SWA_CONFIG_JSON`), deploy the Function package from a network that reaches its private endpoint, and add DNS records if you use custom domains.
5. Publish documents: upload PDFs to the `documents` container with metadata `approved=true` as a member of a publisher group.

`./deploy.sh <env> show` prints the outputs: the public URL, the Front Door ID, the Function and storage names, and the custom domain validation tokens.

## Not included

- Example site content and example API code (the pipelines take a folder as a parameter).
- The Terraform twin.
- Key Vault (nothing reads a secret), hub peering and central private DNS, an immutability policy on the documents, and an infrastructure pipeline.
- Domain registration and DNS changes.

## To verify in dev before production

**Nothing has been built or run.** The Bicep CLI was not available when this was written, so `bicep build` and the linter have not been run, and nothing has been run against Azure, not even `what-if`. First check:

- `bicep build` and the linter for `main.bicep` and all four `main.bicepparam` files.
- Front Door Premium with a Private Link origin to a Function App whose public access is disabled, and that the Pending connection appears for the script to approve.
- The Function host with `vnetContentShareEnabled` and the key-based content share through the file private endpoint.
- `Microsoft.Insights/webtests` kind `standard` and the availability metric alert (scopes, hidden-link tags).
- `az stack sub create` with `--deny-settings-mode` and a `.bicepparam` file on your Azure CLI version, and `readEnvironmentVariable()` in the parameter files.
- That `/api/documents` returns only approved PDFs through Front Door, and that unapproved blobs and direct calls to the Function are refused.
