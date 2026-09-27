# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Build-free static site: plain HTML, CSS, and JavaScript with no build step, served from Azure Static Web Apps behind Azure Front Door and its WAF. No backend: no Function App, API, database or Blob Storage. Infrastructure is Terraform in three designs: `infrastructure/publicly-accessible-static-website/` (Front Door + WAF, external, anonymous), `infrastructure/public-signin-static-website/` (Front Door + WAF, Entra sign-in, approved guests) and `infrastructure/privately-accessible-static-website/` (private endpoint, APEX Entra sign-in, internal), each with dev, qa, uat, prod and per-environment subscriptions. Both are future APEX golden templates (`GOLDEN-TEMPLATES.md`). `WEBSITES-(Azure)/` is a reference for the edge, delivery and operations pattern only; its document API is out of scope.

## Users

Two audiences, each with its own design (user-confirmed definitions):

- **Internal users:** anyone signing in with APEX Entra ID, meaning APEX employees, people from companies inside APEX, and contractors (IT and business colleagues alike). Internal sites are private: no internet exposure and no connection outside the APEX tenant. Design: `infrastructure/privately-accessible-static-website/` with `content/privately-accessible-static-website/`.
- **External users:** external clients or users, never anyone from APEX itself. Anonymous public design: `infrastructure/publicly-accessible-static-website/` with `content/publicly-accessible-static-website/`. When they must sign in first: `infrastructure/public-signin-static-website/` with `content/public-signin-static-website/` (Entra ID sign-in as B2B guests of the APEX tenant, approved groups only).

Beyond that split, no specific job or persona is confirmed; do not assume one.

## Product Purpose

A generic, reusable pattern for publishing static websites, deployed separately for each client. Each deployment gets its own repository, Azure subscription and resources per environment, domain, deployment token, monitoring, and branding. The site itself must stay generic: never name or reference any specific existing client or reference site.

## Capabilities and Constraints

- Scope is publishing static websites only. Document APIs, approved-document publishing, Functions and storage are out of scope unless the user reintroduces them.
- Every environment is monitored: availability tests from five regions, Front Door and WAF logs, alerts, and a shared workbook dashboard that named Entra ID groups can view.
- Site content and infrastructure follow separate controlled release paths (GitHub Actions or Azure Pipelines for content, Terraform for infrastructure).
- No build tooling may be introduced; output must remain directly servable static files.
- Undecided: primary audience, accessibility standard, and whether analytics or cookies are used.

## Brand Commitments

- Typography (user-confirmed): primary face `Texturina, Arial, sans-serif` for headings, display text and the seal; secondary face `Roboto, Arial, sans-serif` for body copy, navigation, labels and UI. Code and resource names use the system monospace stack only.
- Branding is per client/issuer: logo, colours, typography, company text, and contact details come from each client. The design must work as a reusable pattern that takes a client's brand, not as one fixed identity.
- No client names, wording, contact details, domains, identifiers, documents, or branding from any existing deployment may appear in the generic site or carry over between clients.

## Evidence on Hand

- Architecture of the static-website Terraform stack: `infrastructure/publicly-accessible-static-website/ARCHITECTURE.md` (source) and the public page `content/publicly-accessible-static-website/architecture.html`.
- Architecture, deployment, governance, and operations documentation in `WEBSITES-(Azure)/`.
- No site source code, brand assets, or client content is in this workspace. Do not invent company text, documents, testimonials, or claims.

## Product Principles

1. Legal-approved copy only: every piece of public wording and every document requires client Legal/Compliance approval. Use placeholders instead of writing claims.
2. Brand-agnostic by construction: structure and components must re-skin cleanly per client without code rewrites.
3. Static and simple: no build step, no framework dependency, and fast delivery from the edge.
4. Explicit publication: only approved content ever appears publicly.
