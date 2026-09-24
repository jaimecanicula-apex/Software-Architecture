## 🎯 Purpose

  

Use this runbook to create a separate investor-document website from the Esla S.A. solution pattern. Each issuer should have a separate repository, Azure resource set, domain, identities, storage target, deployment credentials, monitoring, and controlled records unless an approved shared-service architecture explicitly states otherwise.

  

This document is a step-by-step checklist for gathering client requirements, building the website and API, provisioning the supporting services, publishing approved content, going live, and handing the service to operations. Complete each checkbox and retain the referenced evidence. Use the linked architecture, configuration, deployment, publication, operations, incident, acceptance, and change guides for detailed controls.

  

Do not copy Esla names, wording, contact details, domains, Azure identifiers, credentials, documents, or branding into a new issuer website. Treat the existing solution only as a technical pattern.

[[_TOC_]]
  

## 🧭 How to use this runbook
---
  

This runbook has two deliberately separate parts:

  

| Part | Audience | Purpose |
| --- | --- | --- |
| **Part A — Questions for the client** | Project manager, business analyst, client, and Legal/Compliance | Collect and approve the business, content, branding, domain, legal, and service requirements before building anything |
| **Part B — Internal build procedure** | Application, cloud platform, security, DNS, DevOps, and operations teams | Create the repository and infrastructure, configure the application, test it, launch it, and hand it over |
  

Do not send Part B to the client as a questionnaire. Do not start production implementation until the mandatory Part A answers are approved. Record `Not required` with an approver where a question does not apply; do not leave it blank.

  

## 📥 Information required before work starts
---
  

| Area | Required decision or artifact |
| --- | --- |
| Business | Issuer, purpose, market, go-live date, sponsor, service owner |
| Legal/Compliance | Disclosure obligations, wording, categories, approval/withdrawal, retention |
| Branding/content | Logo, colours, typography, company text, office, email, links, footer |
| Accessibility/privacy | Target standard, test approach, cookies/analytics/privacy requirements |
| Domain | Production/test domains, registrar, DNS owner, validation, certificate ownership |
| Azure | Tenant, subscription, resource group, region, naming, tags, budget, support model |
| Security | Classification, identity, network, WAF, logging, access review, recovery controls |
| Delivery | GitHub organisation, repository, protected branch, reviewers, secrets, approvals |
| Operations | Monitoring, support hours, escalation, recovery objectives, handover owner |
  

Do not begin production implementation without named owners, approved requirements, and a documented architecture decision.

  

---

  

# Part A — Questions to ask the client

  

## 🧾 Client information questionnaire
---
  

Send **only this part** to the client at the start of the project. Record each answer in an approved requirements document and identify an owner and due date for every unanswered item. Examples are illustrative and must not be treated as approved content.

  

### 1. Company and project details
---
  

- [ ] **Confirm the full legal name of the company or entity.** This is the authoritative name used in headings, legal wording, document descriptions, and approval records.

- [ ] **Confirm the website's purpose.** State whether it is an investor-relations portal, transaction website, regulatory publication site, or another type of service.

- [ ] **Confirm the target go-live date and any regulatory deadline.** Include the time zone and any dependencies such as listing, transaction closing, or DNS approval.

- [ ] **Name the business sponsor and content owner.** These people approve scope, wording, documents, and go-live readiness.

  

### 2. Domain and audience
---
  

- [ ] **Provide the preferred production domain name.** Also request an alternative in case the first choice is unavailable.

- [ ] **Confirm whether a test or staging domain is required.** Record who may access it and whether unpublished information could appear there.

- [ ] **Identify the expected audience and countries served.** This informs legal wording, language, accessibility, privacy, and security requirements.

- [ ] **Confirm required languages.** For each language, identify who supplies and approves translations.

  

### 3. Website title
---
  

- [ ] **Provide the exact website title and capitalization.** Example: *Argentum Capital S.A.* or *Esla S.A.* Confirm whether the title is the legal entity name or an approved public-facing name.

- [ ] **Provide an optional subtitle or strapline.** Confirm whether it should appear in the page header, browser title, search description, or all three.

  

### 4. Address and contact information
---
  

- [ ] **Office address:** provide the complete approved public address. Example: *3 rue Gabriel Lippmann, L-5365 Munsbach, Grand Duchy of Luxembourg*.

- [ ] **Email address:** provide the public mailbox and confirm that it is monitored. Example: *EslaSA@apexgroup.com*.

- [ ] **Phone number:** provide the number in international format or explicitly confirm that no telephone number should be displayed.

- [ ] **Contact wording:** confirm the label to display, such as *Investor enquiries*, *Registered office*, or *Contact us*.

- [ ] **Privacy contact:** provide the privacy or data-protection contact if required by the approved legal design.

  

Do not publish personal contact details unless their use has been explicitly approved.

  

### 5. About description
---
  

- [ ] **Provide a short company/entity description.** Request final, publication-approved wording rather than drafting from unverified corporate sources.

- [ ] **Confirm the desired length and placement.** For example, a short homepage paragraph and an optional longer About section.

- [ ] **Identify mandatory legal or regulatory wording.** Confirm disclaimers, issuer status, jurisdiction, company registration details, and required risk notices.

- [ ] **Name the approver.** Legal/Compliance must approve the final text before production publication.

  

### 6. Website structure and visual design
---
  

- [ ] **Confirm the required tabs or sections.** Suggested sections are *Home*, *Information Memorandum and Transaction Terms*, *Announcements*, *Financial Reports*, *Corporate Documents*, *About*, and *Contact*.

- [ ] **For each section, describe its purpose and content owner.** This prevents empty, duplicate, or unowned sections.

- [ ] **Confirm whether sections should be separate pages or areas of one page.** Also confirm navigation order and mobile behavior.

- [ ] **Provide the preferred colour scheme.** Request approved primary, secondary, background, text, link, hover, and focus colours, ideally as HEX or RGB values.

- [ ] **Provide approved brand assets.** Request logos in suitable web formats, favicon, brand guidelines, fonts and font licences, imagery, and rules for clear space and minimum logo size.

- [ ] **Confirm accessibility requirements.** Record the target standard, normally WCAG 2.2 AA unless the organisation approves another standard.

- [ ] **Confirm search, filtering, sorting, and document grouping needs.** Specify expected behavior when no documents are available or the API is unavailable.

  

### 7. Documents and publication rules
---
  

- [ ] **List all required document categories.** Map each public section to a stable metadata category used by Storage, the API, and the frontend.

- [ ] **Provide sample and launch documents.** Files must be final PDFs approved for public release; samples must be clearly identified and removed before go-live if not publishable.

- [ ] **Confirm required document details.** Agree display name, description, publication date, category, language, ordering, and whether older versions remain public.

- [ ] **Define approval and publication responsibilities.** Record who submits, approves, uploads, verifies, withdraws, and replaces a document.

- [ ] **Define retention and withdrawal rules.** Include emergency withdrawal, correction, replacement, and evidence requirements.

- [ ] **Confirm accepted file types and size limits.** Update and test the API, publishing workflow, security controls, and user interface if these differ from the current PDF-focused process.

  

### 8. Footer, links, privacy, and analytics
---
  

- [ ] **Provide required footer content.** Confirm copyright wording, legal entity details, registration number, registered office, and year behavior.

- [ ] **Provide approved external links.** Examples include the corporate website, stock exchange, regulator, privacy notice, accessibility statement, and legal notice.

- [ ] **Confirm privacy and cookie requirements.** Determine whether the proposed site functionality requires a privacy notice or consent mechanism.

- [ ] **Confirm analytics requirements.** Record the approved platform, data collected, retention, consent model, access, and whether analytics are prohibited.

- [ ] **Confirm social media requirements.** Only include accounts and icons explicitly approved by the client.

  

**End of client questionnaire.** Return the completed answers and supplied assets to the project team. Technical ownership, internal security decisions, requirements validation, and approval gates are handled in Part B.

  

---

  

# Part B — Internal step-by-step website build procedure

  

This part begins only after Part A has been returned and approved. Complete the steps in order unless an approved project plan explicitly identifies safe parallel activities. Each exit gate is a prerequisite for the next dependent step.

  

## Step 1 — Approve requirements, scope, and governance
---
  

- [ ] **Appoint all owners.** Include business, Legal/Compliance, application, platform, security, DNS, content publication, and operations; document decision and escalation authority.

- [ ] **Convert the client answers into requirements.** Create a controlled requirements baseline containing the approved title, domain, sitemap, content, branding, document categories, legal requirements, accessibility target, service targets, and launch date.

- [ ] **Create a requirements traceability matrix.** Give every requirement an identifier and map it to its owner, implementation task, test, approval, and evidence location.

- [ ] **Approve scope and deadlines.** Record regulatory dates, dependencies, inclusions, exclusions, assumptions, constraints, and measurable acceptance criteria.

- [ ] **Approve the document governance model.** Define categories, metadata, approval evidence, audit, retention, withdrawal, replacement, and emergency publication.

- [ ] **Approve non-functional requirements.** Include privacy, cookies, analytics, accessibility, records management, availability, recovery, and threat review.

- [ ] **Approve the architecture.** Confirm whether the new website follows the Front Door, Static Web Apps, Function App, and private Blob Storage pattern or requires an architecture decision for any variation.

- [ ] **Create project control records.** Maintain risks, assumptions, issues, dependencies, architecture decisions, and changes with owners and dates.

- [ ] **Agree release and handover authority.** Identify who can approve deployment, rollback, go-live, risk acceptance, and transfer to operations.

  

### Internal technical, security, and operational decisions
---
  

- [ ] **Confirm the Azure environment.** Record the tenant, subscription, region, naming standard, mandatory tags, cost centre, and budget owner. Do not infer these values from another issuer's environment.

- [ ] **Confirm repository governance.** Record the GitHub organisation, repository administrators, protected branches, CODEOWNERS, required reviewers, and release approvers.

- [ ] **Confirm security requirements.** Cover data classification, WAF, identity, network restrictions, vulnerability management, logging, alerting, penetration testing, and access reviews.

- [ ] **Confirm service targets.** Record expected availability, support hours, recovery time objective, recovery point objective, and incident severity model.

- [ ] **Name operational owners.** Identify application, cloud platform, security, DNS, content publication, and incident-management owners.

  

### Internal requirements approval gate
---
  

- [ ] All client questionnaire answers are complete or have an owner and due date.

- [ ] Legal/Compliance has approved public wording, disclosures, document categories, and publication controls.

- [ ] The sitemap, visual direction, accessibility target, domain, and contact details have documented approval.

- [ ] Technical, security, operational, and delivery requirements have named owners.

- [ ] Scope, assumptions, exclusions, dependencies, acceptance criteria, and go-live date are formally approved.

  

**Required outputs:** approved requirements baseline, traceability matrix, architecture/design decision, project plan, responsibility matrix, risk register, acceptance criteria, and delivery/change records.

  

**Exit:** scope, requirements, architecture, ownership, risks, acceptance criteria, and delivery plan are approved.

  

## Step 2 — Purchase/register the domain and plan DNS
---
  

Start domain work early because availability, client approval, registrar processing, validation, and propagation can affect the launch date.

  

- [ ] **Check domain availability and ownership.** Confirm the requested domain is available or verify the existing registrant, registrar, expiry date, status, and administrative ownership.

- [ ] **Obtain registration approval.** Confirm the legal registrant, approved domain spelling, registration period, cost centre, renewal period, renewal owner, and authorised approver.

- [ ] **Submit the purchase/registration request.** Use the corporate L2/L3 and MarkMonitor process where required. Do not purchase a corporate domain through a personal or unapproved registrar account.

- [ ] **Secure the registration.** Enable the approved registrar lock, role-based access, multifactor authentication, renewal controls, and change notifications where supported.

- [ ] **Select the authoritative DNS service.** Record the nameservers, DNS-zone owner, approvers, operators, and whether DNS remains in MarkMonitor or is delegated to an approved Azure DNS zone.

- [ ] **Design the DNS records.** Define the production hostname, optional `www` behavior, Front Door validation record, Front Door routing record, TTLs, mail-related impact, and any test hostname.

- [ ] **Reserve time for certificate validation.** Identify the Azure Front Door custom-domain validation records and managed-certificate dependencies that will be created later.

- [ ] **Prepare the cutover and rollback plan.** Record current values if the domain already exists, proposed values, low-TTL timing, validation method, propagation expectations, rollback values, and operator.

- [ ] **Retain domain evidence.** Store the request, approval, registration confirmation, registrar details, renewal ownership, and DNS plan in the controlled records system.

  

**Important:** purchasing/registering the domain is completed in this step. Pointing the live domain to Azure is completed only after the application passes testing in Step 10.

  

**Exit:** the approved domain is registered and protected, renewal ownership is recorded, and the DNS/cutover plan is ready.

  

## Step 3 — Create and secure the GitHub repository
---
  

- [ ] **Create an issuer-specific repository.** Use the approved GitHub organisation, visibility, naming convention, owners, and data classification.

- [ ] **Copy only the approved solution pattern.** Bring across the application, API, workflow, publishing skill, and documentation needed for the new service.

- [ ] **Replace issuer-specific content and configuration.** Update company, domain, contacts, branding, legal text, Azure names, Storage target, Front Door values, Function name, and external links.

- [ ] **Perform and evidence a sanitisation search.** Search source, history intended for migration, configuration, workflow files, documentation, and assets for previous issuer values and secrets.

- [ ] **Create the repository structure.** Include the frontend, Function API, deployment workflows, controlled publication tooling, documentation, tests, and configuration samples required by the approved design.

- [ ] **Configure repository controls.** Enable protected default branches, pull-request reviews, required status checks, CODEOWNERS, secret scanning, dependency alerts, minimal workflow permissions, and protected environment approvals.

- [ ] **Configure access using corporate groups.** Separate repository administration, development, review, release approval, and read access according to the approved segregation-of-duties model.

- [ ] **Create delivery environments and secrets.** Create preview/test/production environments as required. Store only protected deployment secrets; never place secret values in source, documentation, issues, or pull-request comments.

- [ ] **Review ignored and generated files.** Ensure local settings, credentials, packages, build outputs, deployment archives, logs, and editor files cannot be committed accidentally.

- [ ] **Establish a clean baseline.** Run available linting/tests, review dependency versions, and record the initial commit or release used to start the new implementation.

  

**Exit:** no previous issuer data remains, source review controls operate, and no credential is committed.

  

## Step 4 — Design the Azure environment and resource inventory
---
  

Before provisioning, confirm the target tenant, management group, subscription, region, resource group, naming standard, tags, cost centre, data classification, policy requirements, support model, and whether separate non-production and production environments are required.

  

Create an approved resource design and naming sheet for every resource below. A resource marked **conditional** may be omitted only when the architecture/security owner records why it is not required.

  

| Azure resource or configuration item | Requirement | Purpose |
| --- | --- | --- |
| Subscription and management-group placement | Required | Billing, policy, ownership, and governance boundary |
| Resource group | Required per approved environment design | Lifecycle, access, tags, locks, and cost grouping |
| Azure Front Door profile | Required | Public global edge and TLS entry point |
| Azure Front Door endpoint | Required | Azure-provided edge hostname |
| Front Door origin groups and origins | Required | Connect Front Door to the website and API origins |
| Front Door routes and rule sets | Required | Route website paths to the frontend and `/api/*` to the API |
| Front Door WAF policy and security-policy association | Required | Managed/custom request filtering and edge protection |
| Front Door custom domain and managed certificate | Required | Approved public hostname and HTTPS certificate |
| Azure DNS public zone | Conditional | Hosts authoritative public DNS only when the approved domain design delegates DNS to Azure rather than retaining it in MarkMonitor |
| Azure Static Web App | Required | Hosts the static HTML, CSS, JavaScript, and assets |
| Function App | Required | Lists and streams approved public documents |
| App Service plan | Required for the selected Function hosting design | Provides Function compute, scale, and network capabilities |
| Function managed identity | Required | Authenticates to Storage without embedded credentials |
| Storage account | Required | Stores document objects and metadata |
| Private Blob container | Required | Holds approved and unapproved publication content privately |
| Key Vault | Conditional | Stores platform secrets/certificates required by the approved design |
| Virtual network | Required by the current private-network pattern | Network boundary for integration and private endpoints |
| Function integration subnet | Required when VNet integration is used | Provides the Function's outbound private-network path |
| Private-endpoint subnet | Required when private endpoints are used | Hosts private endpoints without mixing delegated workloads |
| Network security group | Required by the current network pattern | Controls permitted subnet/NIC traffic |
| Route table | Required by the current network pattern | Controls subnet routes and approved next hops |
| Private endpoints | Required for every service made private | Private connectivity to Storage, Key Vault, or other approved services; confirm each target rather than assuming a fixed count |
| Private-endpoint network interfaces | Automatically created with private endpoints | Hold private IP configurations and require inventory/diagnostics |
| Private DNS zones, links, and records | Required with private endpoints | Resolve service hostnames to private IP addresses |
| Network Watcher | Required where supported by platform policy | Network diagnostics and connection troubleshooting |
| Log Analytics workspace or approved diagnostic destination | Required | Central retention and querying of resource logs |
| Application Insights | Required unless an approved equivalent is used | Function request, failure, dependency, and performance telemetry |
| Diagnostic settings | Required on supported resources | Send platform, access, WAF, and audit logs to the approved destination |
| Alert rules | Required | Detect availability, security, certificate, dependency, and deployment problems |
| Action Group | Required | Routes alerts to owned operational recipients |
| Budgets and cost alerts | Required | Detect unexpected consumption and establish cost ownership |
| Resource locks and recovery controls | Required according to policy | Reduce accidental deletion and support recovery objectives |
| Azure RBAC group assignments | Required | Provide least-privilege administrative, operational, deployment, read, and publication access |

  

- [ ] **Choose environment separation.** Record which resources are shared or duplicated for development, test, preview, and production, including how data and credentials remain separated.

- [ ] **Create the network and data-flow design.** Document public routes, origin restrictions, Function-to-Storage connectivity, DNS resolution, trust boundaries, ports, identities, and logging paths.

- [ ] **Define capacity and resilience.** Select regions, SKUs, scaling, Storage redundancy, retention, soft delete, versioning, lifecycle, recovery objectives, and any regional recovery design.

- [ ] **Define ownership and access.** Map corporate groups and managed identities to the narrowest practical Azure roles and scopes.

- [ ] **Review estimated cost and policy compliance.** Confirm budget ownership, permitted regions/SKUs, mandatory tags, policy exceptions, and security approval before deployment.

  

**Exit:** the resource inventory, architecture, network design, naming, access model, resilience design, and estimated cost are approved.

  

## Step 5 — Provision and record the Azure resources
---
  

Provision through approved IaC where possible:

  

- [ ] **Prepare and review IaC.** Create the authoritative templates/modules, parameter files, state/storage arrangement, deployment identity, and plan output. Obtain platform and security approval before applying it.

- [ ] **Create the resource group and governance controls.** Apply approved names, tags, policy assignments, role assignments, budgets, and deletion locks.

- [ ] **Create networking.** Provision the virtual network, integration and private-endpoint subnets, NSGs, route tables, required peerings, and Network Watcher configuration.

- [ ] **Create the data layer.** Provision the Storage account and private Blob container; disable anonymous Blob access and configure firewall, private access, redundancy, versioning, soft delete, retention, lifecycle, diagnostics, and recovery controls.

- [ ] **Create Key Vault if required.** Configure RBAC, network restrictions, purge protection, diagnostics, and approved consumers; never substitute source-controlled settings for secret management.

- [ ] **Create private endpoints and DNS.** Create each approved private endpoint and NIC, approve its connection, link the correct private DNS zone, and verify records from the intended network path.

- [ ] **Create the Function platform.** Provision the App Service plan, Function App, supported Node.js runtime, managed identity, VNet integration, inbound restrictions, health/scale behavior, diagnostics, and Application Insights or approved equivalent.

- [ ] **Create the Static Web App.** Record its plan, region, default hostname, deployment-token rotation owner, diagnostics, Front Door integration, and intended origin-access restrictions.

- [ ] **Create Front Door and WAF.** Provision the profile, endpoint, origin groups, origins, health probes, website/API routes, rule sets, WAF policy, and security-policy association. The custom production domain can remain uncut-over until Step 10.

- [ ] **Create monitoring and alerting.** Provision the approved log destination, diagnostic settings, alert rules, dashboards/workbooks, retention, and Action Group; test notification delivery.

- [ ] **Apply RBAC.** Grant group-based administration/operations roles and assign the Function managed identity Blob read/list access at the narrowest practical scope. Grant publisher groups only approved Blob data-plane permissions.

- [ ] **Apply resilience and cost controls.** Implement the approved recovery configuration, locks, quotas, budgets, and cost alerts.

- [ ] **Create and review the resource register.** Capture every resource name, ID, type, region, SKU, owner, environment, dependency, identity, private IP/DNS mapping, access assignment, diagnostics destination, recovery setting, and latest verification date.

  

Create a complete resource register based on [Infrastructure Configuration Reference](Infrastructure-Configuration-Reference.md). Never carry Esla production values into another issuer environment.

  

**Exit:** resources, identity, network/DNS, diagnostics, access, and recovery configuration are validated and recorded.

  

## Step 6 — Configure Storage, identity, and the document API
---
  

- [ ] **Implement the approved container and metadata model.** Define category, approval status, publication date, description, display name, and any language/version fields consistently.

- [ ] **Grant least-privilege API access.** Enable the Function managed identity and grant only the Blob read/list permissions required by the design.

- [ ] **Configure the API runtime.** Set the supported Node.js version, Storage account/container settings, allowed file behavior, logging, and production runtime settings.

- [ ] **Adapt the publishing workflow.** Change the account/container and category validation, then review authentication, no-overwrite behavior, metadata, and failure handling.

- [ ] **Deploy a versioned package.** Follow [Azure Function Deployment](Azure-Function-Deployment.md), retain the artifact and logs, and verify the deployed version.

- [ ] **Test positive and negative API paths.** Cover listing, approved download, unapproved and missing files, malformed identifiers, unsupported types, large files, identity failure, and network failure.

- [ ] **Verify the security boundary.** Confirm no account key, SAS token, connection string, anonymous Blob endpoint, internal error detail, or unrestricted origin is exposed publicly.

  

**Exit:** the API securely lists/streams approved content through managed identity and passes security tests.

  

## Step 7 — Build and configure the frontend
---
  

- [ ] **Apply only approved client content.** Implement the title, description, structure, branding, contacts, legal wording, footer, links, and document categories from the signed-off requirements.

- [ ] **Configure origin restrictions.** Replace copied Front Door IDs and hosts with the new environment's verified values.

- [ ] **Use the intended API route.** Ensure browser requests use same-origin `/api/documents` through Front Door rather than a Storage or Function origin URL.

- [ ] **Remove placeholders and obsolete sections.** Delete sample documents, copied issuer text, unused categories, test links, comments, metadata, and assets.

- [ ] **Implement all user states.** Review loading, search, ordering, filtering, empty categories, no results, API errors, missing files, and clear recovery guidance.

- [ ] **Test responsive and browser behavior.** Cover agreed desktop/mobile widths, supported browsers, orientation, zoom, long titles, long filenames, and slow connections.

- [ ] **Test accessibility.** Verify semantic structure, keyboard use, visible focus, contrast, link purpose, screen readers, reduced motion, reflow, and the agreed WCAG target.

- [ ] **Obtain content and design approval.** Retain approval for every public statement, contact detail, logo, colour, image, font, external link, and legal notice.

  

**Exit:** the preview contains only approved issuer content and passes agreed functional/accessibility criteria.

  

## Step 8 — Configure deployment and edge routing
---
  

- [ ] **Connect frontend delivery.** Link Static Web Apps to the approved repository and reviewed workflow with minimal permissions.

- [ ] **Protect deployment credentials.** Store the deployment token under the required protected secret/environment and document rotation ownership without recording the value.

- [ ] **Test preview and production deployments.** Verify pull-request creation/update/closure behavior, production branch deployment, approvals, failure reporting, and retained logs.

- [ ] **Keep deployment units separate.** Confirm the frontend workflow cannot accidentally package or deploy the Function App.

- [ ] **Configure Front Door routes.** Send website paths to Static Web Apps and `/api/*` to the Function App with correct route precedence.

- [ ] **Harden edge behavior.** Review host headers, probes, HTTPS redirect, TLS, compression, caching, security headers, request limits, WAF, and diagnostics.

- [ ] **Add the custom domain without production cutover.** Add the hostname to Front Door, create the requested validation record through the approved DNS process, and confirm managed-certificate issuance. Do not change the live routing record until Step 10.

- [ ] **Prevent origin bypass.** Apply the approved Front Door restrictions to Static Web Apps and the Function origin, then test that direct-origin access is rejected where required.

  

**Exit:** preview/test deployment works, Front Door routes both origins correctly, the custom domain and certificate are validated, and production cutover remains controlled.

  

## Step 9 — Prepare and publish approved launch content
---
  

- [ ] **Obtain final approved files and metadata.** Match every file to its approval, public description, publication date, category, display name, and owner.

- [ ] **Perform pre-publication checks.** Validate filenames, content, redaction, PDF behavior, malware-scan status, metadata, accessibility expectations, category, and duplicate/version handling.

- [ ] **Publish through the controlled workflow.** Follow [Uploading Documents](Uploading-Documents.md), updated and re-approved for the new issuer's Storage target.

- [ ] **Verify every publication publicly.** Check listing, name, description, date, category, ordering, download, content, headers, and behavior through the production edge.

- [ ] **Retain publication evidence.** Record approval, source checksum, uploader, time, target, metadata, verification, and any exceptions without storing credentials.

- [ ] **Exercise withdrawal and replacement.** Demonstrate the authorised process, expected public/API result, cache behavior, evidence, and restoration or corrected-publication route.

  

**Exit:** only intended approved documents are public and publication/withdrawal controls are demonstrated.

  

## Step 10 — Test, accept, and go live
---
  

- [ ] **Apply the go-live change freeze.** Permit only approved critical fixes and record a healthy pre-release baseline for all service components.

- [ ] **Complete formal acceptance.** Execute [Testing and Acceptance Checklist](Testing-and-Acceptance-Checklist.md), link evidence, and resolve or formally accept every exception.

- [ ] **Confirm operational readiness.** Test alerts, Action Group recipients, on-call routes, status communications, dashboards, runbooks, credentials, and rollback artifacts.

- [ ] **Collect formal approvals.** Obtain business, Legal/Compliance, application, platform, security, operations, change, and final go-live authorization.

- [ ] **Execute the production DNS cutover.** Through L2/L3 and MarkMonitor or the approved DNS operator, point the production hostname to Front Door using the approved record and TTL. Do not expose origin hostnames as the public target.

- [ ] **Validate DNS and TLS externally.** Verify authoritative and recursive resolution from multiple resolvers/networks, Front Door custom-domain association, certificate chain/hostname/expiry, HTTPS redirect, `www` behavior, website routes, and `/api/*` routes.

- [ ] **Monitor the observation period.** Watch Front Door/WAF, origins, Function, Storage, DNS/TLS, logs, alerts, user journeys, document access, and deployments.

- [ ] **Close the release record.** Capture versions, artifacts, checksums, timestamps, implementers, approvers, evidence, incidents, rollback status, and accepted risks.

  

**Exit:** acceptance signed, production stable, monitoring active, and rollback ready.

  

## Step 11 — Hand over the service and close the project
---
  

Provide the support team with:

  

- [ ] **Source and release information.** Provide the repository, protected branches, deployment units, environments, artifact locations, release procedures, and rollback procedures.

- [ ] **Architecture and configuration.** Provide approved diagrams, trust boundaries, data flows, complete resource register, configuration authority, dependencies, and known constraints.

- [ ] **Monitoring and support.** Provide dashboards/log queries, alert catalogue, tested Action Group, support hours, escalation routes, service targets, and supplier references.

- [ ] **Identity and access.** Provide the access-request, approval, removal, emergency-access, credential-rotation, and periodic-review processes with named system owners.

- [ ] **Operational procedures.** Provide publication, withdrawal, replacement, frontend and Function deployment, rollback, incident, recovery, maintenance, and security-event procedures.

- [ ] **Domain and resilience ownership.** Record DNS registrar and certificate owners, renewal process, recovery objectives, backup/restore behavior, recovery-test schedule, and known risks.

- [ ] **Evidence and training.** Deliver acceptance, release, go-live, recovery-test, access-review, and training evidence in the approved records system.

  

- [ ] **Run supervised exercises.** Require the receiving team to demonstrate publication/withdrawal, release/rollback, alert response, incident handling, access requests, and recovery procedures.

- [ ] **Obtain formal service acceptance.** Record the receiving owner, acceptance date, residual risks, and all open actions with owners and due dates.

  

**Exit:** receiving owner formally accepts the service and all open actions have owners and due dates.

  

## ✅ Completion gate
---
  

- [ ] Client questionnaire and approved requirements baseline complete.

- [ ] Requirements traceability matrix demonstrates implementation and test coverage.

- [ ] Domain registration, DNS ownership, renewal, cutover, and rollback records complete.

- [ ] GitHub repository, access, branch protection, environments, workflows, and secret controls complete.

- [ ] Requirements, architecture, ownership, and regulatory controls approved.

- [ ] Repository contains no previous issuer values or secrets.

- [ ] Every required/approved Azure resource is provisioned and appears in the controlled resource register.

- [ ] Azure network, identity, DNS, monitoring, cost, access, and recovery configuration is verified.

- [ ] Front Door/WAF, origins, Function, and private Storage verified.

- [ ] Frontend and Function independently deployable and reversible.

- [ ] Publication and withdrawal demonstrated with approved content.

- [ ] Acceptance complete with risks formally accepted.

- [ ] Operations handover and exercises accepted.

- [ ] All project actions are closed or transferred with an owner and due date.