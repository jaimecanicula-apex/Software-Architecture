## 🎯 Scope

  

This guide packages and deploys the document API from `api/` to `func-eslalu-prod-001` using Azure Functions run-from-package ZipDeploy. The Function is independent of the Static Web Apps workflow.

  

Production configuration values and infrastructure fields belong in [Infrastructure Configuration Reference](Infrastructure-Configuration-Reference.md).

  

## ✅ Prerequisites

  

- Approved Function change, test evidence, deployment window, and rollback operator.

- Azure CLI, Node.js 24+, and npm available on the deployment workstation.

- Permission to read configuration, deploy packages, restart, and inspect logs for the target Function.

- Production Storage account and container confirmed.

- Function managed identity enabled with **Storage Blob Data Reader** or an approved narrower equivalent.

- Required Storage firewall, private endpoint, route, and DNS path healthy.

- Required application settings confirmed without exposing their values in evidence.

- Previous approved deployment package or package identifier retained for rollback.

  

## ⚙️ Required runtime and settings

  

The approved runtime must satisfy `api/package.json`; the documented Linux setting is `node|24`.

  

```powershell

az functionapp config set `

  --resource-group "<verified-resource-group>" `

  --name "func-eslalu-prod-001" `

  --linux-fx-version "node|24"

```

  

Required settings:

  

```text

FUNCTIONS_WORKER_RUNTIME=node

DATA_STORAGE_ACCOUNT=<approved production storage account>

DATA_CONTAINER=<approved production container>

WEBSITE_RUN_FROM_PACKAGE=1

```

  

The current code does not read the obsolete names `STORAGE_ACCOUNT_NAME` or `DOCUMENTS_CONTAINER_NAME`.

  

## 📦 Package contract

  

Azure must find these entries at ZIP root, not beneath an extra `api/` directory:

  

```text

host.json

index.js

package.json

package-lock.json

node_modules/

```

  

With `WEBSITE_RUN_FROM_PACKAGE=1`, Azure activates the package selected by `/home/data/SitePackages/packagename.txt`. Editing loose Kudu `wwwroot` files does not deploy new code.

  

## 🚀 Deployment procedure

  

From the repository root in PowerShell:

  

```powershell

Set-Location .\api

npm ci --omit=dev

Compress-Archive `

  -Path host.json,index.js,package.json,package-lock.json,node_modules `

  -DestinationPath ..\function-deploy-current.zip `

  -Force

Set-Location ..

```

  

Inspect the archive structure and record its approved checksum or release identifier according to policy. Then deploy:

  

```powershell

az functionapp deployment source config-zip `

  --resource-group "<verified-resource-group>" `

  --name "func-eslalu-prod-001" `

  --src ".\function-deploy-current.zip"

```

  

ZipDeploy writes a new package, updates the active package pointer, and recycles workers. Allow approximately 30–60 seconds for recycling before declaring failure. Remove unneeded local archives after evidence and retention requirements are satisfied; never commit packages or `node_modules/`.

  

## ✅ Verification

  

When network policy permits, verify the direct Function endpoint first, then the public Front Door route:

  

```powershell

curl.exe -i https://func-eslalu-prod-001.azurewebsites.net/api/documents

curl.exe -i https://eslasa.lu/api/documents

```

  

Confirm:

  

- Listing returns HTTP `200` with a valid `documents` array.

- Only approved `.pdf` and `.txt` blobs are listed.

- An approved document returns `200` with the expected content.

- Missing and unapproved documents return `404`.

- Invalid identifiers return `400`.

- No credential, connection string, SAS token, or internal exception is exposed.

- Front Door origin health, Function failures, latency, and Storage dependencies remain normal.

- The active package or deployment ID is recorded.

  

Direct origin access may be intentionally restricted. A blocked direct test is not failure when the public route, logs, and approved origin restrictions prove health.

  

## ↩️ Rollback

  

1. Declare rollback and stop additional releases.

2. Identify the last approved Function ZIP and verify its provenance.

3. Redeploy it with the same `config-zip` method.

4. Allow worker recycling.

5. Repeat direct-where-permitted and public-route verification.

6. Monitor Function and dependency telemetry.

7. Record the rollback and preserve the failed package/log evidence.

  

Do not roll back by editing loose Kudu files.

  

## 🧯 Troubleshooting

  

| Symptom | Primary checks |

| --- | --- |

| Old behavior remains | ZipDeploy result, active package pointer, ZIP contents, worker recycle period |

| Startup or module failure | `npm ci --omit=dev`, Node compatibility, `node_modules/` and package files at ZIP root |

| Listing returns `500` | Required app settings, managed identity token, Blob RBAC, Storage firewall, private endpoint, DNS, Storage health |

| Direct route works; public route fails | Front Door `/api/*` route, origin host header, probe, WAF, and origin restrictions |

| Both direct and public routes fail | Runtime, package activation, startup logs, app settings, identity, Storage, and networking |

| New document is absent | Supported extension and exact approval/category metadata; do not redeploy Function without evidence of a code issue |

  

Use [Incident and Troubleshooting Guide](Incident-and-Troubleshooting-Guide.md) for full diagnostic paths.

  

## 📋 Release record

  

Retain the change ID, source commit, dependency lock file, package identifier/checksum, target resource, deploy output, active package ID, approvers, test results, production verification, observation outcome, and rollback package reference.