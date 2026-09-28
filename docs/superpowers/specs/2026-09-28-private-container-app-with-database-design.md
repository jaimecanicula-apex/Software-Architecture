# Privately accessible container app with database — design spec

Status: approved by user, ready for implementation planning
Date: 2026-09-28

## Intent

Add a fifth golden template: a containerised Python application for internal
users, with its own PostgreSQL database and Blob image storage, and its own
application-level username/password sign-in (in addition to the existing
Entra ID gate). It demonstrates the pattern for any future template that
needs a stateful backend, not just a stateless one.

**Who it's for:** teams that need a small internal line-of-business app with
its own login and simple CRUD, not just a passthrough to Entra-authenticated
users. **Success looks like:** `terraform validate` and `terraform test`
pass with mocked providers, the Python app's pytest suite passes, and the
template is a self-contained copy of the container-app pattern — nothing
references another template's files.

## Decisions carried from clarification

- **Two auth layers, not one.** Container Apps' built-in Entra sign-in stays
  in front (only assigned Entra groups get in at all — reuses
  `entra-app-auth`), and the Flask app adds its own username/password login
  on top, with roles (`admin` / `user`). This matches the existing template's
  network-privacy-first posture while satisfying the request for app-level
  credentials.
- **Database:** Azure Database for PostgreSQL Flexible Server, VNet-integrated
  (delegated subnet, no public network access).
- **CRUD domain:** a generic asset catalogue (name, category, description,
  one image) — keeps the example generic per `CLAUDE.md`'s "no client names"
  rule. Any user can view all assets; a user can edit/delete only their own;
  an admin can edit/delete anything and manage users.
- **Secrets:** Terraform generates the DB admin password, the app's session
  secret key, and the seed users' initial passwords with `random_password`,
  and writes them to a dedicated Key Vault (RBAC, private endpoint, public
  access off). The Container App reads them as Key Vault-referenced secrets
  through its managed identity. Terraform's own access to the vault's data
  plane (to write the generated secrets) is via `key_vault_allowed_ip_ranges`
  (deployer/agent public IPs) — documented as a first-apply requirement,
  same shape as the existing template's "apply twice" bootstrap step.

## Names and layout

- Template folder: `infrastructure/privately-accessible-container-app-with-database/`
- Workload code: `pcd` (private container + database)
- Stack folder: `stacks/container-app-with-database/`
- Content folder: `content/python-crud-app/` (per the `<language>-<pattern>-app`
  naming rule — it's built into a container image, not uploaded as static
  site content)
- The new template is a **self-contained copy** of
  `privately-accessible-container-app`: `naming`, `network`, `container-app`,
  `entra-app-auth`, `monitoring`, `bootstrap/`, `scripts/`, and the pipeline
  skeleton are copied in and then extended, not referenced by relative path
  across template folders (`CLAUDE.md`: "Templates must not reference each
  other's files, so any one of them can be copied out on its own").

## Infrastructure

```
Corporate user ──hub peering + private DNS──▶ internal load balancer
   ──▶ Container App (Entra sign-in, assigned groups only)
   ──▶ app login screen (username/password, session cookie)
   ──▶ container, port 8000

Container App ──managed identity──▶ Key Vault (private endpoint)
   holds: DB admin password, DB app-user password, Flask SECRET_KEY,
          seed users' initial passwords, Entra client secret,
          App Insights connection string

Container App ──password from Key Vault reference──▶ PostgreSQL Flexible
   Server (VNet-integrated, delegated subnet, no public access)

Container App ──managed identity (no account key)──▶ Storage account
   (private endpoint), Blob container "images"

Container logs ──▶ Log Analytics
Traces, requests, exceptions ──▶ Application Insights ──▶ alerts
Delivery pipeline ──az acr build──▶ Container Registry
   ◀──AcrPull (managed identity)── Container App
```

### Network

Three subnets in the spoke VNet, all prefixes from `terraform.tfvars` (the
IP plan), all names from an extended `naming` module:

| Subnet | Purpose | Minimum size |
| --- | --- | --- |
| `snet-cae-<suffix>` | Container Apps environment (delegated `Microsoft.App/environments`) | /27, same as today |
| `snet-pg-<suffix>` | PostgreSQL Flexible Server (delegated `Microsoft.DBforPostgreSQL/flexibleServers`) | /28 |
| `snet-pe-<suffix>` | Private endpoints: Key Vault, Storage | /28 |

Each subnet keeps its own NSG (`nsg-cae-…`, `nsg-pg-…`, `nsg-pe-…`), same
deny-internet-inbound pattern as today. Hub peering, custom DNS servers and
`use_hub_gateway` stay as they are — unchanged variables, reused as-is.

### Private DNS

Zones created and linked to the spoke (and the hub, when
`hub_virtual_network_id` is set), same pattern as the existing environment
domain zone:

- `privatelink.postgres.database.azure.com`
- `privatelink.vaultcore.azure.net`
- `privatelink.blob.core.windows.net`
- the Container Apps environment's own domain (unchanged)

### PostgreSQL Flexible Server

New module `modules/postgresql/`. Variables, all environment-driven:

- `postgresql_sku_name` (e.g. `B_Standard_B1ms` dev/qa, `GP_Standard_D2ds_v5` uat/prod)
- `postgresql_storage_mb` (min 32768)
- `postgresql_version` (default `16`)
- `postgresql_backup_retention_days` (7–35)
- `postgresql_geo_redundant_backup_enabled` (bool)
- `postgresql_ha_enabled` (bool) + `postgresql_ha_mode` (`ZoneRedundant` | `SameZone`)
- `postgresql_zone` / `postgresql_standby_zone` (explicit zone placement, like `zone_redundancy_enabled` elsewhere)

Validation: HA refuses a Burstable SKU (`B_*`) — matches the existing
`registry_zone_redundancy_enabled needs Premium` pattern. A `check` warns if
`postgresql_ha_enabled` is on with a SKU/region that lacks zones, mirroring
`zone_redundancy_has_replicas_to_spread`.

Defaults by environment (set in `terraform.tfvars`, not hard-coded):
dev/qa → Burstable B1ms, no HA; uat/prod → General Purpose D2ds_v5,
zone-redundant HA.

No public network access; the server joins `snet-pg-<suffix>` directly
(Flexible Server VNet integration doesn't use a private endpoint).

The database admin password and the app's own least-privilege database
role's password are both `random_password` resources, written to Key Vault
immediately — never in `terraform.tfvars` or the image.

### Storage (images)

New module extends `container-app` or a new `modules/storage/` (implementation
plan decides which is cleaner) with:

- `storage_replication_type` (LRS/ZRS/GZRS variable; ZRS dev/qa, GZRS uat/prod
  — same resilience-as-parameter rule as everything else)
- `shared_access_key_enabled = false` — the app authenticates with its
  managed identity only
- `public_network_access_enabled = false`, private endpoint in `snet-pe`
- `blob_soft_delete_retention_days` variable
- One container, `images`, private access
- Role assignment: the container app's identity gets **Storage Blob Data
  Contributor** scoped to the storage account (container-level scoping isn't
  supported by the built-in role; documented as a trade-off)

### Key Vault

New `modules/key-vault/`:

- RBAC authorization mode (no access policies)
- `public_network_access_enabled = false`, private endpoint in `snet-pe`
- `purge_protection_enabled` variable, on by default in uat/prod
- `key_vault_allowed_ip_ranges` — public IPs allowed to reach the **data
  plane** during `terraform apply`, needed because Terraform itself must
  write the generated secrets before the private endpoint-only path is
  useful from CI/CD. Documented in the README as a first-apply requirement,
  same shape as the "apply twice, registry is empty" step already in the
  existing template.
- Secrets stored: `db-admin-password`, `db-app-password`,
  `flask-secret-key`, `seed-admin-password`, `seed-demo-password`, plus the
  existing `microsoft-provider-authentication-secret` and
  `appinsights-connection`.
- The container app's managed identity gets **Key Vault Secrets User**;
  secrets are wired into the container app as Key Vault-referenced secrets
  (`azurerm_container_app` supports `key_vault_secret_id` per secret), same
  mechanism as today's plain secrets, just sourced from the vault instead of
  being passed as Terraform variables.

### Zones / resilience summary

| Resource | Zone parameter | Dev/QA | UAT/Prod |
| --- | --- | --- | --- |
| Container Apps environment | `zone_redundancy_enabled` (existing) | off | on, `min_replicas=2` |
| Container Registry | `registry_zone_redundancy_enabled` (existing) | off | optional, Premium |
| PostgreSQL | `postgresql_ha_enabled` + `postgresql_ha_mode` | off | on, `ZoneRedundant` |
| Storage | `storage_replication_type` | ZRS | GZRS |
| Key Vault | not zonal — platform-managed, noted in README's "Not applicable" row | — | — |
| Terraform state | `replication_type` in `bootstrap/` (existing) | GZRS default | GZRS default |

### Monitoring and governance

Unchanged pattern, extended targets: diagnostic settings on PostgreSQL, Key
Vault and Storage into the existing Log Analytics workspace; two new metric
alerts (PostgreSQL CPU percent, storage percent used — both thresholds are
variables like the existing restart/5xx alerts). Governance tags, budget,
delete lock in uat/prod, monitoring viewer roles: unchanged pattern, applied
to the new resources too.

## Application (`content/python-crud-app/`)

Same base as `python-mvc-app` (Flask app factory, gunicorn, non-root
Dockerfile, `/healthz`, Application Insights via OpenTelemetry), extended
with:

**Dependencies added:** `SQLAlchemy`, `psycopg[binary]`, `azure-identity`,
`azure-storage-blob`. No Flask-Login, no Flask-WTF — session-based login and
a CSRF token are small enough to hand-write (see `current_user.py`'s existing
"headers are only trustworthy behind the platform" pattern; the new login is
the second, independent trust layer on top).

**Data model:**

- `User`: id, username (unique), password_hash (werkzeug `scrypt`), role
  (`admin` | `user`), failed_login_count, locked_until, created_at
- `Asset`: id, name, category, description, image_blob_name (nullable),
  owner_user_id (FK), created_at, updated_at

**Pages / routes:**

- `/login`, `/logout` — username/password form, session cookie
  (`Secure; HttpOnly; SameSite=Lax`), CSRF token on the form
- `/assets` — list, search by name/category (any signed-in user)
- `/assets/new`, `/assets/<id>/edit`, `/assets/<id>/delete` — owner or admin
  only; image upload validated by content-sniffing (not just extension),
  size-limited via the existing `MAX_CONTENT_LENGTH` pattern
- `/assets/<id>/image` — streams the blob through the app (keeps the storage
  account private; the app checks the requester is signed in before
  streaming)
- `/admin/users` — admin only: list, create, reset password, delete (not
  self-delete)

**Authorization rule:** every route requires the Entra-authenticated
`X-MS-CLIENT-PRINCIPAL-*` headers to be present (unchanged outer gate) *and*
a valid app session (new inner gate). Losing either one signs the user out.

**Lockout:** N failed attempts (env-configurable, default 5) locks the
account for a cooldown window (default 15 min) — mitigates password
guessing now that there's a real password to guess, called out per
`CLAUDE.md`/brainstorming's "never simplify away security measures" rule.

**Seeding:** on startup, if no admin user exists, create `admin` and `demo`
users (usernames from env vars, passwords read from the Key Vault-sourced
env vars the same way the DB password is). A Postgres advisory lock
(`pg_advisory_lock`) guards the seed/`create_all` step so two replicas
starting together don't race.

**Schema management:** `db.create_all()` at startup — no Alembic. This is a
deliberate corner: fine for a fresh template with no prior schema to migrate.
*Skipped: migrations tooling — add Alembic when the schema first changes
after a template consumer has real data.*

**Local dev / tests:** `DATABASE_URL` unset → SQLite in a temp file;
storage account unset → local folder under a temp dir. `pytest` covers
login, lockout, CSRF rejection, ownership-based authorization (user A can't
edit user B's asset), and basic CRUD.

## What's explicitly out of scope

- Alembic migrations (noted above as the upgrade path)
- Password reset via email (admin resets it instead — no email service in
  this template)
- Multi-factor app-level auth (Entra's own MFA, if the tenant requires it,
  already applies to the outer layer)
- The public counterpart (`publicly-accessible-container-app`) — this stays
  internal-only like its sibling

## Cost estimate (to be finalised in the README with full retail-price detail)

West Europe, retrieved 2026-09-28 from the Azure Retail Prices API, 730-hour
month, list prices, before the Container Apps free grant:

| Item | Dev/QA | UAT/Prod |
| --- | --- | --- |
| PostgreSQL compute (Burstable B1ms $0.0199/hr, or GP D2ds_v5 $0.212/hr ×2 for zone-redundant HA) | ~$14.53 | ~$309.52 |
| PostgreSQL storage, 32 GiB @ $0.1369/GiB-month | ~$4.38 | ~$4.38+ |
| PostgreSQL backup storage, LRS $0.103/GiB-month (GRS ~2x, uat/prod) | ~$1–3 | ~$3–8 |
| Key Vault, Standard, operations @ $0.03/10K | <$1 | <$1 |
| Blob storage, Hot LRS $0.0196/GiB-month (dev/qa) or Hot GZRS ~$0.046/GiB-month (uat/prod), few GiB of images | <$1 | ~$1–2 |
| Private endpoints (Key Vault, Storage), published rate ~$0.01/hr each + data processed | ~$14.60 (2 endpoints) | ~$14.60+ |
| Container Apps, Registry, DNS, alerts, monitoring (existing template's numbers) | ~$35 (idle) | ~$67 (idle) |
| **Total, mostly idle** | **~$70–75/month** | **~$400–410/month** |

The jump from dev/qa to uat/prod is dominated by zone-redundant PostgreSQL HA
(two D2ds_v5 instances instead of one Burstable). This gets fully priced —
with confirmed meters, not estimates — in the template's own README, per
`CLAUDE.md`'s cost-estimate rule, during implementation.

## Testing

- `terraform test` (mocked providers): network subnet/NSG shape, PostgreSQL
  HA-vs-SKU validation, Key Vault private-access-only assertions, Container
  App Key Vault secret references, same style as the existing
  `private_app.tftest.hcl`
- `terraform fmt -recursive` / `validate` for the new template
- Python `pytest`: auth, lockout, CSRF, per-owner authorization, CRUD,
  image upload validation

## Documentation and delivery

- `README.md` — Design decisions table (Concern/Decision/Why/Trade-off,
  including the two new rows: "Second auth layer" and "Database"), Cost
  estimate section, first-time setup (now three applies: platform with
  `create_container_app=false`, push image, `create_container_app=true` —
  same shape as today)
- `ARCHITECTURE.md` — C4 Mermaid model
- `c4-context.drawio`, `c4-containers.drawio` via the `c4-drawio` skill
- `pipelines/azure-pipelines.yml` — copied and extended (image build step
  unchanged; still ACR Tasks)
- Update `CLAUDE.md`'s template table and `GOLDEN-TEMPLATES.md`'s catalogue
  to list the new template

## Open items for the implementation plan (not decisions the plan should re-litigate)

- Exact module boundary for storage (own `modules/storage/` vs. folded into
  `container-app`) — pick during planning, not architecturally significant
- Exact CSRF token implementation (hand-rolled double-submit cookie is the
  expected lazy-but-correct choice; the plan should not add a dependency for
  it)
