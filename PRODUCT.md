# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

APEX golden templates: approved, parameterized Azure starting points, each with example content it deploys. Infrastructure is Terraform (the private static website with storage also has a Bicep twin), with dev, qa, uat and prod environments in separate subscriptions. Catalogue and roadmap: `GOLDEN-TEMPLATES.md`.

Two kinds of example content:

- **Build-free static sites:** plain HTML, CSS and JavaScript with no build step, served from Azure Static Web Apps. Everything in a static-site content folder is uploaded as-is.
- **Containerised Python apps:** Flask applications built into a container image and run on Azure Container Apps.

| Template | Infrastructure | Example content | Edge / entry | Sign-in | Data |
| --- | --- | --- | --- | --- | --- |
| Public static website | `infrastructure/publicly-accessible-static-website/` | `content/publicly-accessible-static-website/` | Front Door + WAF, internet | None (anonymous) | None |
| Public sign-in static website | `infrastructure/public-signin-static-website/` | `content/public-signin-static-website/` | Front Door + WAF, internet | Entra ID, approved B2B guests | None |
| Private static website | `infrastructure/privately-accessible-static-website/` | `content/privately-accessible-static-website/` | Private endpoint, APEX network only | APEX Entra ID, assigned groups | None |
| Private container app | `infrastructure/privately-accessible-container-app/` | `content/python-mvc-app/` | Internal Container Apps environment | APEX Entra ID, assigned groups | None (CSV converted in memory) |
| Private container app with database and storage | `infrastructure/privately-accessible-container-app-with-database-and-storage/` | `content/python-crud-app/` | Internal Container Apps environment | APEX Entra ID, then app-level username/password | PostgreSQL + Blob Storage |
| Private static website with storage | `infrastructure/privately-accessible-static-website-with-storage/` | `content/privately-accessible-static-website-with-storage/` | Private endpoints, APEX network only | APEX Entra ID, assigned groups | Blob Storage, no database |
| Private static website with storage, Bicep | `infrastructure/privately-accessible-static-website-with-storage-bicep/` | Same content folder | Same | Same | Same |

## Users

Two audiences, each with its own designs (user-confirmed definitions):

- **Internal users:** anyone signing in with APEX Entra ID, meaning APEX employees, people from companies inside APEX, and contractors (IT and business colleagues alike). Internal designs are private: no internet exposure and no connection outside the APEX tenant. They are the private static website, the private static website with storage, and both private container apps.
- **External users:** external clients or users, never anyone from APEX itself. Anonymous: the public static website. Must sign in first: the public sign-in static website (Entra ID B2B guests of the APEX tenant, approved groups only).

Beyond that split, no specific job or persona is confirmed; do not assume one.

## Product Purpose

A catalogue of generic, reusable designs that any team can copy to build Azure infrastructure without redesigning it, deployed separately for each client or workload. Each deployment gets its own repository, Azure subscriptions and resources per environment, domain, monitoring and branding. The templates and example content must stay generic: never name or reference any specific client or existing site.

## Capabilities and Constraints

- **Static sites** publish static files only. The three existing static templates have no backend: no Function App, API, database or storage.
- **Private static website with storage:** signed-in internal users list, upload and download files in one shared library. There is no server code: the page uses MSAL.js (a pinned copy shipped with the site, no build step) to get the user's own Entra token for Azure Storage and calls Blob Storage through its private endpoint. Every user in the allowed groups can read, upload, overwrite and delete any file (Storage Blob Data Contributor on the one container). Versioning and soft delete make mistakes recoverable, and malware scanning on upload is optional. File type and size checks run in the browser only. No per-user or per-team privacy and no database.
- **Container apps** run any image that listens on port 8000 and answers `GET /healthz`. The example apps are a CSV converter (MVC) and an asset catalogue (CRUD, with PostgreSQL and Blob image storage).
- **No keys:** apps and pages reach storage with managed or user identities; storage account keys are disabled.
- **Monitored everywhere:** availability tests (five internet regions for public designs, an in-VNet probe for private ones), diagnostics, alerts and a workbook dashboard that named Entra ID groups can view. Monitoring cannot be off in prod.
- **Separate release paths:** content and apps ship through GitHub Actions or Azure Pipelines; infrastructure through Terraform (or Bicep for the Bicep twin).
- **Static sites stay build-free:** no build tooling; output must remain directly servable static files.
- Undecided: primary audience per deployment, accessibility standard, and whether analytics or cookies are used.

## Brand Commitments

- Typography (user-confirmed): primary face `Texturina, Arial, sans-serif` for headings, display text and the seal; secondary face `Roboto, Arial, sans-serif` for body copy, navigation, labels and UI. Code and resource names use the system monospace stack only.
- Branding is per client/issuer: logo, colours, typography, company text, and contact details come from each client. The design must work as a reusable pattern that takes a client's brand, not as one fixed identity.
- No client names, wording, contact details, domains, identifiers, documents, or branding from any existing deployment may appear in the generic content or carry over between clients.

## Evidence on Hand

- Each template's `README.md` (design decisions, cost estimate, setup) and `ARCHITECTURE.md` (C4 model), with draw.io C4 diagrams beside them.
- The public static site's architecture page: `content/publicly-accessible-static-website/architecture.html`.
- Example app source and tests in `content/python-mvc-app/` and `content/python-crud-app/`.
- No brand assets or client content are in this workspace. Do not invent company text, documents, testimonials, or claims.

## Product Principles

1. Legal-approved copy only: every piece of public wording and every document requires client Legal/Compliance approval. Use placeholders instead of writing claims.
2. Brand-agnostic by construction: structure and components must re-skin cleanly per client without code rewrites.
3. Simple by default: static sites have no build step and no framework dependency; add compute, storage or a database only when the template's purpose needs it.
4. Private by default for internal users: no public endpoints, no storage keys, sign-in before any page.
5. Explicit publication: only approved content ever appears publicly.
