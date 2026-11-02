# Publicly accessible static website with a document API (Bicep): architecture

C4 model of the template, in [Mermaid](https://mermaid.js.org/). The same views are in [c4-context.drawio](c4-context.drawio) and [c4-containers.drawio](c4-containers.drawio), with Lucidchart-import copies [c4-context-lucidchart.drawio](c4-context-lucidchart.drawio) and [c4-containers-lucidchart.drawio](c4-containers-lucidchart.drawio). Keep all of them in step when the architecture changes.

## Level 1: system context

```mermaid
flowchart LR
    Visitor["👤 Public visitor<br/>reads published documents"]
    Publisher["👤 Publisher<br/>uploads approved PDFs"]
    Engineer["👤 Platform engineer<br/>deploys and operates"]
    System["Public website with document API<br/>(this template)"]
    Entra["Microsoft Entra ID"]
    DevOps["Azure DevOps / GitHub<br/>delivery pipelines"]
    DNS["DNS provider<br/>custom domains"]

    Visitor -->|"HTTPS"| System
    Publisher -->|"Entra ID sign-in, upload"| System
    Publisher --> Entra
    Engineer -->|"deploy.sh, stacks"| System
    DevOps -->|"site and API packages"| System
    DNS -.->|"CNAME and validation"| System
```

## Level 2: containers (one environment)

```mermaid
flowchart TB
    Visitor["👤 Public visitor"] -->|HTTPS| FD
    Publisher["👤 Publisher"] -->|"Entra ID, public endpoint"| Blob

    subgraph Edge["Public edge (global)"]
        FD["Front Door Premium<br/>HTTPS redirect, routing"]
        WAF["WAF policy<br/>Prevention in uat and prod"]
        WAF --- FD
    end

    subgraph Hosting["Application hosting"]
        SWA["Static Web App (Standard)<br/>accepts only this Front Door"]
        Func["Function App (EP1, Linux, Node)<br/>public access disabled<br/>system-assigned identity"]
    end

    subgraph Net["VNet"]
        SnetF["Integration subnet<br/>delegated Microsoft.Web/serverFarms"]
        SnetP["Private endpoint subnet"]
        PE["Private endpoints<br/>blob, file, Function"]
        DNSZ["Private DNS zones<br/>blob, file, azurewebsites"]
        SnetP --- PE
        PE -.-> DNSZ
    end

    subgraph Data["Data"]
        Blob[("Storage account<br/>private container 'documents'<br/>+ Function host storage")]
    end

    subgraph Ops["Monitoring"]
        LAW["Log Analytics"]
        AI["Application Insights<br/>availability tests"]
        AG["Action Group + alerts"]
        LAW --> AG
        AI --> AG
    end

    FD -->|"/*"| SWA
    FD -->|"/api/* via Private Link"| Func
    Func -->|"VNet integration, route all"| SnetF
    Func -->|"managed identity, Blob Data Reader"| PE
    PE --> Blob
    FD -. logs .-> LAW
    Func -. telemetry .-> AI
    Blob -. logs .-> LAW
```

## Level 3: components of the Function App

```mermaid
flowchart LR
    Req["GET /api/documents<br/>GET /api/documents/{id}"] --> Routes["HTTP routes<br/>anonymous, behind Front Door"]
    Routes --> Validate["Identifier validation<br/>simple .pdf names only"]
    Routes --> Filter["Approval filter<br/>.pdf and approved=true"]
    Filter --> Client["Blob client<br/>DefaultAzureCredential"]
    Validate --> Client
    Client -->|"private endpoint"| Container[("documents container")]
    Filter --> Map["Public mapping<br/>id, displayName, category, group,<br/>size, lastModified, publicationDate"]
    Routes --> Headers["Response headers<br/>Cache-Control no-store, nosniff"]
```

The API code is not part of the template; the components above are the contract the template's permissions and routing assume: read-only access, PDFs only, 404 for missing and unapproved documents alike, no caching.

## Trust boundaries

| Boundary | Control |
| --- | --- |
| Internet → Front Door | HTTPS only with redirect, managed certificates, WAF, origin health probes |
| Front Door → Static Web App | `AzureFrontDoor.Backend` allow-list, required `X-Azure-FDID`, allowed forwarded hosts |
| Front Door → Function App | Private Link connection approved on the Function; public network access disabled |
| Function → Storage | System-assigned identity, Storage Blob Data Reader, private endpoint through VNet integration |
| Publisher → Storage | Entra ID, Storage Blob Data Contributor, anonymous access off |
| Operator → Azure | Entra ID, RBAC, delete lock and deny-delete stack in uat and prod |

## Deployment

```mermaid
flowchart TB
    Engineer["👤 Platform engineer"] --> Script["scripts/deploy.sh · deploy.ps1"]
    Script -->|"preflight checks"| Script
    Script -->|"az stack sub create"| Stack["Deployment stack<br/>stack-&lt;workload&gt;-&lt;env&gt;"]
    Script -->|"approve Private Link connection"| Func["Function App"]
    Params["environments/&lt;env&gt;/main.bicepparam<br/>deployment.env"] --> Stack
    Stack --> Main["main.bicep<br/>subscription scope"]
    Main --> Mods["modules/*.bicep"]
    PipeSite["azure-pipelines-site.yml"] -->|"site + origin lock"| SWA["Static Web App"]
    PipeFunc["azure-pipelines-function.yml"] -->|"ZipDeploy, private network agent"| Func
```

**Status:** nothing has been built or deployed. The Bicep CLI was not available when this was written.
