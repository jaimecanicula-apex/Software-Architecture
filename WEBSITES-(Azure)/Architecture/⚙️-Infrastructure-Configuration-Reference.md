


## 🎯 Purpose
---
  

This is the canonical register for production configuration used by the repository documentation. It separates **source-confirmed values** from fields that must be verified in the Azure control plane or authoritative infrastructure-as-code repository.

  

Do not copy a placeholder into production, infer a name from naming conventions, or treat an inventory entry as proof that a control is configured correctly. Never record secrets in this document.

[[_TOC_]]

## ✅ Source-confirmed production values
---

| Setting | Value | Evidence in repository |
| --- | --- | --- |
| Public URL | `https://eslasa.lu` | Application and documentation |
| Production branch | `main` | GitHub Actions workflow |
| Frontend source | `/app` | GitHub Actions workflow |
| Frontend build | Skipped; files deploy directly | GitHub Actions workflow |
| Function App name | `func-eslalu-prod-001` | Deployment documentation |
| Function runtime requirement | Node.js 24 or later | `api/package.json` |
| Function model | Azure Functions Node.js v4 | `@azure/functions` application code |
| Function API prefix | `/api` | Azure Functions default route prefix |
| Storage account publishing target | `steslalu001` | Upload script |
| Blob container publishing target | `eslalu-data` | Upload script |
| Front Door endpoint hostname | `fde-eslalu-prod-001-a3egesdsfhdwaae.a01.azurefd.net` | Static Web App configuration |
| Required Front Door ID | `96ef97f5-b554-41a9-94a6-b909b351fd76` | Static Web App configuration |
| Allowed forwarded hosts | `eslasa.lu`; recorded Front Door hostname | Static Web App configuraton |
| Static Web App deployment secret name | `AZURE_STATIC_WEB_APPS_API_TOKEN` | GitHub Actions workflow |
| Function storage settings | `DATA_STORAGE_ACCOUNT`; `DATA_CONTAINER` | Function source |
| Function deployment mode | `WEBSITE_RUN_FROM_PACKAGE=1` | Deployment documentation |
| Domain workflow | L2/L3 through MarkMonitor | Project documentation |

> **Required reconciliation:** the values of `DATA_STORAGE_ACCOUNT` and `DATA_CONTAINER` configured on the production Function App must equal the approved production storage target. Source confirms what the publishing script uses, not what the Azure app settings currently contain.

  

## 🗂️ Controlled resource register
---
  

Complete the unverified fields in the organisation's controlled configuration inventory. Sensitive values and operational contacts belong in approved systems, not this public repository.

  

| Resource type | Known name / quantity | Required fields to verify |
| --- | --- | --- |
| Subscription | Not recorded | Subscription name and ID, tenant, management group, owner |
| Resource group | Not recorded | Name, region policy, tags, locks, owner |
| Front Door profile and endpoint | Endpoint hostname known | Profile/endpoint names and IDs, SKU, state, routes, rule sets |
| Front Door WAF policy | 1 identified | Name/ID, prevention or detection mode, managed rules, custom rules, exclusions |
| Custom domain | `eslasa.lu` | Validation state, DNS records, certificate type/state/expiry, renewal owner |
| Static Web App | 1 identified | Name/ID, default hostname, region, SKU, deployment token rotation owner |
| Function App | `func-eslalu-prod-001` | Resource group, ID, region, OS, identity principal ID, network access, scale |
| App Service plan | 1 identified | Name/ID, SKU, operating system, capacity, zone configuration |
| Storage account | `steslalu001` from upload script | ID, region, SKU, redundancy, firewall, public access, recovery, lifecycle |
| Blob container | `eslalu-data` from upload script | Public access, retention, immutability if required, role scope, diagnostics |
| Key Vault | 1 identified | Name/ID, consumers, RBAC/access-policy model, network access, purge protection |
| Virtual network | 1 identified | Name/ID, region, CIDRs, DNS settings, peerings, owner |
| Subnets | Not enumerated | Names, CIDRs, delegation, service endpoints, resource associations |
| Network security group | 1 identified | Name/ID, subnet/NIC association, effective rules, flow logging |
| Route table | 1 identified | Name/ID, subnet association, routes, next hops, propagation settings |
| Private endpoints | 4 identified | Name, target, subresource, subnet, private IP, approval state, DNS zone group |
| Private endpoint NICs | 4 identified | Name, private endpoint mapping, private IP configuration |
| Private DNS zones | Not confirmed | Zone names, links, record sets, auto-registration, owners |
| Network Watcher | 1 identified | Name/region, enabled diagnostics, retention, owner |
| Diagnostic destination | Not recorded | Log Analytics workspace/storage/Event Hub, IDs, retention, access |
| Alert rules | Not enumerated | Name, signal, scope, threshold, severity, evaluation window, runbook |
| Action Group | 1 identified | Name/ID, receivers, escalation, test date, owner |
| Resource locks and recovery | Not recorded | Scope, lock level, backup/restore approach, recovery objectives |

  

## 🌐 Front Door and WAF baseline
---
  

Record and validate:

  

- Profile and endpoint names, SKU, custom domain, and certificate status.

- Website route to the Static Web App and `/api/*` route to the Function App.

- Accepted/forwarding protocols, HTTPS redirect, route patterns, origin groups, origins, priority, weight, and host headers.

- Health probe paths, methods, intervals, expected status, and origin-health thresholds.

- Compression and caching rules; document API responses must not remain stale after publication.

- WAF association, policy mode, managed rule-set versions, bot protection, custom rules, and logging.

- Every WAF exclusion's business reason, approver, owner, creation date, expiry/review date, and narrow scope.

- Access, health-probe, and WAF diagnostic destinations and retention.

  

When Front Door is replaced, update the ID and allowed forwarded hosts in the Static Web App configuration before cutover.

  

## 🌐 Static Web App baseline
---
  

Repository deployment configuration:

  

```text

app_location=/app

api_location=

output_location=

skip_app_build=true

```

  

The empty API location is intentional because the Function App is deployed separately. Origin protection requires:

  

- `AzureFrontDoor.Backend` in allowed IP ranges.

- The source-confirmed `X-Azure-FDID` request header.

- Only approved forwarded hosts.

- A protected and rotated deployment token stored only as the GitHub secret `AZURE_STATIC_WEB_APPS_API_TOKEN`.

  

## ⚙️ Function App baseline
---
  

Required application settings:

  

```text

FUNCTIONS_WORKER_RUNTIME=node

DATA_STORAGE_ACCOUNT=<approved production storage account>

DATA_CONTAINER=<approved production container>

WEBSITE_RUN_FROM_PACKAGE=1

```

  

Required platform configuration:

  

- Linux runtime `node|24` or a later application-supported version approved through testing.

- Managed identity enabled and identifiable by principal ID.

- **Storage Blob Data Reader** or an approved narrower equivalent at the container or storage scope.

- Network path and DNS resolution to the Blob endpoint.

- Approved inbound origin restrictions and Front Door host-header behavior.

- Application/platform diagnostics, dependency telemetry, scaling, health, and restart visibility.

- No storage key, connection string, or SAS token in source or browser-visible settings.

  

The package must contain `host.json`, `index.js`, package files, and production `node_modules/` at ZIP root. Deployment specifics belong in [Azure Function Deployment](Azure-Function-Deployment.md).

  

## 📦 Storage baseline
---
  

Required controls:

  

- Container is private and anonymous Blob access is disabled unless formally approved.

- Function identity has read-only data-plane access at the narrowest practical scope.

- Publisher groups have only the approved Blob data-plane permissions.

- Firewall, private endpoint, and private DNS settings permit intended workloads only.

- Soft delete, versioning, retention, lifecycle, immutability, and recovery match legal and operational policy.

- Authorization, availability, capacity, and transaction diagnostics reach the approved destination.

- Storage account and container configured on the Function match the publishing target.

  

Supported public metadata:

  

| Metadata | Requirement | Consumer |
| --- | --- | --- |
| `approved` | Exact logical value `true` required for public listing/download | API |
| `category` | One of the four supported category identifiers | Frontend grouping |
| `publicationdate` | `YYYY-MM-DD` | Frontend display and ordering |
| `displayname` | Optional | API and frontend display |
| `description` | Required by publishing workflow for announcements | Announcement display |
  

## 🔌 Network baseline

  

For every subnet, record purpose, CIDR, delegation, NSG, route table, private endpoints, service endpoints, and DNS dependencies. For every private endpoint, record target resource and subresource, private IP, NIC, subnet, connection state, DNS zone group, and owner.

  

Validate the effective path from the Function environment to the Blob endpoint, including:

  

1. DNS resolves the intended public or private endpoint according to design.

2. Private DNS zones are linked to the correct virtual networks.

3. NSG and user-defined route behavior permits the connection.

4. Storage firewall and private endpoint approval permit the Function.

5. Network Watcher or equivalent diagnostics can investigate failures.

  

Do not assume all four private endpoints target Storage or Key Vault; confirm each target in Azure.

  

## 🔑 Identity and access matrix
---
  

| Scope | Minimum intended permission | Principal type |
| --- | --- | --- |
| GitHub repository | Read/contribute/approve/administer according to duty | Corporate groups and service integration |
| Static Web App | Deployment or operational role only where required | Delivery/platform groups |
| Function App | Deployment, configuration, or read access by duty | Application/platform groups |
| Blob container | Blob Data Reader | Function managed identity |
| Blob container | Blob Data Contributor or approved narrower role | Authorised publisher group |
| Front Door / WAF | Contributor or approved custom role | Platform/security groups |
| DNS / MarkMonitor | Corporate domain-change permission | L2/L3 domain team |
| Monitoring | Reader and alert-management permissions by duty | Operations/security groups |


Use groups rather than direct assignments, separate approval from publishing where policy requires, time-limit privileged elevation, and recertify access periodically.

  

## 📊 Monitoring and diagnostics baseline
---
  

At minimum, collect and own:

  

- Front Door access, origin-health, latency, and WAF logs.

- Static Web App deployment status and preview/production failures.

- Function requests, failures, latency, restarts, throttling, and Storage dependencies.

- Storage availability, authorization failures, capacity, and transactions.

- Activity Log events for deletion, identity, network, security, and policy changes.

- Custom-domain validation and certificate expiry state.

- GitHub production workflow failures.

  

Every alert must define scope, signal, severity, threshold, evaluation window, owner, Action Group, escalation path, and runbook. Action Group delivery must be tested on an approved schedule.

  

## 🛡️ Governance baseline
---
  

- Apply mandatory environment, owner, application, cost-centre, data-classification, and support tags.

- Protect critical resources with approved locks and deletion controls.

- Use authoritative IaC where available; record and reconcile emergency manual changes.

- Enable Azure Activity Log and appropriate resource diagnostics with policy-compliant retention.

- Store secrets in approved secret stores, not documentation, repository files, or screenshots.

- Record recovery objectives, storage recovery behavior, rollback artifacts, and restore test evidence.

  

## ✅ Configuration review
---
  

- [ ] All inventory fields have an owner and latest verification date.

- [ ] Source-confirmed values match the production control plane.

- [ ] Front Door routes, origin host headers, and origin restrictions agree.

- [ ] WAF mode, rules, and exclusions are approved and logged.

- [ ] Function runtime, settings, active package, and identity are correct.

- [ ] Function and publishing workflow use the same storage target.

- [ ] Storage privacy, retention, lifecycle, and recovery are approved.

- [ ] Four private endpoints, NICs, subnets, and DNS mappings are documented.

- [ ] RBAC assignments are least privilege and group-based where possible.

- [ ] Diagnostics, alerts, Action Group recipients, and retention are tested.

- [ ] DNS ownership, records, certificate, and renewal responsibilities are recorded.

- [ ] Resource locks, recovery objectives, and restore evidence are current.

- [ ] No secret or credential appears in the inventory.