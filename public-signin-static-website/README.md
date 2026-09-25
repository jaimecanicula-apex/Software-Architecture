# Public sign-in static website (Terraform)

> **Golden template candidate.** This folder is written to become an APEX golden template. See [../GOLDEN-TEMPLATES.md](../GOLDEN-TEMPLATES.md) for what still has to happen before it is published as one.

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
| Site folder | `app/` | `app-public-signin/` | `app-internal/` |

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
5. **Pipeline secrets:** store `static_web_app_deployment_token` as `AZURE_STATIC_WEB_APPS_API_TOKEN_PUBLIC_SIGNIN`, and `staticwebapp_config_json` as `SWA_CONFIG_JSON`. The pipelines write the config into `app-public-signin/` before uploading.

## Recommended outside Terraform

- **Conditional Access for guests:** require MFA for guest accounts signing in to this app, and optionally restrict their locations.
- **Cross-tenant access settings:** decide whether to trust partner-tenant MFA or require MFA in APEX.
- **Access reviews:** periodically review the site's users group so stale guest access is removed.

## To verify in dev

These have not been tested against Azure yet (`terraform validate` passes):

- Sign-in through the Front Door host name. `allowedForwardedHosts` and the redirect URIs must match every host users see.
- A guest's first sign-in, after redeeming the invitation.
