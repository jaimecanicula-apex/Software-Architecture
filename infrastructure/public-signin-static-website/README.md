# Public sign-in static website (Terraform)

> **Golden template candidate.** This folder is written to become an APEX golden template. See [../../GOLDEN-TEMPLATES.md](../../GOLDEN-TEMPLATES.md) for what still has to happen before it is published as one.

Use this design when the site must be **reachable from the internet** by **external people**, but only **after they sign in with Entra ID** and only if they are **approved**. External users are invited as **B2B guests of the APEX tenant** and sign in with their own work or Microsoft account. Only members of the site's users group, or another approved group, get past sign-in.

```
External guest (anywhere on the internet)
   │  HTTPS
   ▼
Azure Front Door + WAF ──X-Azure-FDID──▶ Azure Static Web App (Standard)
                                          │  every page except /healthz.html:
                                          │  401 → /.auth/login/aad
                                          ▼
                              Microsoft Entra ID (APEX tenant)
                              app registration, assignment required,
                              approved users group (B2B guests)

Availability tests (5 regions) ──▶ /healthz.html (anonymous)
Front Door, WAF, tests ──▶ Log Analytics / App Insights ──▶ alerts, workbook dashboard
```

## The three designs side by side

| | Publicly accessible | **Public sign-in (this folder)** | Privately accessible |
| --- | --- | --- | --- |
| Audience | Anyone, anonymous | Approved external people | Internal APEX users |
| Entry | Front Door + WAF | Front Door + WAF | Private endpoint only |
| Sign-in | None | Entra ID (APEX tenant, B2B guests), assigned groups only | APEX Entra, assigned groups only |
| Availability tests | Internet, `/` | Internet, `/healthz.html` | In-VNet probe |
| Site folder | `content/publicly-accessible-static-website/` | `content/public-signin-static-website/` | `content/privately-accessible-static-website/` |

## What this folder adds to the public design

- **`modules/entra-app-auth`:** single-tenant app registration with redirect URIs for every public host (the Front Door endpoint and custom domains). *Assignment required* is on, and the secret rotates every 180 days.
- **`modules/entra-guest-access`:**
  - creates the site's users group, `grp-sps-<env>-<region>-001-site-users`
  - sends a B2B invitation to each address in `guest_emails`
  - adds each invited guest to that group
- **Static Web App settings:** `AZURE_CLIENT_ID` and `AZURE_CLIENT_SECRET`. The Standard SKU is enforced, because custom sign-in needs it.
- **`staticwebapp.config.json` template:**
  - an Entra identity provider scoped to the APEX tenant
  - every route requires `authenticated`, except the anonymous `/healthz.html`
  - a 401 redirects to sign-in
  - GitHub and Twitter login are disabled
  - the origin is locked to Front Door
  - CSP and `Cache-Control: private, no-store`
- **Availability tests** target `/healthz.html`, so they measure the site without needing an account.

## Design decisions

| Concern | Decision | Why | Trade-off |
| --- | --- | --- | --- |
| Region | `location`, required in every environment's `terraform.tfvars` (no default), validated against the 5 regions that offer Static Web Apps | Data residency and latency are choices per organisation and environment; a silent default could place an environment in the wrong region | Only westus2, centralus, eastus2, westeurope and eastasia. Changing it later recreates the Static Web App and the regional monitoring resources |
| Availability zones | No zone setting exists: Front Door and Static Web Apps content are global, and Azure manages zone placement for Log Analytics and Application Insights. The Terraform state storage is zone- and geo-redundant (GZRS) through `replication_type` in `bootstrap/` | Nothing in this design is pinned to one zone, so there is nothing to spread | No control over the platform's zone placement. An outage of the whole region still stops deployments and the monitoring workspace, though Front Door keeps serving cached pages |
| Audience | Approved external people, invited as Entra B2B guests of the tenant | Guests keep their own work or Microsoft accounts, so there are no passwords to manage, and access is one group membership | Guests live in our tenant, so someone must invite, review and remove them, and their home tenant's MFA may not be trusted without cross-tenant settings |
| Who gets in | *Assignment required* on the app; only the site's users group and `allowed_group_ids` | Entra itself refuses anyone not approved, before the site sees a request. Removing someone from the group removes their access | Every new person needs an invitation and a group change; there is no self sign-up |
| Sign-in | Static Web App built-in authentication with a single-tenant app registration; secret rotates every 180 days | The site stays build-free and one config file protects every route. Rotation limits the life of a leaked secret | A client secret, not a certificate or federated credential: it expires if the environment is not re-applied within about 210 days. Entra is the only login |
| Hosting | Static Web App, Standard in every environment | Custom Entra sign-in needs Standard, so even dev cannot use Free | Standard costs more than Free in every environment, including dev |
| Edge and WAF | Front Door with WAF, as in the public design (off in dev, Standard in qa, Premium in uat and prod) | The site is still on the internet, so it keeps rate limiting, geo blocking, managed rules and the origin lock | Same cost as the public design, with Front Door Premium as the largest line |
| Caching | `Cache-Control: private, no-store` on every page | Signed-in pages must never be cached at the edge or shown to another guest | No edge caching: every request goes to the Static Web App, which is slower for guests far away |
| Availability | Web tests from 5 regions on the anonymous `/healthz.html` | Tests need no account, which would otherwise have to be stored and rotated. They do not prove sign-in works | Tests stay green while sign-in is broken (expired secret, wrong redirect URI), so sign-in failures surface only through users |
| Governance | Mandatory tags, budget, delete lock in uat and prod, viewer and operator groups | Required for every golden template | The lock blocks legitimate teardown until removed through change control, and a budget only warns; it never stops spending |

## Cost estimate

Retail list prices in USD for West Europe from the Azure Retail Prices API, the data source of the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/), retrieved on 2026-09-27. A month is 730 hours. Taxes, discounts, reservations and currency conversion are not included; re-check in the calculator before committing a budget.

Fixed monthly cost per environment, with one availability test on `/healthz.html`:

| Item | Price used | dev | qa | uat | prod |
| --- | --- | --- | --- | --- | --- |
| Static Web App, Standard (needed for custom sign-in) | $9 per app | $9 | $9 | $9 | $9 |
| Front Door base fee | Standard $35; Premium $330 | off | $35 | $330 | $330 |
| Standard web test, 5 locations every 5 minutes | $0.000645 per run, 43,800 runs a month | $28.25 | $28.25 | $28.25 | $28.25 |
| Alerts | $0.15 to $0.50 per rule; activity log alerts free | about $1 | about $1 | about $1 | about $1 |
| Log Analytics | First 5 GB free, then $2.99 per GB | $0 | $0 | $0 | $0 |
| Entra ID guests (B2B) | Billed per monthly active user; the first 50,000 a month are free | $0 | $0 | $0 | $0 |
| **Fixed total** | | **about $38** | **about $73** | **about $368** | **about $368** |

Traffic adds Front Door requests ($0.009 Standard or $0.015 Premium per 10,000) and data out ($0.0825 per GB for the first 10 TB). Pages are never cached (`Cache-Control: private, no-store`), so every request also reaches the Static Web App; its first 100 GB of bandwidth is included. Each custom domain with `monitor = true` adds $28.25.

- **Front Door Premium is 90 % of the cost** in uat and prod.
- **uat budget is tight:** 400 against about $368 fixed; one monitored domain plus traffic reaches the forecast warning.

## Managing who gets in

| Way | How |
| --- | --- |
| A few named people | Add their emails to `guest_emails` and apply. Each receives the Microsoft invitation email; the `guest_invitation_links` output has the links in case the email is lost. |
| Many people or self-service | Leave `guest_emails` empty. The APEX identity team invites guests (for example through Entra entitlement management access packages) and adds them to the group in the `site_users_group_id` output. |
| An existing partner group | Put its object ID in `allowed_group_ids`. |

Removing someone from the group stops their next sign-in. Deleting the guest account in Entra removes them everywhere.

## First-time setup

1. Run `bootstrap/` for the state storage and fill in `environments/<env>/backend.hcl`.
2. In `environments/<env>/terraform.tfvars`, set:
   - `tenant_id` (APEX)
   - `subscription_id`
   - governance tags
   - `guest_emails` and/or `allowed_group_ids`
   - custom domains
   - alert recipients
   - viewer and operator groups
3. **Identity for `apply`:** besides Contributor and User Access Administrator on the subscription, the identity needs these Entra permissions:
   - create app registrations and groups
   - invite guests, via the Guest Inviter role or tenant settings that allow it
   
   If pipelines may not do that, set `create_entra_app = false` and manage the group outside Terraform.
4. Deploy:
   ```
   ./public-signin-static-website/scripts/tf.sh dev init
   ./public-signin-static-website/scripts/tf.sh dev plan
   ./public-signin-static-website/scripts/tf.sh dev apply
   ```
5. **Pipeline secrets:** store `static_web_app_deployment_token` as `AZURE_STATIC_WEB_APPS_API_TOKEN_PUBLIC_SIGNIN`, and `staticwebapp_config_json` as `SWA_CONFIG_JSON`. The pipelines write the config into `content/public-signin-static-website/` before uploading.

## Recommended outside Terraform

- **Conditional Access for guests:** require MFA for guest accounts signing in to this app, and optionally restrict their locations.
- **Cross-tenant access settings:** decide whether to trust partner-tenant MFA or require MFA in APEX.
- **Access reviews:** periodically review the site's users group so stale guest access is removed.

## To verify in dev

These have not been tested against Azure yet (`terraform validate` passes):

- Sign-in through the Front Door host name. `allowedForwardedHosts` and the redirect URIs must match every host users see.
- A guest's first sign-in, after redeeming the invitation.
