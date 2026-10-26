# Privately accessible static website with storage (Terraform)

> **Golden template candidate.** This folder is written to become an APEX golden template. See [../../GOLDEN-TEMPLATES.md](../../GOLDEN-TEMPLATES.md) for what still has to happen before it is published as one.

Use this design when the site is for **internal users only** and they need a **shared file library**: anyone assigned to the site signs in with APEX Entra ID, then lists, uploads, downloads and deletes files in one private Azure Blob container. There is no database and no server code. Nothing is exposed to the internet.

- Without a file library, use [../privately-accessible-static-website](../privately-accessible-static-website).
- For external clients or users, use [../publicly-accessible-static-website](../publicly-accessible-static-website).
- Prefer Bicep to Terraform? The same design is in [../privately-accessible-static-website-with-storage-bicep](../privately-accessible-static-website-with-storage-bicep). Keep the two in step (see its README).

```
APEX user on the corporate network (VPN / ExpressRoute / office)
   │  resolves the site and the storage account through Private DNS
   ▼
Private endpoint ──▶ Azure Static Web App (public network access OFF)
   │                    │  APEX Entra sign-in, assigned groups only
   │                    ▼
   │                 content/privately-accessible-static-website-with-storage/
   │                    (build-free HTML, CSS, JS + a pinned copy of MSAL.js)
   │
   └─ the same browser, with the user's own Entra token (MSAL.js)
      ▼
   Private endpoint ──▶ Blob storage "files" container
                        (public access OFF, account keys OFF, versioning, soft delete,
                         optional malware scanning on upload)

In-VNet probe (Container Apps job, every 5 min) ──▶ site /healthz.html
Probe + diagnostics ──▶ Azure Monitor Private Link ──▶ Log Analytics / App Insights
                                                        ├─▶ alerts ─▶ Action Group
                                                        └─▶ workbook dashboard (viewer groups)
```

## How it differs from the private static website

| | Private static website | This template |
| --- | --- | --- |
| Files | None | One shared Blob container, `files` |
| Who can use files | n/a | Everyone in `allowed_group_ids`: read, upload, overwrite, delete |
| How the page reaches storage | n/a | The browser calls Blob storage with the signed-in user's own token (MSAL.js). No API, no account key |
| Entra app registration | Web sign-in | Adds a single-page-app redirect and the Azure Storage `user_impersonation` permission (admin consent once) |
| Private endpoints | Site, Azure Monitor | Site, Azure Monitor, storage |
| Site content | `content/privately-accessible-static-website/` | `content/privately-accessible-static-website-with-storage/`, which adds `files.html`, `files.js` and `vendor/msal-browser.min.js` |
| Pipeline secrets | Deployment token, `SWA_CONFIG_JSON` | Adds `FILES_CONFIG_JSON` (no secrets in it) |
| Terraform state key | `private-static-website/<env>.tfstate` | `private-static-website-with-storage/<env>.tfstate`, so the two never share state |

## Design decisions

| Concern | Decision | Why | Trade-off |
| --- | --- | --- | --- |
| Region | `location`, required in every environment's `terraform.tfvars` (no default), validated against the 5 regions that offer Static Web Apps | Data residency and latency are choices per organisation and environment; a silent default could place an environment in the wrong region | Only westus2, centralus, eastus2, westeurope and eastasia. Changing it later recreates the Static Web App, the storage account and the regional monitoring resources |
| Availability zones | `probe_zone_redundancy_enabled` spreads the availability probe's Container Apps environment across zones: on in uat and prod. The file library's zone resilience is its replication setting, `storage_replication_type` (ZRS in dev and qa, GZRS in uat and prod). The Static Web App, private endpoints and Private DNS have no zone setting; Azure keeps them resilient. The Terraform state storage is GZRS through `replication_type` in `bootstrap/` | A zone failure should not silence the probe or take the files offline in prod | The probe setting is fixed at creation (switching recreates its environment). GZRS costs about twice ZRS per GB. Switching replication type later is a migration, not an edit |
| Subnets | Two subnets: private endpoints (`private_endpoint_subnet_prefix`, now holding the site, Azure Monitor and storage endpoints) and the probe (`probe_subnet_prefix`, delegated to Container Apps). Names `snet-pe-<suffix>` and `snet-probe-<suffix>`, each with its own NSG, from the naming module | Address ranges come from each environment's IP plan, and separating the probe keeps its delegation away from the private endpoints | Two ranges to allocate per environment; the probe subnet needs at least a /27 to itself |
| Entry | Private endpoint in the spoke VNet; Static Web App public network access **off** | Every user is internal, so there is no internet entry to defend at all | Users off the corporate network cannot reach it, the design depends on the hub and corporate DNS, and deployment and preview environments with public access off still need verifying |
| Network | Own spoke VNet, NSGs denying internet inbound, Private DNS zones, optional hub peering | The template works on its own and joins the hub when the platform team is ready | More to own: IP ranges from the IP plan, peering and DNS coordination. Its own Private DNS zones can clash with central zones in a landing zone |
| Sign-in | APEX Entra ID, single tenant, *assignment required* for `allowed_group_ids`; secret rotates every 180 days | Entra refuses everyone else in the tenant, before the site sees a request | The client secret expires if the environment is not re-applied within about 210 days |
| File access path | The page signs the user in again with MSAL.js (silent when the session exists) and calls Blob storage directly with a token for `https://storage.azure.com/user_impersonation`. The storage CORS rule allows only the site's own origins | No server code to run, patch or scale, and no account key anywhere. Every blob operation in the logs carries the real user, not a shared identity. Static Web Apps built-in (managed) Functions cannot join a VNet, so they could not reach a private storage account | The browser holds a storage token, so any script that runs on the page could use it: the site's content security policy allows only its own scripts, and MSAL.js is a pinned copy. A user can call storage directly with their own token and skip the page. The app registration needs a one-time admin consent. Off the corporate network the page cannot reach storage even though the Static Web App might load |
| Storage account | StorageV2 with public network access off, shared keys off, TLS 1.2, no public blobs, cross-tenant replication off. One private endpoint in the private-endpoint subnet, registered in `privatelink.blob.core.windows.net` | Nothing can read the files except a signed-in user on the private network, and there is no key to leak or rotate | Operators who need to browse files in the portal need private network access and a role. The account name must be globally unique, so it carries a 4-character hash of the subscription ID |
| Who can do what | Everyone in `allowed_group_ids` gets a custom role at the `files` container: read, write, delete, add and blob-tag read (the tags hide malware-flagged files). It replaces Storage Blob Data Contributor, which cannot read tags | One shared library, as agreed: simple to understand and to audit | Anyone assigned can overwrite or delete any other user's file. Versioning and soft delete make that recoverable, not impossible. There are no per-user or per-team folders, and no read-only group |
| Recovery | Blob versioning, blob soft delete and container soft delete for `soft_delete_retention_days` (7 in dev and qa, 14 in uat, 30 in prod). A lifecycle rule deletes old versions after the same period | A mistaken overwrite or delete can be undone by an operator | Old versions and deleted files are billed as storage until they expire. Recovery is an operator task; the page has no undo |
| Malware scanning | Defender for Storage scanning on upload, `malware_scanning_enabled`: off in dev and qa, on in uat and prod (refused if turned off in prod). Files flagged malicious carry a blob tag and the page hides them | Files that colleagues share are the one place malware can enter this design | Scanning is per GB scanned plus a per-account charge, and the scan finishes after the upload: a file can be downloaded in the seconds before the result arrives. The page hides a flagged file but does not delete it, and anyone who calls storage directly still sees it. Dev and qa never exercise it |
| Upload limits | `max_upload_mb` and `allowed_extensions` are written to `files-config.json` at deploy time and checked in the browser | Stops honest mistakes such as a wrong file type or a huge file | Advice, not enforcement: a user calling storage directly bypasses them. A single request upload is also fine for the default 100 MB but is not built for multi-gigabyte files |
| Availability | Container Apps job inside the VNet requests `/healthz.html` every 5 minutes | Internet web tests cannot reach a private site; the job takes the same private path as users, with no server, code package or storage account | One location, from inside the VNet only: it does not test users' VPN or ExpressRoute path, certificate expiry, or the file library itself. The job image is pulled from the internet |
| Telemetry | Azure Monitor Private Link Scope with private-only ingestion. Blob read, write and delete logs and transaction metrics go to the same Log Analytics workspace | Monitoring data about a private site stays on the private network, and file activity is auditable by user | The Private Link Scope changes Azure Monitor DNS for the whole network, adds cost, and is one more link that can fail. Blob logs add ingestion volume per operation |
| Alerts | Availability below threshold, probe silent for 15 minutes, destructive changes, resource and service health, budget | A silent probe means the check itself or its private path failed, which availability alone would not show | A probe-silent alert says something broke but not whether it is the probe, the network or the site; someone must diagnose it. There is no storage-specific alert (capacity, 403 spikes) and no "Files" tab in the dashboard yet |
| Dashboard access | `monitoring_query_from_internet = true` by default | Viewers can open the dashboard from the portal anywhere they sign in; set false to limit it to the APEX network | Open from anywhere means any device where viewers sign in; limiting it means viewers need the corporate network |
| Governance | Mandatory tags, budget, delete lock in uat and prod, viewer and operator groups | Required for every golden template | The lock blocks legitimate teardown until removed through change control, and a budget only warns; it never stops spending. The lock does not protect individual blobs: versioning and soft delete do |

## Cost estimate

Retail list prices in USD for West Europe from the Azure Retail Prices API, the data source of the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/), retrieved on 2026-10-26. A month is 730 hours. Taxes, discounts, reservations and currency conversion are not included; re-check in the calculator before committing a budget.

Per environment, with an example workload of **100 GB stored, 10,000 writes and 100,000 reads a month, and 5 GB uploaded a month**. Old versions and soft-deleted files count as stored data, so a busy library costs more than this.

| Item | Price used | dev, qa (ZRS, no scanning) | uat, prod (GZRS, scanning) |
| --- | --- | --- | --- |
| Static Web App, Standard | $9 per app | $9.00 | $9.00 |
| Private endpoints, 3 (site, Azure Monitor, storage) | $0.01 an hour each, plus $0.01 per GB processed in and out | $21.90 | $21.90 |
| Private DNS zones, 6 (site plus 5 for Azure Monitor, including blob) | $0.50 per zone | $3.00 | $3.00 |
| Blob data stored, hot | ZRS $0.024 per GB, GZRS $0.046 per GB | $2.40 | $4.60 |
| Blob writes, 10,000 | ZRS $0.0675, GZRS $0.1175 per 10,000 | $0.07 | $0.12 |
| Blob reads, 100,000 | $0.0043 per 10,000 | $0.04 | $0.04 |
| Defender for Storage plan, per storage account | $0.006849 an hour (Global "Storage Account Defender Workload Unit", effective 2026-10-01) | $0 | $5.00 |
| Malware scanning, 5 GB | $0.15 per GB scanned | $0 | $0.75 |
| Availability probe: Container Apps job, 0.25 vCPU and 0.5 GiB, every 5 minutes | About 22,000 vCPU-seconds a month, inside the free grant | $0 | $0 |
| Alerts, including the probe-silent log alert | $0.15 to $1.00 per rule; activity log alerts free | about $2 | about $2 |
| Log Analytics and Application Insights | First 5 GB free, then $2.99 per GB; retention past 31 days $0.13 per GB a month | $0 up to 5 GB | $0 up to 5 GB |
| VNet, NSGs, Entra app, role definition, budget | No charge | $0 | $0 |
| **Total** | | **about $38** | **about $46** |

- **The file library adds about $10 a month in dev and qa and about $18 in uat and prod** over the private static website without storage (about $29). Most of it is the storage private endpoint ($7.30) and, in uat and prod, the Defender plan ($5).
- **Traffic-driven:** storage per GB, writes and reads, and scanning per GB uploaded. Ten times the data adds about $22 in ZRS and $41 in GZRS.
- **To confirm:**
  - The Container Apps "Environment Management Hour" meter ($0.143 an hour, about $104 a month) and whether it applies to the probe's Consumption-only environment. It is not in the totals.
  - Whether the per-account Defender plan fee applies when only malware scanning is switched on, and what the new "Storage Malware Scan GB Defender Workload Unit" meter ($0.006849 an hour) bills on top of the $0.15 per GB. The $5 above is the per-account meter.
- **Budgets** (100, 150, 200, 300) are several times the estimate; they can be lowered unless the environment meter above applies.

## Folder layout

```
infrastructure/privately-accessible-static-website-with-storage/
├── bootstrap/                 One-time: Terraform state storage
├── modules/
│   ├── naming/                Names, including vnet-, ampls-, pe-, app-, st- and role- prefixes
│   ├── network/               Spoke VNet, private-endpoint and probe subnets, NSGs,
│   │                          Private DNS zones, optional hub peering
│   ├── private-endpoint/      Generic private endpoint + DNS zone group
│   ├── static-web-app/        Static Web App with public_network_access_enabled
│   ├── storage/               File library: account, container, versioning, soft delete,
│   │                          CORS, private endpoint, user role, malware scanning, logs
│   ├── entra-app-auth/        Single-tenant app registration, assigned groups, rotating secret,
│   │                          SPA redirect and Azure Storage permission
│   ├── monitoring/            Log Analytics, App Insights (private ingestion), alerts,
│   │                          workbook, viewer/operator roles
│   ├── monitor-private-link/  Azure Monitor Private Link Scope + endpoint
│   └── availability-probe/    Scheduled Container Apps job inside the VNet (probe.sh)
├── stacks/static-website/     Root module for this design
│   ├── templates/             staticwebapp.config.json (sign-in, security headers)
│   └── tests/                 terraform test suites (mocked providers)
├── environments/dev|qa|uat|prod/  terraform.tfvars + backend.hcl
└── scripts/tf.sh · tf.ps1     ./privately-accessible-static-website-with-storage/scripts/tf.sh dev plan
```

## The file library page

`content/privately-accessible-static-website-with-storage/files.html` and `files.js`:

- **Sign-in:** MSAL.js (a pinned copy in `vendor/`, version 3.28.1, loaded with a subresource integrity hash) reuses the user's Entra session, so there is normally no second prompt. It asks for the Azure Storage scope; the first time, an admin must have consented (see First-time setup).
- **Settings:** the page reads `files-config.json`, written by the pipeline from the `files_config_json` output: tenant, app, storage account, container, size limit and allowed types. It holds no secret.
- **What it does:** lists files (hiding any that malware scanning flagged), uploads (asking before it replaces a file), downloads, and deletes (asking first).
- **Content security policy:** `staticwebapp_config_json` allows scripts only from the site itself and connections only to the site, `login.microsoftonline.com` and this one storage account.
- **Tested:** the JavaScript parses; it has **not** been run in a browser against real storage.

## Monitoring

Every environment gets the full set, and none of it uses the internet:

- **Availability:** a Container Apps job inside the VNet requests `https://<site>/healthz.html` every 5 minutes and writes the result to Application Insights.
- **Alerts:**
  - availability below threshold (sev 1)
  - the probe stops reporting for 15 minutes (sev 1)
  - destructive or security changes: deletions, role assignments, removed locks
  - resource health, Azure service health, and budget
- **File activity:** blob logs (who read, wrote or deleted what) and transaction metrics go to Log Analytics.
- **Private telemetry:** the probe's results go through the Azure Monitor Private Link Scope, and ingestion is private-only.
- **Who can see it:**
  - `monitoring_viewer_principal_ids` and `monitoring_operator_principal_ids` get the same roles as in the public design, on this resource group only.
  - `monitoring_query_from_internet = true` (the default) lets them open the dashboard from the Azure portal anywhere they can sign in. `false` limits it to the APEX network.

## Sign-in

- **App registration:** `entra-app-auth` creates a single-tenant registration with two redirect URIs: `https://<site>/.auth/login/aad/callback` (Static Web Apps sign-in) and `https://<site>/files.html` (MSAL.js, single-page app). For a custom domain, add it to `additional_site_origins`.
- **Who gets in:** *assignment required* is on, so only `allowed_group_ids` can sign in. Everyone else in APEX is refused by Entra itself. The same groups get the file library role.
- **Storage permission:** the registration requests the delegated Azure Storage `user_impersonation` permission. Entra needs an admin to consent once, or every user is asked.
- **Client secret:** the secret rotates every 180 days (`time_rotating`). The next apply after rotation updates the Static Web App settings. MSAL.js uses no secret.
- **If pipelines may not create app registrations:** set `create_entra_app = false` and pass `existing_entra_client_id` and `existing_entra_client_secret`. The existing registration then needs the SPA redirect and the Azure Storage permission added by hand.
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
   - the file library settings (`storage_replication_type`, `soft_delete_retention_days`, `malware_scanning_enabled`, `max_upload_mb`, `allowed_extensions`)
3. **Identity for `apply`:** the identity needs these roles:
   - Contributor and User Access Administrator on the subscription (the file library creates a role definition and role assignments)
   - Security Admin, or another role that can change Defender for Cloud settings, where `malware_scanning_enabled` is on
   - Network Contributor on the hub, if you set `hub_virtual_network_id`
   - Entra rights to create app registrations (Application Developer or Cloud Application Administrator), or use `create_entra_app = false`
4. Deploy:
   ```
   ./privately-accessible-static-website-with-storage/scripts/tf.sh dev init
   ./privately-accessible-static-website-with-storage/scripts/tf.sh dev plan
   ./privately-accessible-static-website-with-storage/scripts/tf.sh dev apply
   ```
5. **Admin consent:** in Entra ID, open the app registration named by `entra_client_id` (output) and grant admin consent for the Azure Storage `user_impersonation` permission.
6. **Pipeline secrets:** store `static_web_app_deployment_token`, `staticwebapp_config_json` and `files_config_json` as the internal pipeline secrets (`AZURE_STATIC_WEB_APPS_API_TOKEN_INTERNAL_FILES`, `SWA_CONFIG_JSON`, `FILES_CONFIG_JSON`). The pipelines write both configs into `content/privately-accessible-static-website-with-storage/` before uploading.

## What the platform team must do

- **Hub peering:** create the hub side of the peering. This stack only creates the spoke side, and only when `hub_virtual_network_id` is set.
- **DNS:** make corporate DNS resolve the zones in the `private_dns_zones` output, including `privatelink.blob.core.windows.net`, so users resolve the storage account to its private address. Either link them to the hub, which the stack does when `hub_virtual_network_id` is set, or forward them to the hub DNS resolver.
- **Private DNS zones:** this design creates its own `privatelink.*` zones for Azure Monitor and blob storage. In a landing zone with central Private DNS zones, point to those zones instead. That is one of the golden-template changes.

## Not included

Kept out to keep the template simple. Each is a reasonable next step:

- Per-user or per-team files, or a read-only group
- Server-side checks of file type, size or content (needs an API: see the design discussion for a Function App or Container Apps variant)
- Storage alerts (capacity, 403 spikes) and a "Files" tab in the workbook
- Archive or cool tiering for old files

## To verify in dev before production

These have not been tested against Azure yet (`terraform validate` and the mocked `terraform test` suites pass for dev, qa and uat):

- The file library page, end to end: MSAL.js sign-in, list, upload, download and delete from a machine on the private network.
- The Azure Storage permission ID and the custom role's data actions (`blobs/tags/read` in particular), and that listing with `include=tags` works with the role.
- CORS for preview environments, whose host names differ from the default host.
- `azurerm_security_center_storage_defender` on a subscription that already has Defender for Storage settings.
- Deployment from GitHub Actions or Azure Pipelines still works with public network access disabled.
- Pull-request preview environments resolve through the private DNS zone.
- The probe image is pulled from MCR over outbound internet. For a fully closed network, mirror the image into an APEX registry and set `probe_image`.
