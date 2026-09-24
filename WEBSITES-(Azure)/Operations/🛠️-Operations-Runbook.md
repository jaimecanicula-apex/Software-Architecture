## 🎯 Purpose

  

This runbook defines routine operation, monitoring, maintenance, access review, and service handover. Procedures for deployment, publication, incidents, and configuration are maintained in their dedicated guides and are not repeated here.

[[_TOC_]]

## 🌐 Service summary

  

| Service | Operational responsibility |

| --- | --- |

| Azure Front Door and WAF | Public routing, TLS, origin health, and edge security |

| Azure Static Web Apps | Frontend hosting and preview/production deployments |

| Azure Function App | Approved-document listing and streaming |

| Azure Blob Storage | Private publication storage and metadata |

| GitHub Actions | Frontend delivery status |

| Azure monitoring and Action Group | Detection, notification, and escalation |

| MarkMonitor through L2/L3 | Domain and DNS lifecycle |

  

Production service: `https://eslasa.lu`

  

## 👥 Responsibility model

  

| Area | Accountable function |

| --- | --- |

| Content accuracy, approval, retention, and withdrawal | Legal / Compliance / Investor Relations |

| Application source, frontend, and Function releases | Application team |

| Azure configuration, identity, network, and recovery | Cloud platform team |

| WAF policy and security events | Security team / Security operations |

| Domain and DNS | L2/L3 through MarkMonitor |

| Monitoring, incident coordination, and service reporting | Operations / Security operations |

  

Maintain named groups, on-call details, support hours, escalation timing, and supplier contacts in the controlled service-management system.

  

## 📊 Monitoring baseline

  

Every production alert needs severity, owner, Action Group, escalation path, and runbook. Monitor at least:

  

- Public website and `/api/documents` availability.

- Front Door origin health, request failures, and latency.

- WAF blocks, policy changes, and false-positive trends.

- Function failures, latency, restarts, throttling, and Storage dependency errors.

- Storage availability, authorization failures, capacity, and transactions.

- Static Web App production deployment failures.

- Certificate validation/expiry and domain state.

- High-impact Azure Activity Log changes, especially deletion, identity, network, and security changes.

  

The exact signals, thresholds, retention, and recipients belong in [Infrastructure Configuration Reference](Infrastructure-Configuration-Reference.md).

  

## 🗓️ Operating schedule

  

### Daily

  

- Confirm synthetic website, API, and representative-document checks succeed.

- Review active availability, origin-health, Function, Storage, WAF, and certificate alerts.

- Review failed production deployments and unresolved incidents.

- Prioritise urgent regulatory publication requests and failed publications.

  

### Weekly

  

- Review Front Door latency/origin trends and Function dependency failures.

- Review WAF blocks for attacks and false positives.

- Review Storage authorization failures and capacity growth.

- Review Action Group delivery failures and monitoring gaps.

- Confirm recent releases/publications have complete evidence.

- Triage dependency, secret-scanning, and repository security alerts.

  

### Monthly

  

- Review Azure cost, unexpected growth, runtime/dependency support, and certificate state.

- Review privileged, deployment, and publishing access changes.

- Review WAF exclusions/custom rules and approaching review dates.

- Review storage recovery, retention, lifecycle, and diagnostic ingestion.

- Reconcile documentation and the configuration register with production.

- Sample public documents against their approval records.

  

### Quarterly

  

- Complete formal access recertification.

- Test Action Group delivery and escalation.

- Exercise frontend and Function rollback.

- Validate private endpoint, NIC, route, NSG, and private DNS mappings.

- Review resource locks and accidental-deletion controls.

- Perform an approved restore test where applicable.

- Review domain contacts, recovery objectives, risks, and content withdrawal controls.

  

### Annually

  

- Conduct an end-to-end recovery exercise.

- Review architecture, threat assumptions, Azure SKUs, runtime support, and deprecated services.

- Reapprove public legal wording, registered office, contacts, branding, and accessibility.

- Confirm domain and certificate renewal arrangements.

- Reapprove support ownership, supplier contacts, and service acceptance.

  

## 🔁 Routine activities

  

| Activity | Authoritative procedure |

| --- | --- |

| Publish or withdraw a document | [Uploading Documents](Uploading-Documents.md) |

| Release frontend changes | [Website Deployment](Website-Deployment.md) |

| Release Function changes | [Azure Function Deployment](Azure-Function-Deployment.md) |

| Change infrastructure, WAF, identity, or DNS | [Change and Release Management](Change-and-Release-Management.md) |

| Diagnose production failure | [Incident and Troubleshooting Guide](Incident-and-Troubleshooting-Guide.md) |

| Perform major or periodic acceptance | [Testing and Acceptance Checklist](Testing-and-Acceptance-Checklist.md) |

  

## 🔑 Access management

  

- Use corporate identity groups and least privilege.

- Separate content approval from technical publishing where policy requires.

- Time-limit privileged elevation and record justification and approver.

- Review direct assignments, dormant access, service credentials, and publisher roles.

- Remove access promptly when responsibilities change.

- Never share accounts or deployment credentials.

- Record evidence of periodic recertification and exceptions.

  

## 🔧 Maintenance windows

  

Use a controlled window for runtime, Front Door/WAF, DNS, network/private endpoint, Storage policy, identity, and availability-affecting changes. Record:

  

- Owner, approver, implementer, start/end time, and stakeholder communications.

- Expected impact, dependencies, health baseline, and freeze scope.

- Verification plan, observation period, rollback trigger, and rollback operator.

- Final outcome, monitoring state, and evidence location.

  

## 📈 Service review

  

Review availability and latency, incidents by severity/root cause, failed changes, publication errors, security events, WAF tuning, capacity/cost, unsupported dependencies, access exceptions, monitoring gaps, recovery tests, open risks, and overdue actions. Assign every action an owner and due date.

  

## 🤝 Handover checklist

  

- [ ] Architecture and complete resource register reviewed.

- [ ] Named support and escalation groups recorded.

- [ ] Dashboard, logs, GitHub, and Azure access granted.

- [ ] Alerts and Action Group delivery tested.

- [ ] Publication and withdrawal process demonstrated.

- [ ] Frontend and Function release/rollback demonstrated.

- [ ] DNS and MarkMonitor request path understood.

- [ ] Private networking and recovery dependencies reviewed.

- [ ] Incident simulation completed.

- [ ] Known risks and recovery objectives formally accepted.