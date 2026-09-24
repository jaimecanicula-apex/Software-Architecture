## 🎯 Purpose
---
  

Use this checklist for go-live, a major release or infrastructure change, recovery testing, and periodic service reacceptance. Mark items **Pass**, **Fail**, **Not applicable**, or **Risk accepted**, and link evidence. A checked box without evidence is not acceptance.

[[_TOC_]]


## 🪪 Release identification
---
  

```text

Issuer / service:

Environment and public URL:

Change / release ID:

Git commit and workflow run:

Function package / deployment ID:

Infrastructure version / change ID:

Test date and window:

Testers and approvers:

Evidence location:

```

  

## 📄 Business and content
---
  

- [ ] Issuer identity, company overview, registered office, email, links, footer, and branding are correct and approved.

- [ ] Legal, regulatory, privacy, cookie, accessibility, copyright, and retention requirements are satisfied.

- [ ] Required categories are present; no sample, draft, internal, or previous-issuer content remains.

- [ ] Every visible document, title, date, category, and announcement description matches approval.

- [ ] No confidential content, PDF metadata, draft page, or unintended file is public.

- [ ] Publication and withdrawal evidence is complete.

  

## 🌐 Functional website
---
  

- [ ] Production domain loads over HTTPS and HTTP redirects according to policy.

- [ ] Page title, header, navigation, anchors, sections, footer, email, and external links work.

- [ ] Search returns expected matches and a clear empty result.

- [ ] Categories render correctly and announcements have the expected ordering.

- [ ] Documents open through the public API in a safe new browser context.

- [ ] Refresh and direct anchors work; browser console/network show no unexpected errors.

- [ ] API-unavailable and empty-content states are understandable.

  

## 🔌 Document API
---
  

- [ ] `GET /api/documents` returns `200` and a valid `documents` array through Front Door.

- [ ] Only approved `.pdf` and `.txt` files are listed.

- [ ] Category, display name, size, modified time, publication date, and description behavior match the contract.

- [ ] Approved download returns `200` with expected content type, length, and inline disposition.

- [ ] Missing and unapproved documents return `404` without disclosing approval state.

- [ ] Unsupported/traversal identifiers return `400`.

- [ ] Unexpected failures return generic responses without secrets or internal details.

- [ ] API responses are not stale after an approved publication change.

  

## 📚 Production document sample
---
  

For every document when feasible, or a formally approved representative sample:

  

- [ ] Public filename/display name is unique and suitable.

- [ ] Category, date, and description are correct.

- [ ] File opens and is complete, readable, and uncorrupted.

- [ ] Content and hash where required match the approved original.

- [ ] No confidential metadata, comments, attachments, or draft pages are present.

- [ ] URL uses the expected production domain and API path.

  

## 📱 Browser, responsive, and accessibility
---
  

- [ ] Supported Chrome and Edge desktop versions tested.

- [ ] Firefox and Safari tested where included in the support matrix.

- [ ] iOS, Android, tablet, narrow desktop, and 200% zoom layouts remain operable.

- [ ] Text and controls do not overlap, truncate incorrectly, or require unintended horizontal scrolling.

- [ ] Document controls remain usable with touch and pointer input.

- [ ] Page title, language, landmarks, labels, heading hierarchy, and link text are meaningful.

- [ ] Keyboard-only navigation, focus order, visible focus, and skip/primary navigation work.

- [ ] Images have appropriate alternatives and decorative images are handled correctly.

- [ ] Colour contrast, reflow, text spacing, reduced motion, and error states meet the approved standard.

- [ ] Automated scan has no unaccepted critical findings.

- [ ] Manual screen-reader review is complete when required.

  

## ⚡ Performance and resilience
---
  

- [ ] Page and API meet agreed performance targets under normal load.

- [ ] Static assets are compressed/cached appropriately without stale API metadata.

- [ ] Representative PDF downloads complete within target.

- [ ] Front Door probes report healthy origins.

- [ ] Synthetic website, API, and document monitoring succeeds.

- [ ] Failure modes and recovery objectives were tested or evidenced.

- [ ] Storage redundancy/recovery and rollback assumptions match the service record.

  

## 🛡️ Front Door, WAF, DNS, and TLS
---
  

- [ ] Domain resolves to the approved Front Door endpoint from multiple resolvers.

- [ ] Custom-domain validation and trusted certificate are healthy; expiry/renewal owner is recorded.

- [ ] Website paths reach Static Web Apps and `/api/*` reaches the Function App.

- [ ] Origin host headers, priorities, weights, and health probes match the approved design.

- [ ] Direct origin access is restricted according to architecture.

- [ ] Static Web Apps validates the current Front Door ID and forwarded hosts.

- [ ] WAF is attached in approved mode with current managed/custom rules.

- [ ] Expected traffic passes and approved malicious test patterns are handled according to policy.

- [ ] Front Door access, origin-health, and WAF diagnostics reach the approved destination.

  

## ⚙️ Function, Storage, identity, and network
---
  

- [ ] Function runtime is supported and required settings/run-from-package are present.

- [ ] Active package is identifiable and contains the expected release.

- [ ] Managed identity is enabled with least-privilege Blob read access.

- [ ] No storage key, SAS token, or connection string exists in source or browser-visible responses.

- [ ] Container is private and publisher access is limited to approved groups.

- [ ] Function and publishing workflow use the same approved account/container.

- [ ] Storage soft delete, versioning, retention, lifecycle, recovery, and diagnostics match policy.

- [ ] Every private endpoint maps to the recorded target, NIC, subnet, IP, and DNS zone.

- [ ] Function-to-Storage DNS, route, NSG, firewall, and private endpoint behavior works.

- [ ] Existing Blobs are protected from accidental overwrite by the publishing workflow.

  

## 🚀 Delivery and rollback
---
  

- [ ] Pull-request preview and required reviews completed.

- [ ] Merge/push to `main` deployed the approved frontend commit.

- [ ] Function used approved ZipDeploy and package evidence is retained.

- [ ] Protected deployment credentials were not exposed.

- [ ] Previous frontend revision, Function package, infrastructure state, and DNS values are identifiable.

- [ ] Frontend and Function rollback were tested or demonstrated.

- [ ] Publication withdrawal/replacement control was tested or demonstrated.

- [ ] Rollback verification and monitoring evidence is retained.

  

## 📊 Monitoring and operations
---
  

- [ ] Website/API availability, origin health, Function, Storage, WAF, deployment, certificate, and high-impact change alerts exist.

- [ ] Alert severity, threshold, owner, Action Group, escalation, and runbook are recorded.

- [ ] Action Group delivery and escalation were tested.

- [ ] Dashboard/log access, support hours, and incident contacts are current.

- [ ] Azure diagnostics and retention meet policy.

- [ ] Access recertification, resource locks, restore testing, and maintenance ownership are current.

  

## 👥 Ownership and control
---
  

- [ ] Business, Legal/Compliance, application, platform, security, operations, DNS, and release owners are named in the controlled system.

- [ ] Domain ownership and L2/L3 MarkMonitor request path are current.

- [ ] Azure/GitHub/publisher permissions follow least privilege and segregation of duties.

- [ ] Recovery objectives, known constraints, exceptions, and residual risks have owners.

- [ ] Architecture and configuration register match production and have a review date.

  

## ✍️ Acceptance decision
---
  

Record every unresolved item with severity, owner, due date, workaround, compensating control, and formal risk approver.

  

```text

Business acceptance:

Legal / Compliance acceptance:

Application acceptance:

Cloud platform acceptance:

Security acceptance:

Operations acceptance:

Residual risks / exceptions:

Go-live or continued-service decision:

Decision owner and date:

```