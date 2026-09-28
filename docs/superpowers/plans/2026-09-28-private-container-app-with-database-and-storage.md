# Privately accessible container app with database and storage — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fifth golden template — a containerised Flask CRUD app for internal users, with its own PostgreSQL database and Blob image storage, app-level username/password login layered on top of the existing Entra sign-in, and every network/zone/storage/region choice parameterized like its sibling `privately-accessible-container-app`.

**Architecture:** Copy the `privately-accessible-container-app` template wholesale (it must stay self-contained), extend `naming`/`network`/`container-app`/`monitoring` with three new modules (`postgresql`, `key-vault`, `storage`), and wire generated secrets through Key Vault references into the container app. The Flask app gets a SQLAlchemy data layer, hand-rolled session login (no new web-framework dependency), and a generic asset-catalogue CRUD.

**Tech Stack:** Terraform 1.9+, azurerm ~>4.60, azuread ~>3.0, azapi ~>2.12, random ~>3.6; Python 3.13, Flask, SQLAlchemy 2, psycopg3, azure-identity, azure-storage-blob, gunicorn, pytest.

**Spec:** [docs/superpowers/specs/2026-09-28-private-container-app-with-database-design.md](../specs/2026-09-28-private-container-app-with-database-design.md)

## Deviation from spec (flag for review)

The spec's Key Vault list has two DB secrets (`db-admin-password`, `db-app-password` for a separate least-privilege role). This plan uses **one** PostgreSQL credential (`db-password`), used by both Terraform (to create the database) and the app (to connect), instead of adding a second Terraform provider (`cyrilgdn/postgresql` or similar) just to create a scoped role from outside the network. The server is single-tenant per environment already — nothing else connects to it — so the extra role buys little isolation here.
`# ponytail: single admin credential instead of a separate least-privilege app role; add a scoped Postgres role (via the app's own startup SQL, since it already has network access the Terraform runner may not) if a second consumer of this database ever appears.`
Say so now if you want the two-role version instead; otherwise the plan below proceeds with one.

## Global Constraints

- Terraform `>= 1.9.0`; providers pinned (`azurerm ~> 4.60`, `azuread ~> 3.0`, `azapi ~> 2.12`, `time ~> 0.12`, `random ~> 3.6`); `.terraform.lock.hcl` committed.
- `location` is required in every environment's `terraform.tfvars` and in `bootstrap/`, no default.
- Zone redundancy is a variable everywhere the service supports it: Container Apps environment, PostgreSQL HA, storage replication. Off in dev/qa, on in uat/prod.
- Storage redundancy (Postgres backup geo-redundancy, Blob replication type, Terraform state GZRS) is always a variable, never hard-coded.
- Subnet address prefixes come from `terraform.tfvars`; subnet and NSG names come from the `naming` module.
- Never change the `key` in an existing `backend.hcl`.
- Every row in the README's `## Design decisions` table has a Why and a Trade-off.
- The README's `## Cost estimate` is priced from the Azure Retail Prices API, per environment, with retrieval date and unit prices.
- `c4-context.drawio` and `c4-containers.drawio` ship next to `ARCHITECTURE.md`, generated/checked with the `c4-drawio` skill.
- Governance on every environment: mandatory tags, budget, delete lock in uat/prod, least-privilege viewer/operator roles, monitoring that cannot be turned off in prod.
- The template is self-contained: no relative path reaches outside its own folder.
- The example app stays build-free: plain HTML/CSS/JS templates, no frontend build step.
- Never put client/customer names in `infrastructure/`, `content/` or `PRODUCT.md`.

## Review Focus

- A locked-out account must stay rejected even with the correct password until the cooldown expires — Task 17's test.
- A POST/PUT/DELETE with a missing or wrong CSRF token must be refused (400), not silently processed — Task 17's test.
- A signed-in user who is neither the asset's owner nor an admin must get 403 on edit/delete, never a silent no-op or someone else's data — Task 19's test.
- An uploaded file whose extension lies about its type (e.g. a `.jpg` that isn't really a JPEG) must be rejected by content-sniffing, not trusted by extension or `Content-Type` header alone — Task 19's test.
- The first `terraform plan` with `create_container_app = false` must not dereference a Key Vault secret ID that doesn't exist yet (the app-only secrets are written before the app exists, but the Entra/App-Insights ones are not) — Task 12's test.

---

## File Structure

```
infrastructure/privately-accessible-container-app-with-database-and-storage/
  README.md · ARCHITECTURE.md · c4-context.drawio · c4-containers.drawio · .gitignore
  bootstrap/{main.tf,example.tfvars}
  modules/
    naming/main.tf              # copied + 7 new outputs
    network/main.tf             # copied + 2 new subnets/NSGs
    container-app/main.tf       # copied + Key Vault secret refs + identity outputs
    entra-app-auth/main.tf      # copied unchanged
    monitoring/main.tf          # copied + diagnostics/alerts for pg, kv, storage
    postgresql/main.tf          # new
    key-vault/main.tf           # new
    storage/main.tf             # new
  stacks/container-app-with-database-and-storage/
    versions.tf · providers.tf · variables.tf · main.tf · outputs.tf
    tests/private_app_with_db.tftest.hcl
  environments/{dev,qa,uat,prod}/{terraform.tfvars,backend.hcl}
  scripts/tf.sh · tf.ps1        # copied + one path edit each
  pipelines/azure-pipelines.yml # copied + paths/names updated

content/python-crud-app/
  app/
    __init__.py                 # factory: db, seeding, blueprints, error handlers
    db.py                       # engine/session, env-driven DATABASE_URL
    seed.py                     # seed admin/demo users, advisory-lock guarded
    uploads.py                  # magic-byte image sniffing
    storage.py                  # blob read/write with local-folder fallback
    auth/security.py            # session login, CSRF, login/admin decorators
    models/{user.py,asset.py,current_user.py}
    controllers/{auth_controller.py,asset_controller.py,admin_controller.py,health_controller.py}
    views/{layout.html,login.html,error.html,assets/list.html,assets/form.html,admin/users.html}
    static/styles.css
  tests/{conftest.py,test_health.py,test_auth.py,test_assets.py,test_admin.py}
  Dockerfile · requirements.txt · requirements-dev.txt · README.md · .dockerignore · .gitignore
```

---

## Task 1: Scaffold the template folder

Copies the pieces that don't change (bootstrap, scripts, entra-app-auth module, `.gitignore`) so later tasks only touch what's actually new or different.

**Files:**
- Create (copy, then edit paths): `infrastructure/privately-accessible-container-app-with-database-and-storage/bootstrap/main.tf`, `bootstrap/example.tfvars`, `.gitignore`, `scripts/tf.sh`, `scripts/tf.ps1`, `modules/entra-app-auth/main.tf`

**Interfaces:**
- Produces: the folder tree other tasks write into; `entra-app-auth` module unchanged (`client_id`, `client_secret` outputs, as in the source template).

- [ ] **Step 1: Copy the reusable files**

```bash
src=infrastructure/privately-accessible-container-app
dst=infrastructure/privately-accessible-container-app-with-database-and-storage
mkdir -p "$dst"/{bootstrap,scripts,modules/entra-app-auth,pipelines}
cp "$src/bootstrap/main.tf" "$dst/bootstrap/main.tf"
cp "$src/bootstrap/example.tfvars" "$dst/bootstrap/example.tfvars"
cp "$src/.gitignore" "$dst/.gitignore"
cp "$src/scripts/tf.sh" "$dst/scripts/tf.sh"
cp "$src/scripts/tf.ps1" "$dst/scripts/tf.ps1"
cp "$src/modules/entra-app-auth/main.tf" "$dst/modules/entra-app-auth/main.tf"
```

- [ ] **Step 2: Point the scripts at the new stack folder**

In `scripts/tf.sh`, change:
```bash
stack="$root/stacks/container-app"
```
to:
```bash
stack="$root/stacks/container-app-with-database-and-storage"
```

In `scripts/tf.ps1`, change:
```powershell
$stack  = Join-Path $root 'stacks/container-app'
```
to:
```powershell
$stack  = Join-Path $root 'stacks/container-app-with-database-and-storage'
```

- [ ] **Step 3: Point the bootstrap comment and example key at the new template**

In `bootstrap/main.tf`, the comment block at the top already says `<template-name>/bootstrap`; edit the two `terraform -chdir=...` example lines to `infrastructure/privately-accessible-container-app-with-database-and-storage/bootstrap`. Leave the rest of the file unchanged — it's already fully parameterized.

- [ ] **Step 4: Verify the copy is syntactically valid**

Run: `terraform fmt -check infrastructure/privately-accessible-container-app-with-database-and-storage/bootstrap`
Expected: no output (already formatted, since it's a byte-for-byte copy).

- [ ] **Step 5: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage
git commit -m "chore: scaffold container-app-with-database-and-storage template"
```

---

## Task 2: Naming module

**Files:**
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/modules/naming/main.tf`

**Interfaces:**
- Consumes: nothing (pure computation, same as the source module).
- Produces (new outputs, in addition to every output the source `naming` module already has — `suffix`, `resource_group`, `virtual_network`, `subnet_container_apps`, `nsg_container_apps`, `container_apps_environment`, `container_app`, `container_registry`, `managed_identity`, `entra_app`, `log_analytics`, `application_insights`, `action_group`, `action_group_short`, `budget`): `subnet_postgresql`, `nsg_postgresql`, `subnet_private_endpoints`, `nsg_private_endpoints`, `postgresql_server`, `key_vault`, `storage_account` — all `string`.

- [ ] **Step 1: Copy the source module**

```bash
cp infrastructure/privately-accessible-container-app/modules/naming/main.tf \
   infrastructure/privately-accessible-container-app-with-database-and-storage/modules/naming/main.tf
```

- [ ] **Step 2: Append the new outputs**

Add at the end of the copied file:

```hcl
output "subnet_postgresql" { value = "snet-pg-${local.suffix}" }
output "nsg_postgresql" { value = "nsg-pg-${local.suffix}" }
output "subnet_private_endpoints" { value = "snet-pe-${local.suffix}" }
output "nsg_private_endpoints" { value = "nsg-pe-${local.suffix}" }
output "postgresql_server" { value = "psql-${local.suffix}" }
output "key_vault" { value = "kv-${local.suffix}" }
output "storage_account" { value = replace("st${local.suffix}", "-", "") } # alphanumeric only
```

- [ ] **Step 3: Verify with a plan-free apply of the module alone**

Run:
```bash
cd infrastructure/privately-accessible-container-app-with-database-and-storage/modules/naming
terraform init -backend=false
terraform validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage/modules/naming
git commit -m "feat: extend naming module for postgresql, key vault and storage"
```

---

## Task 3: Network module — postgresql and private-endpoints subnets

**Files:**
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/modules/network/main.tf`

**Interfaces:**
- Consumes: nothing beyond what the source module already takes (`name`, `resource_group_name`, `location`, `address_space`, `container_apps_subnet_name`, `nsg_name`, `container_apps_subnet_prefix`, `dns_servers`, `hub_virtual_network_id`, `use_hub_gateway`, `tags`) plus the new variables below.
- Produces: existing outputs (`virtual_network_id`, `container_apps_subnet_id`) plus new `postgresql_subnet_id`, `private_endpoints_subnet_id`.

New variables: `postgresql_subnet_name` (string), `postgresql_subnet_prefix` (string, "At least /28. Delegated to Microsoft.DBforPostgreSQL/flexibleServers."), `postgresql_nsg_name` (string), `private_endpoints_subnet_name` (string), `private_endpoints_subnet_prefix` (string, "At least /28."), `private_endpoints_nsg_name` (string).

- [ ] **Step 1: Copy the source module**

```bash
cp infrastructure/privately-accessible-container-app/modules/network/main.tf \
   infrastructure/privately-accessible-container-app-with-database-and-storage/modules/network/main.tf
```

- [ ] **Step 2: Add the new variables**

Insert after the existing `variable "tags"` block:

```hcl
variable "postgresql_subnet_name" {
  description = "From the naming module, e.g. snet-pg-pcds-dev-weu-001."
  type        = string
}

variable "postgresql_subnet_prefix" {
  description = "At least /28. Delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  type        = string
}

variable "postgresql_nsg_name" {
  type = string
}

variable "private_endpoints_subnet_name" {
  description = "From the naming module, e.g. snet-pe-pcds-dev-weu-001."
  type        = string
}

variable "private_endpoints_subnet_prefix" {
  description = "At least /28. Hosts the Key Vault and Storage private endpoints."
  type        = string
}

variable "private_endpoints_nsg_name" {
  type = string
}
```

- [ ] **Step 3: Add the two subnets, their NSGs, and the associations**

Insert before the `azurerm_virtual_network_peering` resource:

```hcl
resource "azurerm_subnet" "postgresql" {
  name                 = var.postgresql_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.postgresql_subnet_prefix]

  delegation {
    name = "postgresql-flexible-server"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_network_security_group" "postgresql" {
  name                = var.postgresql_nsg_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  security_rule {
    name                       = "AllowPostgresFromVirtualNetwork"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "postgresql" {
  subnet_id                 = azurerm_subnet.postgresql.id
  network_security_group_id = azurerm_network_security_group.postgresql.id
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = var.private_endpoints_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.private_endpoints_subnet_prefix]
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = var.private_endpoints_nsg_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  security_rule {
    name                       = "AllowHttpsFromVirtualNetwork"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}
```

- [ ] **Step 4: Add the two new outputs**

Append:
```hcl
output "postgresql_subnet_id" {
  value = azurerm_subnet.postgresql.id
}

output "private_endpoints_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}
```

- [ ] **Step 5: Verify**

Run:
```bash
cd infrastructure/privately-accessible-container-app-with-database-and-storage/modules/network
terraform init -backend=false && terraform validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 6: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage/modules/network
git commit -m "feat: add postgresql and private-endpoints subnets to network module"
```

---

## Task 4: Key Vault module (new)

**Files:**
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/modules/key-vault/main.tf`

**Interfaces:**
- Consumes: `name`, `resource_group_name`, `location`, `tenant_id`, `private_endpoint_subnet_id`, `private_dns_zone_id`, `purge_protection_enabled` (bool), `allowed_ip_ranges` (list(string)), `writer_principal_id`, `reader_principal_id`, `secrets` (sensitive map(string)), `tags`.
- Produces: `id` (string), `secret_ids` (map(string), name → versionless secret ID) — later tasks reference `module.key_vault.secret_ids["<name>"]`.

- [ ] **Step 1: Write the module**

```hcl
# Key Vault for generated secrets (DB password, Flask secret key, seed user
# passwords, Entra client secret, App Insights connection string): RBAC
# authorization, private endpoint only. Network ACLs default-deny except the
# IP ranges Terraform itself runs from — needed because Terraform has to
# write these secrets through the data plane before anything else can read
# them, the same "first apply reaches further than the private endpoint
# allows" shape as the registry-is-empty step in the sibling template.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_id" {
  type = string
}

variable "purge_protection_enabled" {
  type    = bool
  default = false
}

variable "allowed_ip_ranges" {
  description = "Public IP ranges (CIDR) allowed to reach the vault's data plane during terraform apply, e.g. the pipeline agent's or your own. Empty means only the private endpoint can reach it, so Terraform itself needs network access to the spoke (a self-hosted agent, or a bastion/VPN into it)."
  type        = list(string)
  default     = []
}

variable "writer_principal_id" {
  description = "Object ID of the identity running Terraform. Granted Key Vault Secrets Officer so it can write the generated secrets."
  type        = string
}

variable "reader_principal_id" {
  description = "The container app's managed identity. Granted Key Vault Secrets User."
  type        = string
}

variable "secrets" {
  description = "Secret name => value."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_key_vault" "this" {
  name                           = var.name
  resource_group_name            = var.resource_group_name
  location                       = var.location
  tenant_id                      = var.tenant_id
  sku_name                       = "standard"
  enable_rbac_authorization      = true
  purge_protection_enabled       = var.purge_protection_enabled
  public_network_access_enabled  = length(var.allowed_ip_ranges) > 0
  tags                           = var.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_ranges
  }
}

resource "azurerm_private_endpoint" "this" {
  name                = "pe-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "azurerm_role_assignment" "writer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id          = var.writer_principal_id
}

resource "azurerm_role_assignment" "reader" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.reader_principal_id
}

resource "azurerm_key_vault_secret" "this" {
  for_each = var.secrets

  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.writer]
}

output "id" {
  value = azurerm_key_vault.this.id
}

output "secret_ids" {
  value = { for name, secret in azurerm_key_vault_secret.this : name => secret.versionless_id }
}
```

- [ ] **Step 2: Verify**

Run:
```bash
cd infrastructure/privately-accessible-container-app-with-database-and-storage/modules/key-vault
terraform init -backend=false && terraform validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage/modules/key-vault
git commit -m "feat: add key-vault module for generated secrets"
```

---

## Task 5: PostgreSQL module (new)

**Files:**
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/modules/postgresql/main.tf`

**Interfaces:**
- Consumes: `name`, `resource_group_name`, `location`, `delegated_subnet_id`, `private_dns_zone_id`, `postgresql_version` (default `"16"`), `sku_name`, `storage_mb` (default `32768`), `backup_retention_days` (7–35), `geo_redundant_backup_enabled` (bool), `ha_enabled` (bool), `ha_mode` (`ZoneRedundant`|`SameZone`), `zone`, `standby_zone`, `administrator_login`, `administrator_password` (sensitive), `database_name` (default `"app"`), `tags`.
- Produces: `server_id`, `fqdn`, `database_name`.

- [ ] **Step 1: Write the module**

```hcl
# Azure Database for PostgreSQL Flexible Server, VNet-integrated: reachable
# only from its delegated subnet, never from the public internet.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "delegated_subnet_id" {
  type = string
}

variable "private_dns_zone_id" {
  type = string
}

variable "postgresql_version" {
  type    = string
  default = "16"
}

variable "sku_name" {
  description = "e.g. B_Standard_B1ms (Burstable, dev/qa) or GP_Standard_D2ds_v5 (General Purpose, uat/prod)."
  type        = string
}

variable "storage_mb" {
  type    = number
  default = 32768
}

variable "backup_retention_days" {
  type    = number
  default = 7

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "geo_redundant_backup_enabled" {
  type    = bool
  default = false
}

variable "ha_enabled" {
  description = "Zone-redundant or same-zone standby. Needs a non-Burstable sku_name. Fixed at creation."
  type        = bool
  default     = false
}

variable "ha_mode" {
  type    = string
  default = "ZoneRedundant"

  validation {
    condition     = contains(["ZoneRedundant", "SameZone"], var.ha_mode)
    error_message = "ha_mode must be ZoneRedundant or SameZone."
  }
}

variable "zone" {
  description = "Primary availability zone, e.g. \"1\". Null lets Azure pick."
  type        = string
  default     = null
}

variable "standby_zone" {
  description = "Standby zone when ha_mode = ZoneRedundant. Ignored otherwise."
  type        = string
  default     = null
}

variable "administrator_login" {
  type = string
}

variable "administrator_password" {
  type      = string
  sensitive = true
}

variable "database_name" {
  type    = string
  default = "app"
}

variable "tags" {
  type    = map(string)
  default = {}
}

# A Burstable server has no standby to fail over to.
check "ha_needs_non_burstable_sku" {
  assert {
    condition     = !var.ha_enabled || !startswith(var.sku_name, "B_")
    error_message = "ha_enabled needs a General Purpose or Memory Optimized sku_name; Burstable (B_*) has no standby."
  }
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = var.postgresql_version

  delegated_subnet_id = var.delegated_subnet_id
  private_dns_zone_id = var.private_dns_zone_id

  sku_name   = var.sku_name
  storage_mb = var.storage_mb
  zone       = var.zone

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password

  dynamic "high_availability" {
    for_each = var.ha_enabled ? [1] : []
    content {
      mode                      = var.ha_mode
      standby_availability_zone = var.ha_mode == "ZoneRedundant" ? var.standby_zone : null
    }
  }

  tags = var.tags
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

output "server_id" {
  value = azurerm_postgresql_flexible_server.this.id
}

output "fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "database_name" {
  value = azurerm_postgresql_flexible_server_database.app.name
}
```

- [ ] **Step 2: Verify**

Run:
```bash
cd infrastructure/privately-accessible-container-app-with-database-and-storage/modules/postgresql
terraform init -backend=false && terraform validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage/modules/postgresql
git commit -m "feat: add postgresql module (VNet-integrated Flexible Server)"
```

---

## Task 6: Storage module (new)

**Files:**
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/modules/storage/main.tf`

**Interfaces:**
- Consumes: `name`, `resource_group_name`, `location`, `private_endpoint_subnet_id`, `private_dns_zone_id`, `replication_type` (`LRS`|`ZRS`|`GZRS`|`RAGZRS`, default `"ZRS"`), `container_name` (default `"images"`), `soft_delete_retention_days` (default `7`), `reader_writer_principal_id`, `tags`.
- Produces: `id`, `account_name`, `primary_blob_endpoint`.

- [ ] **Step 1: Write the module**

```hcl
# Blob storage for asset images: private endpoint only, shared keys off — the
# app reads and writes with its managed identity, never an account key.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

variable "name" {
  description = "Storage account name: 3-24 lowercase letters and digits."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_id" {
  type = string
}

variable "replication_type" {
  description = "LRS, ZRS, GZRS or RAGZRS. ZRS in dev/qa, GZRS in uat/prod."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be LRS, ZRS, GZRS or RAGZRS."
  }
}

variable "container_name" {
  type    = string
  default = "images"
}

variable "soft_delete_retention_days" {
  type    = number
  default = 7
}

variable "reader_writer_principal_id" {
  description = "The container app's managed identity. Granted Storage Blob Data Contributor."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_storage_account" "this" {
  name                             = var.name
  resource_group_name              = var.resource_group_name
  location                         = var.location
  account_tier                     = "Standard"
  account_replication_type         = var.replication_type
  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  allow_nested_items_to_be_public  = false
  shared_access_key_enabled        = false
  public_network_access_enabled    = false
  tags                              = var.tags

  blob_properties {
    delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }
}

resource "azurerm_storage_container" "images" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_private_endpoint" "this" {
  name                = "pe-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "azurerm_role_assignment" "reader_writer" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.reader_writer_principal_id
}

output "id" {
  value = azurerm_storage_account.this.id
}

output "account_name" {
  value = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  value = azurerm_storage_account.this.primary_blob_endpoint
}
```

- [ ] **Step 2: Verify**

Run:
```bash
cd infrastructure/privately-accessible-container-app-with-database-and-storage/modules/storage
terraform init -backend=false && terraform validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage/modules/storage
git commit -m "feat: add storage module for asset images"
```

---

## Task 7: Container App module — Key Vault secret references

**Files:**
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/modules/container-app/main.tf`

**Interfaces:**
- Consumes: everything the source module takes, but `secrets` changes type from `map(string)` to `map(object({ value = optional(string), key_vault_secret_id = optional(string) }))`.
- Produces: everything the source module outputs, plus new `managed_identity_principal_id`, `managed_identity_id`.

- [ ] **Step 1: Copy the source module**

```bash
cp infrastructure/privately-accessible-container-app/modules/container-app/main.tf \
   infrastructure/privately-accessible-container-app-with-database-and-storage/modules/container-app/main.tf
```

- [ ] **Step 2: Change the `secrets` variable's type**

Replace:
```hcl
variable "secrets" {
  description = "Secret name => value. Each one is passed to the container as an environment variable named by secret_environment_variables."
  type        = map(string)
  default     = {}
  sensitive   = true
}
```
with:
```hcl
variable "secrets" {
  description = "Secret name => { value } for a plain secret, or { key_vault_secret_id } to read it from Key Vault through the app's managed identity. Each one is passed to the container as an environment variable named by secret_environment_variables."
  type = map(object({
    value               = optional(string)
    key_vault_secret_id = optional(string)
  }))
  default   = {}
  sensitive = true
}
```

- [ ] **Step 3: Update the dynamic `secret` block**

Replace:
```hcl
  dynamic "secret" {
    for_each = nonsensitive(toset(keys(var.secrets)))
    content {
      name  = secret.value
      value = var.secrets[secret.value]
    }
  }
```
with:
```hcl
  dynamic "secret" {
    for_each = nonsensitive(toset(keys(var.secrets)))
    content {
      name                = secret.value
      value               = var.secrets[secret.value].key_vault_secret_id == null ? var.secrets[secret.value].value : null
      key_vault_secret_id = var.secrets[secret.value].key_vault_secret_id
      identity            = var.secrets[secret.value].key_vault_secret_id == null ? null : azurerm_user_assigned_identity.app.id
    }
  }
```

- [ ] **Step 4: Add the two new outputs**

Append at the end of the file:
```hcl
output "managed_identity_principal_id" {
  value = azurerm_user_assigned_identity.app.principal_id
}

output "managed_identity_id" {
  value = azurerm_user_assigned_identity.app.id
}
```

- [ ] **Step 5: Verify**

Run:
```bash
cd infrastructure/privately-accessible-container-app-with-database-and-storage/modules/container-app
terraform init -backend=false && terraform validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 6: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage/modules/container-app
git commit -m "feat: container-app module reads secrets from key vault references"
```

---

## Task 8: Monitoring module — diagnostics and alerts for pg, key vault, storage

**Files:**
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/modules/monitoring/main.tf`

**Interfaces:**
- Consumes: everything the source module takes, plus new optional `postgresql_server_id`, `key_vault_id`, `storage_account_id` (all `string`, default `null`), `postgresql_cpu_alert_threshold` (number, default `80`), `storage_used_capacity_alert_threshold_gb` (number, default `50`).
- Produces: everything the source module already outputs (no changes there).

- [ ] **Step 1: Copy the source module**

```bash
cp infrastructure/privately-accessible-container-app/modules/monitoring/main.tf \
   infrastructure/privately-accessible-container-app-with-database-and-storage/modules/monitoring/main.tf
```

- [ ] **Step 2: Add the new variables**

Insert after the existing `variable "viewer_principal_ids"` block:

```hcl
variable "postgresql_server_id" {
  type    = string
  default = null
}

variable "key_vault_id" {
  type    = string
  default = null
}

variable "storage_account_id" {
  type    = string
  default = null
}

variable "postgresql_cpu_alert_threshold" {
  description = "Percent CPU averaged over 15 minutes that triggers the alert."
  type        = number
  default     = 80
}

variable "storage_used_capacity_alert_threshold_gb" {
  description = "Blob storage used capacity, in GB, that triggers the alert."
  type        = number
  default     = 50
}
```

- [ ] **Step 3: Add diagnostic settings and alerts**

Insert before the final `output` blocks:

```hcl
resource "azurerm_monitor_diagnostic_setting" "postgresql" {
  count = var.postgresql_server_id == null ? 0 : 1

  name                       = "diag-postgresql"
  target_resource_id         = var.postgresql_server_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  count = var.key_vault_id == null ? 0 : 1

  name                       = "diag-key-vault"
  target_resource_id         = var.key_vault_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "audit"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage" {
  count = var.storage_account_id == null ? 0 : 1

  name                       = "diag-storage"
  target_resource_id         = var.storage_account_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_metric_alert" "postgresql_cpu" {
  count = var.postgresql_server_id == null ? 0 : 1

  name                = "alert-postgresql-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgresql_server_id]
  description         = "PostgreSQL CPU has averaged above the threshold for 15 minutes."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.postgresql_cpu_alert_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_metric_alert" "storage_capacity" {
  count = var.storage_account_id == null ? 0 : 1

  name                = "alert-storage-capacity"
  resource_group_name = var.resource_group_name
  scopes              = [var.storage_account_id]
  description         = "Blob storage used capacity passed the threshold."
  severity            = 3
  frequency           = "PT1H"
  window_size         = "PT6H"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "UsedCapacity"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.storage_used_capacity_alert_threshold_gb * 1024 * 1024 * 1024
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}
```

- [ ] **Step 4: Verify**

Run:
```bash
cd infrastructure/privately-accessible-container-app-with-database-and-storage/modules/monitoring
terraform init -backend=false && terraform validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage/modules/monitoring
git commit -m "feat: monitor postgresql, key vault and storage"
```

---

## Task 9: Stack scaffolding — versions.tf, providers.tf, variables.tf

**Files:**
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage/versions.tf`
- Create: `.../providers.tf`
- Create: `.../variables.tf`

**Interfaces:**
- Produces: every variable `main.tf` (Task 10/11) reads — see full list in Step 3.

- [ ] **Step 1: Copy `versions.tf` and add the `random` provider**

```bash
dst=infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage
mkdir -p "$dst"
cp infrastructure/privately-accessible-container-app/stacks/container-app/versions.tf "$dst/versions.tf"
cp infrastructure/privately-accessible-container-app/stacks/container-app/providers.tf "$dst/providers.tf"
```

In the copied `versions.tf`, add inside `required_providers`:
```hcl
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
```

- [ ] **Step 2: Verify `providers.tf` needs no changes**

It already reads `var.subscription_id` and `var.tenant_id`, both still declared in `variables.tf` below — no edit needed.

- [ ] **Step 3: Write `variables.tf`**

Copy the source stack's `variables.tf` in full, then change `workload`'s default from `"pca"` to `"pcds"` and `image_repository`'s default from `"python-mvc-app"` to `"python-crud-app"`, and append these new variables at the end:

```hcl
# Network: two more subnets beyond the container apps one.

variable "postgresql_subnet_prefix" {
  description = "At least /28, inside vnet_address_space, not overlapping the other subnets."
  type        = string
}

variable "private_endpoints_subnet_prefix" {
  description = "At least /28, inside vnet_address_space, not overlapping the other subnets."
  type        = string
}

# Database

variable "postgresql_version" {
  type    = string
  default = "16"
}

variable "postgresql_sku_name" {
  description = "e.g. B_Standard_B1ms (Burstable, dev/qa) or GP_Standard_D2ds_v5 (General Purpose, uat/prod)."
  type        = string
}

variable "postgresql_storage_mb" {
  type    = number
  default = 32768
}

variable "postgresql_backup_retention_days" {
  type    = number
  default = 7
}

variable "postgresql_geo_redundant_backup_enabled" {
  type    = bool
  default = false
}

variable "postgresql_ha_enabled" {
  description = "Zone-redundant or same-zone standby. Needs a non-Burstable postgresql_sku_name. Fixed at creation."
  type        = bool
  default     = false
}

variable "postgresql_ha_mode" {
  type    = string
  default = "ZoneRedundant"
}

variable "postgresql_zone" {
  description = "Primary availability zone, e.g. \"1\". Null lets Azure pick."
  type        = string
  default     = null
}

variable "postgresql_standby_zone" {
  description = "Standby zone when postgresql_ha_mode = ZoneRedundant."
  type        = string
  default     = null
}

variable "postgresql_administrator_login" {
  type    = string
  default = "appadmin"
}

# Storage (images)

variable "storage_replication_type" {
  description = "LRS, ZRS, GZRS or RAGZRS. ZRS in dev/qa, GZRS in uat/prod."
  type        = string
  default     = "ZRS"
}

variable "storage_soft_delete_retention_days" {
  type    = number
  default = 7
}

# Key Vault

variable "key_vault_purge_protection_enabled" {
  type    = bool
  default = false
}

variable "key_vault_allowed_ip_ranges" {
  description = "Public IP ranges (CIDR) allowed to reach the vault's data plane during terraform apply. Empty means Terraform must run from inside the spoke's network."
  type        = list(string)
  default     = []
}

# Seed users

variable "seed_admin_username" {
  type    = string
  default = "admin"
}

variable "seed_demo_username" {
  type    = string
  default = "demo"
}

# Monitoring thresholds

variable "postgresql_cpu_alert_threshold" {
  type    = number
  default = 80
}

variable "storage_used_capacity_alert_threshold_gb" {
  type    = number
  default = 50
}
```

- [ ] **Step 4: Verify**

Run: `terraform fmt -check infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage`
Expected: no output, or re-run `terraform fmt -recursive` on the file and stage the formatted result (formatting isn't a failure, just run it once).

- [ ] **Step 5: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage/{versions.tf,providers.tf,variables.tf}
git commit -m "feat: stack scaffolding and variables for database/storage template"
```

---

## Task 10: Stack main.tf — network, DNS zones, secrets, database, storage, key vault

**Files:**
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage/main.tf` (first half; Task 11 appends the rest)

**Interfaces:**
- Consumes: `module.naming`, `module.network` (Task 3), `module.postgresql` (Task 5), `module.storage` (Task 6), `module.key_vault` (Task 4).
- Produces: `local.tags`, `local.db_password_secret_name = "db-password"`, `local.flask_secret_name = "flask-secret-key"`, `local.seed_admin_secret_name = "seed-admin-password"`, `local.seed_demo_secret_name = "seed-demo-password"`, `local.auth_secret_name = "microsoft-provider-authentication-secret"` — Task 11 reads all five.

- [ ] **Step 1: Write the network, tags, resource group and DNS zones**

```hcl
# Privately accessible container app with its own database and image
# storage, for internal users only.
#
#   User on the corporate network --hub peering + private DNS--> internal load balancer
#     --> Container App (Entra sign-in required, assigned groups only)
#     --> app login (username/password) --> container on port 8000
#   Container App --managed identity--> Key Vault (DB password, session secret, seed passwords)
#   Container App --password from Key Vault--> PostgreSQL Flexible Server (VNet-integrated)
#   Container App --managed identity, no keys--> Blob storage (private endpoint)

module "naming" {
  source = "../../modules/naming"

  workload    = var.workload
  environment = var.environment
  location    = var.location
  instance    = var.instance
}

locals {
  tags = merge(
    {
      environment           = var.environment
      application           = var.application_name
      workload               = var.workload
      audience               = "internal"
      owner                   = var.governance_tags.owner
      "cost-centre"           = var.governance_tags.cost_centre
      "data-classification"   = var.governance_tags.data_classification
      support                 = var.governance_tags.support
      "managed-by"            = "terraform"
    },
    var.extra_tags,
  )

  auth_secret_name        = "microsoft-provider-authentication-secret"
  db_password_secret_name = "db-password"
  flask_secret_name       = "flask-secret-key"
  seed_admin_secret_name  = "seed-admin-password"
  seed_demo_secret_name   = "seed-demo-password"
}

resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group
  location = var.location
  tags     = local.tags
}

data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------- network

module "network" {
  source = "../../modules/network"

  name                          = module.naming.virtual_network
  resource_group_name           = azurerm_resource_group.this.name
  location                      = var.location
  address_space                 = var.vnet_address_space
  container_apps_subnet_name    = module.naming.subnet_container_apps
  nsg_name                      = module.naming.nsg_container_apps
  container_apps_subnet_prefix  = var.container_apps_subnet_prefix
  postgresql_subnet_name        = module.naming.subnet_postgresql
  postgresql_subnet_prefix      = var.postgresql_subnet_prefix
  postgresql_nsg_name           = module.naming.nsg_postgresql
  private_endpoints_subnet_name = module.naming.subnet_private_endpoints
  private_endpoints_subnet_prefix = var.private_endpoints_subnet_prefix
  private_endpoints_nsg_name    = module.naming.nsg_private_endpoints
  dns_servers                   = var.dns_servers
  hub_virtual_network_id        = var.hub_virtual_network_id
  use_hub_gateway               = var.use_hub_gateway
  tags                          = local.tags
}

locals {
  dns_link_targets = merge(
    { spoke = module.network.virtual_network_id },
    var.hub_virtual_network_id == null ? {} : { hub = var.hub_virtual_network_id },
  )
}

# ---------------------------------------------------------------- private DNS

resource "azurerm_private_dns_zone" "postgresql" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgresql" {
  for_each = local.dns_link_targets

  name                  = "link-${each.key}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.postgresql.name
  virtual_network_id    = each.value
  tags                  = local.tags
}

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  for_each = local.dns_link_targets

  name                  = "link-${each.key}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = each.value
  tags                  = local.tags
}

resource "azurerm_private_dns_zone" "storage" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage" {
  for_each = local.dns_link_targets

  name                  = "link-${each.key}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.storage.name
  virtual_network_id    = each.value
  tags                  = local.tags
}

# ---------------------------------------------------------------- generated secrets

resource "random_password" "db_admin" {
  length  = 32
  special = false # keeps the value safe to embed in a connection string
}

resource "random_password" "flask_secret" {
  length = 48
}

resource "random_password" "seed_admin" {
  length = 20
}

resource "random_password" "seed_demo" {
  length = 20
}
```

- [ ] **Step 2: Add the database module**

Append:
```hcl
# ---------------------------------------------------------------- database

module "postgresql" {
  source = "../../modules/postgresql"

  name                = module.naming.postgresql_server
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  delegated_subnet_id = module.network.postgresql_subnet_id
  private_dns_zone_id = azurerm_private_dns_zone.postgresql.id

  postgresql_version            = var.postgresql_version
  sku_name                      = var.postgresql_sku_name
  storage_mb                    = var.postgresql_storage_mb
  backup_retention_days         = var.postgresql_backup_retention_days
  geo_redundant_backup_enabled  = var.postgresql_geo_redundant_backup_enabled
  ha_enabled                    = var.postgresql_ha_enabled
  ha_mode                       = var.postgresql_ha_mode
  zone                          = var.postgresql_zone
  standby_zone                  = var.postgresql_standby_zone

  administrator_login    = var.postgresql_administrator_login
  administrator_password = random_password.db_admin.result

  tags = local.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgresql]
}
```

- [ ] **Step 3: Add the storage module**

Append (note `reader_writer_principal_id` reaches forward into `module.container_app`, defined in Task 11 — this is not a cycle: only the container app's `azurerm_user_assigned_identity.app` resource is referenced, and that resource has no dependency on anything storage or key-vault produce):

```hcl
# ---------------------------------------------------------------- storage

module "storage" {
  source = "../../modules/storage"

  name                        = module.naming.storage_account
  resource_group_name         = azurerm_resource_group.this.name
  location                    = var.location
  private_endpoint_subnet_id  = module.network.private_endpoints_subnet_id
  private_dns_zone_id         = azurerm_private_dns_zone.storage.id
  replication_type            = var.storage_replication_type
  soft_delete_retention_days  = var.storage_soft_delete_retention_days
  reader_writer_principal_id  = module.container_app.managed_identity_principal_id

  tags = local.tags
}
```

- [ ] **Step 4: Add the Key Vault module**

Append:
```hcl
# ---------------------------------------------------------------- secrets storage

module "key_vault" {
  source = "../../modules/key-vault"

  name                        = module.naming.key_vault
  resource_group_name         = azurerm_resource_group.this.name
  location                    = var.location
  tenant_id                   = var.tenant_id
  private_endpoint_subnet_id  = module.network.private_endpoints_subnet_id
  private_dns_zone_id         = azurerm_private_dns_zone.key_vault.id
  purge_protection_enabled    = var.key_vault_purge_protection_enabled
  allowed_ip_ranges           = var.key_vault_allowed_ip_ranges

  writer_principal_id = data.azurerm_client_config.current.object_id
  reader_principal_id = module.container_app.managed_identity_principal_id

  secrets = merge(
    {
      (local.db_password_secret_name) = random_password.db_admin.result
      (local.flask_secret_name)       = random_password.flask_secret.result
      (local.seed_admin_secret_name)  = random_password.seed_admin.result
      (local.seed_demo_secret_name)   = random_password.seed_demo.result
    },
    var.create_container_app ? {
      (local.auth_secret_name) = module.entra_app[0].client_secret
      "appinsights-connection" = module.monitoring.application_insights_connection_string
    } : {},
  )

  tags = local.tags
}
```

- [ ] **Step 5: Note the file is intentionally incomplete**

`main.tf` references `module.container_app`, `module.entra_app` and `module.monitoring`, none defined yet — that's expected; `terraform validate` will fail until Task 11 finishes the file. Do not run `terraform validate` at the end of this task; Task 11's Step 6 is the first validation point.

- [ ] **Step 6: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage/main.tf
git commit -m "feat: wire network, dns, database, storage and key vault into the stack"
```

---

## Task 11: Stack main.tf — container app, sign-in, alerts, governance; outputs.tf

**Files:**
- Modify: `infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage/main.tf` (append)
- Create: `.../outputs.tf`

**Interfaces:**
- Consumes: `local.tags`, `local.auth_secret_name`, `local.db_password_secret_name`, `local.flask_secret_name`, `local.seed_admin_secret_name`, `local.seed_demo_secret_name` (Task 10); `module.postgresql.fqdn`, `module.postgresql.database_name`, `module.storage.account_name`, `module.key_vault.secret_ids` (Tasks 4–6); `module.monitoring.log_analytics_workspace_id` / `.application_insights_connection_string` / `.action_group_id`.
- Produces: `module.container_app.*` outputs (Task 7), consumed by `outputs.tf`.

- [ ] **Step 1: Add monitoring**

Append to `main.tf`:
```hcl
# ---------------------------------------------------------------- monitoring

module "monitoring" {
  source = "../../modules/monitoring"

  resource_group_name       = azurerm_resource_group.this.name
  resource_group_id         = azurerm_resource_group.this.id
  location                  = var.location
  log_analytics_name        = module.naming.log_analytics
  application_insights_name = module.naming.application_insights
  action_group_name         = module.naming.action_group
  action_group_short_name   = module.naming.action_group_short
  log_retention_days        = var.log_retention_days
  log_daily_quota_gb        = var.log_daily_quota_gb
  alert_email_receivers     = var.alert_email_receivers
  viewer_principal_ids      = var.monitoring_viewer_principal_ids

  postgresql_server_id                     = module.postgresql.server_id
  key_vault_id                             = module.key_vault.id
  storage_account_id                       = module.storage.id
  postgresql_cpu_alert_threshold           = var.postgresql_cpu_alert_threshold
  storage_used_capacity_alert_threshold_gb = var.storage_used_capacity_alert_threshold_gb

  tags = local.tags
}
```

- [ ] **Step 2: Add the container app**

Append:
```hcl
# ---------------------------------------------------------------- hosting

module "container_app" {
  source = "../../modules/container-app"

  resource_group_name   = azurerm_resource_group.this.name
  location               = var.location
  environment_name       = module.naming.container_apps_environment
  container_app_name     = module.naming.container_app
  registry_name           = module.naming.container_registry
  managed_identity_name   = module.naming.managed_identity
  subnet_id               = module.network.container_apps_subnet_id
  dns_zone_virtual_network_ids = local.dns_link_targets
  log_analytics_workspace_id   = module.monitoring.log_analytics_workspace_id
  zone_redundancy_enabled      = var.zone_redundancy_enabled
  registry_sku                 = var.registry_sku

  registry_zone_redundancy_enabled = var.registry_zone_redundancy_enabled

  create_container_app = var.create_container_app
  image_repository     = var.image_repository
  initial_image_tag    = var.initial_image_tag
  cpu                   = var.container_cpu
  memory                 = var.container_memory
  min_replicas           = var.min_replicas
  max_replicas           = var.max_replicas

  environment_variables = merge(var.app_settings, {
    DB_HOST                    = module.postgresql.fqdn
    DB_NAME                    = module.postgresql.database_name
    DB_USER                    = var.postgresql_administrator_login
    AZURE_STORAGE_ACCOUNT_NAME = module.storage.account_name
    AZURE_STORAGE_CONTAINER    = "images"
    SEED_ADMIN_USERNAME        = var.seed_admin_username
    SEED_DEMO_USERNAME         = var.seed_demo_username
  })

  secrets = var.create_container_app ? {
    (local.auth_secret_name)        = { key_vault_secret_id = module.key_vault.secret_ids[local.auth_secret_name] }
    "appinsights-connection"        = { key_vault_secret_id = module.key_vault.secret_ids["appinsights-connection"] }
    (local.db_password_secret_name) = { key_vault_secret_id = module.key_vault.secret_ids[local.db_password_secret_name] }
    (local.flask_secret_name)       = { key_vault_secret_id = module.key_vault.secret_ids[local.flask_secret_name] }
    (local.seed_admin_secret_name)  = { key_vault_secret_id = module.key_vault.secret_ids[local.seed_admin_secret_name] }
    (local.seed_demo_secret_name)   = { key_vault_secret_id = module.key_vault.secret_ids[local.seed_demo_secret_name] }
  } : {}

  secret_environment_variables = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = "appinsights-connection"
    DB_PASSWORD                            = local.db_password_secret_name
    APP_SECRET_KEY                         = local.flask_secret_name
    SEED_ADMIN_PASSWORD                    = local.seed_admin_secret_name
    SEED_DEMO_PASSWORD                     = local.seed_demo_secret_name
  }

  tags = local.tags
}

check "zone_redundancy_has_replicas_to_spread" {
  assert {
    condition     = !var.zone_redundancy_enabled || var.min_replicas >= 2
    error_message = "zone_redundancy_enabled is on but min_replicas is below 2: the one replica sits in one zone and must be rescheduled if that zone fails."
  }
}
```

- [ ] **Step 3: Add sign-in (unchanged shape from the source template)**

Append:
```hcl
# ---------------------------------------------------------------- sign-in

module "entra_app" {
  source = "../../modules/entra-app-auth"
  count  = var.create_container_app ? 1 : 0

  display_name        = module.naming.entra_app
  site_host_name      = module.container_app.container_app_fqdn
  allowed_group_ids   = var.allowed_group_ids
  assignment_required = true
  owners              = var.entra_app_owners
}

resource "azapi_resource" "sign_in" {
  count = var.create_container_app ? 1 : 0

  type      = "Microsoft.App/containerApps/authConfigs@2024-03-01"
  name      = "current"
  parent_id = module.container_app.container_app_id

  body = {
    properties = {
      platform = { enabled = true }
      globalValidation = {
        unauthenticatedClientAction = "RedirectToLoginPage"
        redirectToProvider          = "azureactivedirectory"
        excludedPaths               = ["/healthz"]
      }
      identityProviders = {
        azureActiveDirectory = {
          enabled = true
          registration = {
            clientId                = module.entra_app[0].client_id
            clientSecretSettingName = local.auth_secret_name
            openIdIssuer            = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
          }
        }
      }
    }
  }
}
```

- [ ] **Step 4: Add app alerts and governance (unchanged shape from the source template)**

Append:
```hcl
# ---------------------------------------------------------------- alerts

resource "azurerm_monitor_metric_alert" "restarts" {
  count = var.create_container_app ? 1 : 0

  name                = "alert-restarts-${module.naming.suffix}"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [module.container_app.container_app_id]
  description         = "The container restarted: it crashed or failed its health probe."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "RestartCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = module.monitoring.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "server_errors" {
  count = var.create_container_app ? 1 : 0

  name                = "alert-5xx-${module.naming.suffix}"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [module.container_app.container_app_id]
  description         = "The app returned more than 5 server errors in 15 minutes."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "Requests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5

    dimension {
      name     = "statusCodeCategory"
      operator = "Include"
      values   = ["5xx"]
    }
  }

  action {
    action_group_id = module.monitoring.action_group_id
  }
}

# ---------------------------------------------------------------- governance

resource "azurerm_management_lock" "resource_group" {
  count = var.enable_delete_lock ? 1 : 0

  name       = "lock-cannot-delete"
  scope      = azurerm_resource_group.this.id
  lock_level = "CanNotDelete"
  notes      = "Protects the ${var.environment} private container app with database and storage. Remove through change control only."

  depends_on = [module.container_app, module.monitoring, module.postgresql, module.storage, module.key_vault, azapi_resource.sign_in]
}

resource "azurerm_consumption_budget_resource_group" "this" {
  count = var.monthly_budget > 0 ? 1 : 0

  name              = module.naming.budget
  resource_group_id = azurerm_resource_group.this.id
  amount            = var.monthly_budget
  time_grain        = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 80
    threshold_type = "Actual"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = var.budget_contact_emails
    contact_groups = [module.monitoring.action_group_id]
  }

  notification {
    enabled        = true
    threshold      = 100
    threshold_type = "Forecasted"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = var.budget_contact_emails
    contact_groups = [module.monitoring.action_group_id]
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}
```

- [ ] **Step 5: Write `outputs.tf`**

```hcl
output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "container_app_name" {
  value = module.naming.container_app
}

output "app_url" {
  description = "Internal URL. Resolves only on the spoke, the hub and networks that use the hub's DNS."
  value       = var.create_container_app ? "https://${module.container_app.container_app_fqdn}" : null
}

output "registry_login_server" {
  description = "Push images here, e.g. az acr build --registry <name> --image python-crud-app:<tag> content/python-crud-app."
  value       = module.container_app.registry_login_server
}

output "environment_dns" {
  description = "For the hub DNS team: the zone to forward (or link) and the address it resolves to."
  value = {
    zone       = module.container_app.environment_default_domain
    ip_address = module.container_app.environment_static_ip_address
  }
}

output "postgresql_fqdn" {
  value = module.postgresql.fqdn
}

output "storage_account_name" {
  value = module.storage.account_name
}

output "key_vault_id" {
  value = module.key_vault.id
}

output "log_analytics_workspace_id" {
  value = module.monitoring.log_analytics_workspace_id
}
```

- [ ] **Step 6: Verify the whole stack is syntactically valid**

Run:
```bash
cd infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage
terraform init -backend=false
terraform validate
```
Expected: `Success! The configuration is valid.` (fix any typo the copy/append steps introduced before moving on — this is the first point the whole graph is checked together).

- [ ] **Step 7: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage
git commit -m "feat: complete the stack (container app, sign-in, alerts, governance, outputs)"
```

---

## Task 12: terraform test suite

**Files:**
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage/tests/private_app_with_db.tftest.hcl`

**Interfaces:**
- Consumes: the stack from Tasks 9–11; the `dev` tfvars from Task 13 (write Task 13's `terraform.tfvars` first, or supply equivalent `variables {}` blocks inline — this task uses inline variables so it has no ordering dependency on Task 13).

- [ ] **Step 1: Write the test file**

```hcl
# Plans with mocked providers, so no Azure access is needed:
#   terraform test -var-file=../../environments/dev/terraform.tfvars
mock_provider "azurerm" {
  mock_resource "azurerm_container_app" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.App/containerApps/ca-test" }
  }
  mock_resource "azurerm_postgresql_flexible_server" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-test", fqdn = "psql-test.postgres.database.azure.com" }
  }
  mock_resource "azurerm_key_vault" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test" }
  }
}
mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = { object_id = "00000000-0000-0000-0000-0000000000aa" }
  }
}
mock_provider "azapi" {}
mock_provider "time" {}
mock_provider "random" {}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000001"
  tenant_id       = "00000000-0000-0000-0000-000000000000"
  environment     = "dev"
  location        = "westeurope"

  governance_tags = {
    owner               = "test-team"
    cost_centre         = "TEST"
    data_classification = "Internal"
    support             = "test@example.com"
  }

  vnet_address_space               = ["10.61.0.0/24"]
  container_apps_subnet_prefix     = "10.61.0.0/27"
  postgresql_subnet_prefix         = "10.61.0.32/28"
  private_endpoints_subnet_prefix  = "10.61.0.48/28"

  allowed_group_ids   = ["00000000-0000-0000-0000-0000000000bb"]
  postgresql_sku_name = "B_Standard_B1ms"
}

run "first_apply_creates_platform_only" {
  command = plan

  variables {
    create_container_app = false
  }

  assert {
    condition     = module.container_app.container_app_id == null && length(azapi_resource.sign_in) == 0
    error_message = "The app and its sign-in must wait until the first image is in the registry."
  }

  assert {
    condition     = !contains(keys(module.key_vault.secret_ids), "microsoft-provider-authentication-secret")
    error_message = "The Entra client secret cannot exist in Key Vault before the app (and its registration) exist."
  }
}

run "app_is_internal_and_requires_sign_in" {
  command = plan

  variables {
    create_container_app = true
  }

  assert {
    condition     = length(azapi_resource.sign_in) == 1
    error_message = "Entra sign-in must be configured whenever the app exists."
  }

  assert {
    condition     = azapi_resource.sign_in[0].body.properties.globalValidation.unauthenticatedClientAction == "RedirectToLoginPage"
    error_message = "Unauthenticated requests must be sent to the Entra login."
  }
}

run "database_and_storage_are_never_public" {
  command = plan

  assert {
    condition     = module.storage.id != null
    error_message = "Storage account must be created regardless of create_container_app."
  }

  assert {
    condition     = module.postgresql.fqdn != null
    error_message = "PostgreSQL must be created regardless of create_container_app."
  }
}

run "postgresql_ha_needs_non_burstable_sku" {
  command = plan

  variables {
    postgresql_sku_name  = "B_Standard_B1ms"
    postgresql_ha_enabled = true
  }

  expect_failures = [module.postgresql.check.ha_needs_non_burstable_sku]
}

run "registry_zone_redundancy_needs_premium" {
  command = plan

  variables {
    registry_sku                     = "Basic"
    registry_zone_redundancy_enabled = true
  }

  expect_failures = [var.registry_zone_redundancy_enabled]
}

run "zone_redundancy_warns_with_one_replica" {
  command = plan

  variables {
    zone_redundancy_enabled = true
    min_replicas             = 1
  }

  expect_failures = [check.zone_redundancy_has_replicas_to_spread]
}
```

- [ ] **Step 2: Run it and confirm it fails first (sanity: catch a typo before "fixing" nothing)**

Run:
```bash
cd infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage
terraform test
```
Expected on the very first run: either all runs pass, or a failure that's a genuine bug in Tasks 10–11 (e.g. a missing `depends_on`, a wrong secret key) — fix `main.tf`, not the test, unless the test itself has a typo.

- [ ] **Step 3: Fix until green**

Re-run `terraform test` after each fix.
Expected: `Success! N passed, 0 failed.`

- [ ] **Step 4: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage/tests
git commit -m "test: mocked-provider terraform test suite for database/storage stack"
```

---

## Task 13: Environment tfvars and backend.hcl (dev, qa, uat, prod)

**Files:**
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/environments/{dev,qa,uat,prod}/terraform.tfvars`
- Create: same four `backend.hcl`

**Interfaces:**
- Consumes: every variable from Task 9's `variables.tf`.

- [ ] **Step 1: Write `environments/dev/terraform.tfvars`**

```hcl
# DEV environment. Replace every <...> placeholder before the first apply.

subscription_id = "00000000-0000-0000-0000-000000000001" # <dev subscription id>
tenant_id       = "00000000-0000-0000-0000-000000000000" # <tenant id>

environment = "dev"
location    = "westeurope"
workload    = "pcds"
instance    = "001"

governance_tags = {
  owner               = "<owner team>"
  cost_centre         = "<cost centre>"
  data_classification = "Internal"
  support             = "<support group or email>"
}

enable_delete_lock = false
monthly_budget     = 75
budget_contact_emails = [
  # "finance@example.com",
]

# Network: take the ranges from the IP plan; they must not overlap the hub or other spokes.
vnet_address_space              = ["10.61.0.0/24"]
container_apps_subnet_prefix    = "10.61.0.0/27"
postgresql_subnet_prefix        = "10.61.0.32/28"
private_endpoints_subnet_prefix = "10.61.0.48/28"
# dns_servers            = ["<hub DNS resolver IP>"]
# hub_virtual_network_id = "/subscriptions/<hub sub>/resourceGroups/<hub rg>/providers/Microsoft.Network/virtualNetworks/<hub vnet>"
# use_hub_gateway        = true

# Sign-in: only members of these groups can open the app.
allowed_group_ids = [
  "00000000-0000-0000-0000-000000000000", # <entra-group-object-id: app users>
]

# Resilience. Zone redundancy is fixed at creation; the registry needs Premium for it.
zone_redundancy_enabled          = false
registry_sku                     = "Basic"
registry_zone_redundancy_enabled = false

# Database. HA is fixed at creation and needs a non-Burstable sku_name.
postgresql_sku_name                     = "B_Standard_B1ms"
postgresql_storage_mb                   = 32768
postgresql_backup_retention_days        = 7
postgresql_geo_redundant_backup_enabled = false
postgresql_ha_enabled                   = false

# Storage (images).
storage_replication_type = "ZRS"

# Key Vault: Terraform needs data-plane access to write the generated secrets.
# key_vault_allowed_ip_ranges = ["<your public IP>/32"]

# Application. Leave false for the first apply, push the first image, then set true.
create_container_app = false
image_repository     = "python-crud-app"
initial_image_tag    = "initial"
min_replicas          = 1
max_replicas           = 1
app_settings = {
  APP_MAX_UPLOAD_MB = "10"
}
seed_admin_username = "admin"
seed_demo_username  = "demo"

# Monitoring
log_retention_days = 30
alert_email_receivers = [
  # "alerts@example.com",
]
monitoring_viewer_principal_ids = [
  # "<entra-group-object-id: developers>",
]
```

- [ ] **Step 2: Write `environments/dev/backend.hcl`**

```hcl
# Remote state for DEV. Created by infrastructure/privately-accessible-container-app-with-database-and-storage/bootstrap.
subscription_id      = "00000000-0000-0000-0000-000000000001" # <state subscription id>
resource_group_name  = "rg-tfstate-dev"
storage_account_name = "<tfstate storage account>"
container_name       = "tfstate"
key                  = "private-container-app-with-db/dev.tfstate"
use_azuread_auth     = true
```

- [ ] **Step 3: Write `environments/qa/terraform.tfvars`**

Same as dev, with these fields changed:
```hcl
subscription_id = "00000000-0000-0000-0000-000000000002" # <qa subscription id>
environment     = "qa"
monthly_budget  = 100
vnet_address_space              = ["10.61.1.0/24"]
container_apps_subnet_prefix    = "10.61.1.0/27"
postgresql_subnet_prefix        = "10.61.1.32/28"
private_endpoints_subnet_prefix = "10.61.1.48/28"
```
(Keep every other line identical to dev, including `postgresql_ha_enabled = false` and `storage_replication_type = "ZRS"`.)

- [ ] **Step 4: Write `environments/qa/backend.hcl`**

Same as dev's, with `subscription_id` set to `00000000-0000-0000-0000-000000000002`, `resource_group_name = "rg-tfstate-qa"`, `key = "private-container-app-with-db/qa.tfstate"`.

- [ ] **Step 5: Write `environments/uat/terraform.tfvars`**

Same shape as dev, with:
```hcl
subscription_id = "00000000-0000-0000-0000-000000000003" # <uat subscription id>
environment     = "uat"
enable_delete_lock = true
monthly_budget      = 450
vnet_address_space              = ["10.61.2.0/24"]
container_apps_subnet_prefix    = "10.61.2.0/27"
postgresql_subnet_prefix        = "10.61.2.32/28"
private_endpoints_subnet_prefix = "10.61.2.48/28"

zone_redundancy_enabled = true

postgresql_sku_name              = "GP_Standard_D2ds_v5"
postgresql_backup_retention_days = 35
postgresql_geo_redundant_backup_enabled = false
postgresql_ha_enabled   = true
postgresql_ha_mode      = "ZoneRedundant"
postgresql_zone         = "1"
postgresql_standby_zone = "2"

storage_replication_type = "GZRS"
key_vault_purge_protection_enabled = true

min_replicas = 2 # rehearses prod's zone-redundant layout
max_replicas = 2
log_retention_days = 90
```

- [ ] **Step 6: Write `environments/uat/backend.hcl`**

Same as dev's, with `subscription_id = "00000000-0000-0000-0000-000000000003"`, `resource_group_name = "rg-tfstate-uat"`, `key = "private-container-app-with-db/uat.tfstate"`.

- [ ] **Step 7: Write `environments/prod/terraform.tfvars`**

Same shape as uat, with:
```hcl
subscription_id = "00000000-0000-0000-0000-000000000004" # <prod subscription id>
environment     = "prod"
monthly_budget  = 500
vnet_address_space              = ["10.61.3.0/24"]
container_apps_subnet_prefix    = "10.61.3.0/27"
postgresql_subnet_prefix        = "10.61.3.32/28"
private_endpoints_subnet_prefix = "10.61.3.48/28"

postgresql_geo_redundant_backup_enabled = true

log_retention_days = 180
```
(Every other line — `enable_delete_lock`, `zone_redundancy_enabled`, `postgresql_sku_name`, `postgresql_ha_*`, `storage_replication_type`, `key_vault_purge_protection_enabled`, `min_replicas`/`max_replicas` — identical to uat.)

- [ ] **Step 8: Write `environments/prod/backend.hcl`**

Same as dev's, with `subscription_id = "00000000-0000-0000-0000-000000000004"`, `resource_group_name = "rg-tfstate-prod"`, `key = "private-container-app-with-db/prod.tfstate"`.

- [ ] **Step 9: Verify each environment plans (mocked test, not live Azure)**

Run for each environment:
```bash
cd infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage
terraform test -var-file=../../environments/dev/terraform.tfvars
terraform test -var-file=../../environments/qa/terraform.tfvars
terraform test -var-file=../../environments/uat/terraform.tfvars
terraform test -var-file=../../environments/prod/terraform.tfvars
```
Expected: `Success! N passed, 0 failed.` for all four (uat/prod exercise the HA + GZRS branches the dev-only run in Task 12 doesn't reach).

- [ ] **Step 10: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage/environments
git commit -m "feat: dev/qa/uat/prod environment settings for database/storage template"
```

---

## Task 14: Pipeline, fmt/validate across the whole template

**Files:**
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/pipelines/azure-pipelines.yml`

- [ ] **Step 1: Copy and adapt the pipeline**

```bash
cp infrastructure/privately-accessible-container-app/pipelines/azure-pipelines.yml \
   infrastructure/privately-accessible-container-app-with-database-and-storage/pipelines/azure-pipelines.yml
```

Edit the copied file:
- Header comment and variable-group names: replace `private-container-app` with `private-container-app-with-db` throughout.
- `paths: include:` lists: replace `content/python-mvc-app/*` with `content/python-crud-app/*` and `infrastructure/privately-accessible-container-app/pipelines/azure-pipelines.yml` with `infrastructure/privately-accessible-container-app-with-database-and-storage/pipelines/azure-pipelines.yml`.
- `variables.appDirectory`: `content/python-crud-app`.
- `variables.imageRepository`: `python-crud-app`.
- Environment names (`private-container-app-dev`, etc.): `private-container-app-with-db-dev`, etc.

- [ ] **Step 2: Verify the whole template formats and validates cleanly**

Run:
```bash
terraform fmt -recursive infrastructure/privately-accessible-container-app-with-database-and-storage
terraform -chdir=infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage validate
terraform -chdir=infrastructure/privately-accessible-container-app-with-database-and-storage/bootstrap validate
```
Expected: `fmt` reports no changed files (or stages the ones it reformatted); both `validate` calls print `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage/pipelines
git commit -m "feat: delivery pipeline for database/storage template"
```

---

## Task 15: Python app scaffold — db layer, config, Dockerfile, health

**Files:**
- Create: `content/python-crud-app/app/db.py`
- Create: `content/python-crud-app/app/models/current_user.py` (copy unchanged)
- Create: `content/python-crud-app/app/controllers/health_controller.py` (copy unchanged)
- Create: `content/python-crud-app/Dockerfile`, `requirements.txt`, `requirements-dev.txt`, `.dockerignore`, `.gitignore`
- Test: `content/python-crud-app/tests/test_health.py`, `content/python-crud-app/tests/conftest.py`

**Interfaces:**
- Produces: `app.db.Base` (declarative base), `app.db.engine` / `app.db.SessionLocal` (module globals), `app.db.init_engine()` (rebuild them from current env — later tasks and tests call this), `app.db.get_session()`, `app.db.get_engine()`, `app.db.database_url()` — every later task's models/controllers import `get_session`/`get_engine`/`Base`, never `engine`/`SessionLocal` directly (late-binding: see Step 1's docstring).

- [ ] **Step 1: Write `app/db.py`**

```python
"""Database engine and session.

DATABASE_URL, or DB_HOST/DB_USER/DB_PASSWORD/DB_NAME, picks PostgreSQL; with
none of those set, falls back to a SQLite file under APP_DATA_DIR, so local
dev and tests need no database server.

engine/SessionLocal are created once at import time from the environment at
that moment. init_engine() rebuilds them from the *current* environment —
call it before create_app() in any test that changes DATABASE_URL, DB_HOST
or APP_DATA_DIR. Other modules must import get_session()/get_engine(), not
SessionLocal/engine directly: a direct `from app.db import SessionLocal`
binds the name at import time and misses a later init_engine() rebuild,
since Python resolves a name used inside a function body from the module's
current globals, not the value captured at import time.
"""
import os

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, scoped_session, sessionmaker


class Base(DeclarativeBase):
    pass


def database_url() -> str:
    explicit = os.environ.get("DATABASE_URL")
    if explicit:
        return explicit
    host = os.environ.get("DB_HOST")
    if not host:
        data_dir = os.environ.get("APP_DATA_DIR", "/tmp")
        return f"sqlite:///{data_dir}/app.db"
    user = os.environ["DB_USER"]
    password = os.environ["DB_PASSWORD"]
    name = os.environ.get("DB_NAME", "app")
    return f"postgresql+psycopg://{user}:{password}@{host}:5432/{name}?sslmode=require"


def _build():
    engine = create_engine(database_url(), pool_pre_ping=True)
    return engine, scoped_session(sessionmaker(bind=engine, expire_on_commit=False))


engine, SessionLocal = _build()


def init_engine() -> None:
    global engine, SessionLocal
    engine, SessionLocal = _build()


def get_engine():
    return engine


def get_session():
    return SessionLocal()
```

- [ ] **Step 2: Copy `current_user.py` and `health_controller.py` unchanged**

```bash
mkdir -p content/python-crud-app/app/models content/python-crud-app/app/controllers content/python-crud-app/app/static content/python-crud-app/tests
cp content/python-mvc-app/app/models/current_user.py content/python-crud-app/app/models/current_user.py
cp content/python-mvc-app/app/controllers/health_controller.py content/python-crud-app/app/controllers/health_controller.py
touch content/python-crud-app/app/models/__init__.py content/python-crud-app/app/controllers/__init__.py
```

- [ ] **Step 3: Write `requirements.txt`**

```
Flask==3.1.3
gunicorn==26.2.0
azure-monitor-opentelemetry==1.8.10
SQLAlchemy==2.0.36
psycopg[binary]==3.2.3
azure-identity==1.19.0
azure-storage-blob==12.24.0
```

- [ ] **Step 4: Write `requirements-dev.txt`**

```
-r requirements.txt
pytest==9.1.1
```

- [ ] **Step 5: Write `Dockerfile`**

```dockerfile
# Runtime image for the Python CRUD app. No build tools, runs as a non-root user.
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /srv

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app ./app

RUN useradd --create-home --uid 10001 appuser
USER 10001

EXPOSE 8000

# Two workers suit 1 vCPU. Images go to Blob storage, not local disk, so
# nothing written here needs to survive a restart or be shared across replicas.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--timeout", "120", "--access-logfile", "-", "app:create_app()"]
```

- [ ] **Step 6: Copy `.dockerignore` and `.gitignore` unchanged**

```bash
cp content/python-mvc-app/.dockerignore content/python-crud-app/.dockerignore
cp content/python-mvc-app/.gitignore content/python-crud-app/.gitignore
```

- [ ] **Step 7: Write the failing test for the health endpoint**

`content/python-crud-app/tests/conftest.py`:
```python
"""Test fixtures: SQLite database and local-folder image storage, both reset
per test by pointing APP_DATA_DIR at a fresh tmp_path."""
import re

import pytest


@pytest.fixture()
def app(tmp_path, monkeypatch):
    monkeypatch.setenv("APP_DATA_DIR", str(tmp_path))
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.delenv("DB_HOST", raising=False)
    monkeypatch.delenv("AZURE_STORAGE_ACCOUNT_NAME", raising=False)
    monkeypatch.setenv("SEED_ADMIN_USERNAME", "admin")
    monkeypatch.setenv("SEED_ADMIN_PASSWORD", "admin-pass-123")
    monkeypatch.setenv("SEED_DEMO_USERNAME", "demo")
    monkeypatch.setenv("SEED_DEMO_PASSWORD", "demo-pass-123")
    monkeypatch.setenv("APP_ENV", "development")

    from app.db import init_engine
    init_engine()

    from app import create_app
    yield create_app({"TESTING": True})


@pytest.fixture()
def client(app):
    return app.test_client()


def login(client, username, password):
    page = client.get("/login")
    token = _extract_csrf(page.text)
    return client.post(
        "/login",
        data={"username": username, "password": password, "csrf_token": token},
        follow_redirects=True,
    )


def _extract_csrf(html: str) -> str:
    match = re.search(r'name="csrf_token" value="([^"]+)"', html)
    return match.group(1) if match else ""
```

`content/python-crud-app/tests/test_health.py`:
```python
"""The health endpoint stays reachable without signing in."""


def test_healthz_is_public(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}
```

- [ ] **Step 8: Run it to confirm it fails (no `app` package yet)**

Run: `cd content/python-crud-app && pip install -r requirements-dev.txt && python -m pytest tests/test_health.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app'` (there's no `app/__init__.py` yet; Task 16 onward build it up, culminating in Task 21 where this test finally passes as a side effect of the full app factory existing).

- [ ] **Step 9: Commit**

```bash
git add content/python-crud-app
git commit -m "chore: scaffold python-crud-app (db layer, Dockerfile, deps, health test)"
```

---

## Task 16: Data models — User and Asset

**Files:**
- Create: `content/python-crud-app/app/models/user.py`, `content/python-crud-app/app/models/asset.py`

**Interfaces:**
- Consumes: `app.db.Base` (Task 15).
- Produces: `User` (`id`, `username`, `password_hash`, `role`, `failed_login_count`, `locked_until`, `created_at`; methods `set_password`, `check_password`, `is_locked`, property `is_admin`), `ROLE_ADMIN`, `ROLE_USER`, `Asset` (`id`, `name`, `category`, `description`, `image_blob_name`, `owner_user_id`, `created_at`, `updated_at`) — Tasks 17–20 import these directly.

- [ ] **Step 1: Write `app/models/user.py`**

```python
"""User accounts: the app's own login, independent of the Entra layer in
front of it (Container Apps built-in authentication)."""
from __future__ import annotations

import datetime as dt

from sqlalchemy import DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column
from werkzeug.security import check_password_hash, generate_password_hash

from app.db import Base

ROLE_ADMIN = "admin"
ROLE_USER = "user"


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[str] = mapped_column(String(16), nullable=False, default=ROLE_USER)
    failed_login_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    locked_until: Mapped[dt.datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime, nullable=False, default=dt.datetime.utcnow)

    def set_password(self, password: str) -> None:
        self.password_hash = generate_password_hash(password, method="scrypt")

    def check_password(self, password: str) -> bool:
        return check_password_hash(self.password_hash, password)

    def is_locked(self, now: dt.datetime | None = None) -> bool:
        now = now or dt.datetime.utcnow()
        return self.locked_until is not None and self.locked_until > now

    @property
    def is_admin(self) -> bool:
        return self.role == ROLE_ADMIN
```

- [ ] **Step 2: Write `app/models/asset.py`**

```python
"""Asset catalogue: the example CRUD domain. Any signed-in user can view
every asset; only its owner or an admin can change or delete it."""
from __future__ import annotations

import datetime as dt

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class Asset(Base):
    __tablename__ = "assets"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    category: Mapped[str] = mapped_column(String(64), nullable=False, default="")
    description: Mapped[str] = mapped_column(Text, nullable=False, default="")
    image_blob_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    owner_user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), nullable=False)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime, nullable=False, default=dt.datetime.utcnow)
    updated_at: Mapped[dt.datetime] = mapped_column(
        DateTime, nullable=False, default=dt.datetime.utcnow, onupdate=dt.datetime.utcnow
    )
```

- [ ] **Step 3: Verify the models import cleanly**

Run: `cd content/python-crud-app && python -c "from app.models.user import User, ROLE_ADMIN; from app.models.asset import Asset; print('ok')"`
Expected: `ok`

- [ ] **Step 4: Commit**

```bash
git add content/python-crud-app/app/models
git commit -m "feat: User and Asset models"
```

---

## Task 17: Auth — session login, CSRF, lockout

**Files:**
- Create: `content/python-crud-app/app/auth/security.py`, `content/python-crud-app/app/auth/__init__.py` (empty), `content/python-crud-app/app/controllers/auth_controller.py`, `content/python-crud-app/app/views/layout.html`, `content/python-crud-app/app/views/login.html`
- Test: `content/python-crud-app/tests/test_auth.py`

**Interfaces:**
- Consumes: `User`, `ROLE_ADMIN`, `ROLE_USER` (Task 16); `get_session` (Task 15).
- Produces: `log_in(user)`, `log_out()`, `csrf_token()`, `require_csrf(view)`, `login_required(view)`, `admin_required(view)` (all in `app.auth.security`); `auth_blueprint` with routes `GET/POST /login`, `POST /logout` — Tasks 18–20 use the decorators and blueprint name `"auth.login"`/`"auth.logout"` in `url_for`.

- [ ] **Step 1: Write the failing tests**

```python
"""Login, lockout and CSRF behavior for the app's own username/password layer."""
from tests.conftest import login


def test_login_with_correct_credentials_succeeds(client):
    resp = login(client, "admin", "admin-pass-123")
    assert resp.status_code == 200


def test_login_with_wrong_password_fails(client):
    resp = login(client, "admin", "wrong-password")
    assert resp.status_code == 401


def test_repeated_failures_lock_the_account(client):
    for _ in range(5):
        login(client, "admin", "wrong-password")
    resp = login(client, "admin", "admin-pass-123")
    assert resp.status_code == 401
    assert b"Invalid username or password" in resp.data


def test_post_without_csrf_token_is_rejected(client):
    resp = client.post("/login", data={"username": "admin", "password": "admin-pass-123"})
    assert resp.status_code == 400
```

- [ ] **Step 2: Run to confirm it fails**

Run: `cd content/python-crud-app && python -m pytest tests/test_auth.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app'` (still no `app/__init__.py`; that's Task 21).

- [ ] **Step 3: Write `app/auth/security.py`**

```python
"""Session login helpers and a hand-rolled CSRF token (double-submit
cookie): small enough that adding Flask-WTF just for this would be the
wrong trade for a template meant to stay dependency-light."""
import secrets
from functools import wraps

from flask import abort, redirect, request, session, url_for


def log_in(user) -> None:
    session.clear()
    session["user_id"] = user.id
    session["role"] = user.role
    session["csrf_token"] = secrets.token_urlsafe(32)


def log_out() -> None:
    session.clear()


def csrf_token() -> str:
    if "csrf_token" not in session:
        session["csrf_token"] = secrets.token_urlsafe(32)
    return session["csrf_token"]


def require_csrf(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if request.method in ("POST", "PUT", "PATCH", "DELETE"):
            sent = request.form.get("csrf_token", "")
            expected = session.get("csrf_token", "")
            if not sent or not expected or not secrets.compare_digest(sent, expected):
                abort(400, "Invalid or missing CSRF token.")
        return view(*args, **kwargs)

    return wrapped


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if "user_id" not in session:
            return redirect(url_for("auth.login"))
        return view(*args, **kwargs)

    return wrapped


def admin_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if session.get("role") != "admin":
            abort(403)
        return view(*args, **kwargs)

    return wrapped
```

- [ ] **Step 4: Write `app/controllers/auth_controller.py`**

```python
"""Login/logout for the app's own username/password layer — this sits
behind (not instead of) the Entra sign-in Container Apps enforces in front."""
import datetime as dt
import os

from flask import Blueprint, redirect, render_template, request, url_for

from app.auth.security import csrf_token, log_in, log_out, require_csrf
from app.db import get_session
from app.models.user import User

auth_blueprint = Blueprint("auth", __name__)

MAX_FAILED_ATTEMPTS = int(os.environ.get("APP_MAX_FAILED_LOGINS", "5"))
LOCKOUT_MINUTES = int(os.environ.get("APP_LOCKOUT_MINUTES", "15"))


@auth_blueprint.route("/login", methods=["GET", "POST"])
@require_csrf
def login():
    if request.method == "GET":
        return render_template("login.html", csrf_token=csrf_token(), error=None)

    username = request.form.get("username", "").strip()
    password = request.form.get("password", "")
    db = get_session()
    user = db.query(User).filter_by(username=username).one_or_none()

    # Same error for "no such user" and "locked": don't tell an attacker which one it is.
    if user is None or user.is_locked():
        return render_template("login.html", csrf_token=csrf_token(), error="Invalid username or password."), 401

    if user.check_password(password):
        user.failed_login_count = 0
        user.locked_until = None
        db.commit()
        log_in(user)
        return redirect(url_for("assets.list_assets"))

    user.failed_login_count += 1
    if user.failed_login_count >= MAX_FAILED_ATTEMPTS:
        user.locked_until = dt.datetime.utcnow() + dt.timedelta(minutes=LOCKOUT_MINUTES)
    db.commit()
    return render_template("login.html", csrf_token=csrf_token(), error="Invalid username or password."), 401


@auth_blueprint.route("/logout", methods=["POST"])
@require_csrf
def logout():
    log_out()
    return redirect(url_for("auth.login"))
```

- [ ] **Step 5: Write `app/views/layout.html`**

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{% block title %}Asset catalogue{% endblock %}</title>
  <link rel="stylesheet" href="{{ url_for('static', filename='styles.css') }}">
</head>
<body>
  <header class="top">
    <a class="brand" href="{{ url_for('assets.list_assets') if session.get('user_id') else url_for('auth.login') }}">Asset catalogue</a>
    <nav>
      {% if session.get('user_id') %}
        <a href="{{ url_for('assets.list_assets') }}">Assets</a>
        {% if session.get('role') == 'admin' %}
          <a href="{{ url_for('admin.list_users') }}">Users</a>
        {% endif %}
        <form method="post" action="{{ url_for('auth.logout') }}" class="inline">
          <input type="hidden" name="csrf_token" value="{{ session.get('csrf_token', '') }}">
          <button type="submit">Log out</button>
        </form>
      {% endif %}
    </nav>
  </header>
  <main>
    {% block content %}{% endblock %}
  </main>
</body>
</html>
```

- [ ] **Step 6: Write `app/views/login.html`**

```html
{% extends "layout.html" %}
{% block content %}
<h1>Sign in</h1>
{% if error %}<p class="error" role="alert">{{ error }}</p>{% endif %}
<form method="post">
  <input type="hidden" name="csrf_token" value="{{ csrf_token }}">
  <label for="username">Username</label>
  <input id="username" type="text" name="username" required autofocus>
  <label for="password">Password</label>
  <input id="password" type="password" name="password" required>
  <button type="submit">Sign in</button>
</form>
{% endblock %}
```

- [ ] **Step 7: Run the tests — still failing on the missing app factory**

Run: `cd content/python-crud-app && python -m pytest tests/test_auth.py tests/test_health.py -v`
Expected: still FAIL with `ModuleNotFoundError: No module named 'app'` — the factory (Task 21) is what finally wires blueprints together; this task and the next three build the pieces it assembles. Continue to Task 18.

- [ ] **Step 8: Commit**

```bash
git add content/python-crud-app/app/auth content/python-crud-app/app/controllers/auth_controller.py content/python-crud-app/app/views/layout.html content/python-crud-app/app/views/login.html content/python-crud-app/tests/test_auth.py
git commit -m "feat: session login, CSRF and lockout"
```

---

## Task 18: Seed users

**Files:**
- Create: `content/python-crud-app/app/seed.py`

**Interfaces:**
- Consumes: `get_session`, `get_engine` (Task 15); `User`, `ROLE_ADMIN`, `ROLE_USER` (Task 16).
- Produces: `seed_users()` — Task 21's `create_app()` calls it once at startup.

- [ ] **Step 1: Write `app/seed.py`**

```python
"""Create the seed admin/demo users on startup, once. A Postgres advisory
lock stops two replicas racing to insert the same username; SQLite
(single-process dev/test) has no such race, so the lock is skipped there."""
import os

from sqlalchemy import text

from app.db import get_engine, get_session
from app.models.user import ROLE_ADMIN, ROLE_USER, User

SEED_LOCK_KEY = 823714  # arbitrary constant, unique to this app's seeding step


def seed_users() -> None:
    db = get_session()
    is_postgres = get_engine().dialect.name == "postgresql"
    if is_postgres:
        db.execute(text("SELECT pg_advisory_lock(:key)"), {"key": SEED_LOCK_KEY})
    try:
        _create_if_missing(db, os.environ.get("SEED_ADMIN_USERNAME", "admin"), os.environ.get("SEED_ADMIN_PASSWORD"), ROLE_ADMIN)
        _create_if_missing(db, os.environ.get("SEED_DEMO_USERNAME", "demo"), os.environ.get("SEED_DEMO_PASSWORD"), ROLE_USER)
    finally:
        if is_postgres:
            db.execute(text("SELECT pg_advisory_unlock(:key)"), {"key": SEED_LOCK_KEY})
        db.commit()


def _create_if_missing(db, username: str, password: str | None, role: str) -> None:
    if not password or db.query(User).filter_by(username=username).one_or_none():
        return
    user = User(username=username, role=role)
    user.set_password(password)
    db.add(user)
    db.commit()
```

- [ ] **Step 2: Add the idempotency test (this task's own review-focus check: seeding twice must not duplicate or error)**

`content/python-crud-app/tests/test_seed.py`:
```python
"""Seeding must be safe to run more than once (mirrors two replicas starting
together and both calling seed_users() before either commits)."""
from app.db import Base, get_engine, get_session
from app.models.user import User
from app.seed import seed_users


def test_seeding_twice_creates_each_user_once(app):
    seed_users()  # conftest's app fixture already seeded once; seed again explicitly
    db = get_session()
    admins = db.query(User).filter_by(username="admin").all()
    assert len(admins) == 1
```

- [ ] **Step 3: Run it to confirm the setup is right (should already pass, since it's exercising Task 15's `init_engine` + this task's idempotent insert — a green first run here still counts as the TDD cycle, since the assertion is what's new)**

Run: `cd content/python-crud-app && python -m pytest tests/test_seed.py -v`
Expected: still FAIL with `ModuleNotFoundError: No module named 'app'` until Task 21 exists — same as the other controller tests. Move on; Task 21 makes this and every earlier test's `client`/`app` fixture resolve.

- [ ] **Step 4: Commit**

```bash
git add content/python-crud-app/app/seed.py content/python-crud-app/tests/test_seed.py
git commit -m "feat: seed admin/demo users with an advisory-lock guard"
```

---

## Task 19: Asset CRUD, image upload/serving, storage helper

**Files:**
- Create: `content/python-crud-app/app/uploads.py`, `content/python-crud-app/app/storage.py`, `content/python-crud-app/app/controllers/asset_controller.py`
- Create: `content/python-crud-app/app/views/assets/list.html`, `content/python-crud-app/app/views/assets/form.html`, `content/python-crud-app/app/views/error.html`
- Test: `content/python-crud-app/tests/test_assets.py`

**Interfaces:**
- Consumes: `Asset` (Task 16); `login_required`, `require_csrf`, `csrf_token` (Task 17); `get_session` (Task 15).
- Produces: `sniff_image_content_type(head: bytes) -> str | None` (`app.uploads`); `save_image`, `load_image`, `delete_image` (`app.storage`); `assets_blueprint` with routes `GET /assets/`, `GET/POST /assets/new`, `GET/POST /assets/<id>/edit`, `POST /assets/<id>/delete`, `GET /assets/<id>/image` — Task 20's admin templates and Task 21's factory reference `"assets.list_assets"`.

- [ ] **Step 1: Write the failing tests**

```python
"""Asset CRUD: any signed-in user can view every asset; only the owner or an
admin can change or delete one."""
import io
import re

from tests.conftest import login


def _csrf_from(page) -> str:
    return re.search(r'name="csrf_token" value="([^"]+)"', page.text).group(1)


def test_owner_can_create_and_see_their_asset(client):
    login(client, "demo", "demo-pass-123")
    token = _csrf_from(client.get("/assets/new"))
    resp = client.post(
        "/assets/new",
        data={"name": "Drill", "category": "Tools", "description": "Cordless", "csrf_token": token},
        follow_redirects=True,
    )
    assert resp.status_code == 200
    assert b"Drill" in resp.data


def test_another_user_cannot_edit_someone_elses_asset(client):
    login(client, "demo", "demo-pass-123")
    token = _csrf_from(client.get("/assets/new"))
    client.post("/assets/new", data={"name": "Drill", "csrf_token": token}, follow_redirects=True)
    client.post("/logout", data={"csrf_token": token})

    from app.db import get_session
    from app.models.user import ROLE_USER, User
    db = get_session()
    other = User(username="other", role=ROLE_USER)
    other.set_password("other-pass-123")
    db.add(other)
    db.commit()

    login(client, "other", "other-pass-123")
    resp = client.get("/assets/1/edit")
    assert resp.status_code == 403


def test_uploading_a_non_image_file_is_rejected(client):
    login(client, "demo", "demo-pass-123")
    token = _csrf_from(client.get("/assets/new"))
    resp = client.post(
        "/assets/new",
        data={"name": "Bad upload", "csrf_token": token, "image": (io.BytesIO(b"not an image"), "file.txt")},
        content_type="multipart/form-data",
    )
    assert resp.status_code == 400
    assert b"JPEG" in resp.data


def test_missing_asset_image_is_404(client):
    login(client, "demo", "demo-pass-123")
    resp = client.get("/assets/999/image")
    assert resp.status_code == 404
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd content/python-crud-app && python -m pytest tests/test_assets.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app'`.

- [ ] **Step 3: Write `app/uploads.py`**

```python
"""Content-sniffing for uploaded images: never trust a file extension or the
browser-supplied Content-Type, both are attacker-controlled."""


def sniff_image_content_type(head: bytes) -> str | None:
    if head.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "image/webp"
    return None
```

- [ ] **Step 4: Write `app/storage.py`**

```python
"""Image storage: Azure Blob Storage with the app's managed identity in
Azure, a local folder when no storage account is configured (tests, local
dev)."""
import os
import uuid
from pathlib import Path


def _local_dir() -> Path:
    return Path(os.environ.get("APP_DATA_DIR", "/tmp")) / "images"


def _account_url() -> str | None:
    name = os.environ.get("AZURE_STORAGE_ACCOUNT_NAME")
    return f"https://{name}.blob.core.windows.net" if name else None


def _container_client():
    from azure.identity import DefaultAzureCredential
    from azure.storage.blob import BlobServiceClient

    service = BlobServiceClient(account_url=_account_url(), credential=DefaultAzureCredential())
    return service.get_container_client(os.environ.get("AZURE_STORAGE_CONTAINER", "images"))


def save_image(file_storage) -> str:
    """Stores the uploaded file, returns the blob name to keep on the Asset row."""
    blob_name = f"{uuid.uuid4().hex}-{file_storage.filename}"
    data = file_storage.read()
    if _account_url():
        _container_client().upload_blob(blob_name, data, overwrite=True)
    else:
        local_dir = _local_dir()
        local_dir.mkdir(parents=True, exist_ok=True)
        (local_dir / blob_name).write_bytes(data)
    return blob_name


def load_image(blob_name: str) -> bytes | None:
    if _account_url():
        try:
            return _container_client().download_blob(blob_name).readall()
        except Exception:
            return None
    path = _local_dir() / blob_name
    return path.read_bytes() if path.exists() else None


def delete_image(blob_name: str) -> None:
    if _account_url():
        try:
            _container_client().delete_blob(blob_name)
        except Exception:
            pass
    else:
        (_local_dir() / blob_name).unlink(missing_ok=True)
```

- [ ] **Step 5: Write `app/controllers/asset_controller.py`**

```python
"""Asset catalogue: list/search (any signed-in user), create/edit/delete
(owner or admin), and the image stream route."""
from flask import Blueprint, Response, abort, redirect, render_template, request, session, url_for

from app.auth.security import csrf_token, login_required, require_csrf
from app.db import get_session
from app.models.asset import Asset
from app.storage import delete_image, load_image, save_image
from app.uploads import sniff_image_content_type

assets_blueprint = Blueprint("assets", __name__, url_prefix="/assets")

MAX_IMAGE_BYTES = 5 * 1024 * 1024


@assets_blueprint.route("/")
@login_required
def list_assets():
    db = get_session()
    q = request.args.get("q", "").strip()
    query = db.query(Asset)
    if q:
        like = f"%{q}%"
        query = query.filter((Asset.name.ilike(like)) | (Asset.category.ilike(like)))
    assets = query.order_by(Asset.created_at.desc()).all()
    return render_template(
        "assets/list.html",
        assets=assets,
        q=q,
        user_id=session["user_id"],
        is_admin=session.get("role") == "admin",
    )


@assets_blueprint.route("/new", methods=["GET", "POST"])
@login_required
@require_csrf
def new_asset():
    if request.method == "GET":
        return render_template("assets/form.html", asset=None, csrf_token=csrf_token(), error=None)

    error = _validate_upload()
    if error:
        return render_template("assets/form.html", asset=None, csrf_token=csrf_token(), error=error), 400

    db = get_session()
    asset = Asset(
        name=request.form["name"].strip(),
        category=request.form.get("category", "").strip(),
        description=request.form.get("description", "").strip(),
        owner_user_id=session["user_id"],
    )
    image = request.files.get("image")
    if image and image.filename:
        asset.image_blob_name = save_image(image)
    db.add(asset)
    db.commit()
    return redirect(url_for("assets.list_assets"))


@assets_blueprint.route("/<int:asset_id>/edit", methods=["GET", "POST"])
@login_required
@require_csrf
def edit_asset(asset_id: int):
    db = get_session()
    asset = db.get(Asset, asset_id)
    if asset is None:
        abort(404)
    _require_owner_or_admin(asset)

    if request.method == "GET":
        return render_template("assets/form.html", asset=asset, csrf_token=csrf_token(), error=None)

    error = _validate_upload()
    if error:
        return render_template("assets/form.html", asset=asset, csrf_token=csrf_token(), error=error), 400

    asset.name = request.form["name"].strip()
    asset.category = request.form.get("category", "").strip()
    asset.description = request.form.get("description", "").strip()
    image = request.files.get("image")
    if image and image.filename:
        if asset.image_blob_name:
            delete_image(asset.image_blob_name)
        asset.image_blob_name = save_image(image)
    db.commit()
    return redirect(url_for("assets.list_assets"))


@assets_blueprint.route("/<int:asset_id>/delete", methods=["POST"])
@login_required
@require_csrf
def delete_asset(asset_id: int):
    db = get_session()
    asset = db.get(Asset, asset_id)
    if asset is None:
        abort(404)
    _require_owner_or_admin(asset)
    if asset.image_blob_name:
        delete_image(asset.image_blob_name)
    db.delete(asset)
    db.commit()
    return redirect(url_for("assets.list_assets"))


@assets_blueprint.route("/<int:asset_id>/image")
@login_required
def asset_image(asset_id: int):
    db = get_session()
    asset = db.get(Asset, asset_id)
    if asset is None or not asset.image_blob_name:
        abort(404)
    data = load_image(asset.image_blob_name)
    if data is None:
        abort(404)
    content_type = sniff_image_content_type(data[:12]) or "application/octet-stream"
    return Response(data, mimetype=content_type)


def _require_owner_or_admin(asset: Asset) -> None:
    if session.get("role") != "admin" and asset.owner_user_id != session["user_id"]:
        abort(403)


def _validate_upload() -> str | None:
    if not request.form.get("name", "").strip():
        return "Name is required."
    image = request.files.get("image")
    if image and image.filename:
        head = image.stream.read(12)
        image.stream.seek(0)
        if sniff_image_content_type(head) is None:
            return "Image must be a JPEG, PNG or WebP file."
        image.stream.seek(0, 2)
        size = image.stream.tell()
        image.stream.seek(0)
        if size > MAX_IMAGE_BYTES:
            return "Image must be 5 MB or smaller."
    return None
```

- [ ] **Step 6: Write the templates**

`content/python-crud-app/app/views/assets/list.html`:
```html
{% extends "layout.html" %}
{% block content %}
<h1>Assets</h1>
<form method="get">
  <input type="search" name="q" value="{{ q }}" placeholder="Search name or category">
  <button type="submit">Search</button>
</form>
<p><a href="{{ url_for('assets.new_asset') }}">New asset</a></p>
<ul class="assets">
  {% for asset in assets %}
  <li>
    {% if asset.image_blob_name %}
      <img src="{{ url_for('assets.asset_image', asset_id=asset.id) }}" alt="{{ asset.name }}" width="120">
    {% endif %}
    <h2>{{ asset.name }}</h2>
    <p class="lede">{{ asset.category }}</p>
    <p>{{ asset.description }}</p>
    {% if is_admin or asset.owner_user_id == user_id %}
      <a href="{{ url_for('assets.edit_asset', asset_id=asset.id) }}">Edit</a>
      <form method="post" action="{{ url_for('assets.delete_asset', asset_id=asset.id) }}" class="inline">
        <input type="hidden" name="csrf_token" value="{{ session.get('csrf_token', '') }}">
        <button type="submit">Delete</button>
      </form>
    {% endif %}
  </li>
  {% else %}
  <li>No assets yet.</li>
  {% endfor %}
</ul>
{% endblock %}
```

`content/python-crud-app/app/views/assets/form.html`:
```html
{% extends "layout.html" %}
{% block content %}
<h1>{{ 'Edit asset' if asset else 'New asset' }}</h1>
{% if error %}<p class="error" role="alert">{{ error }}</p>{% endif %}
<form method="post" enctype="multipart/form-data">
  <input type="hidden" name="csrf_token" value="{{ csrf_token }}">
  <label for="name">Name</label>
  <input id="name" type="text" name="name" value="{{ asset.name if asset else '' }}" required>

  <label for="category">Category</label>
  <input id="category" type="text" name="category" value="{{ asset.category if asset else '' }}">

  <label for="description">Description</label>
  <textarea id="description" name="description">{{ asset.description if asset else '' }}</textarea>

  <label for="image">Image (JPEG, PNG or WebP)</label>
  <input id="image" type="file" name="image" accept="image/jpeg,image/png,image/webp">

  <button type="submit">Save</button>
</form>
{% endblock %}
```

`content/python-crud-app/app/views/error.html`:
```html
{% extends "layout.html" %}
{% block content %}
<h1>Something went wrong</h1>
<p class="error" role="alert">{{ message }}</p>
<p><a href="{{ url_for('assets.list_assets') }}">Back to assets</a></p>
{% endblock %}
```

- [ ] **Step 7: Run — still blocked on the missing factory**

Run: `cd content/python-crud-app && python -m pytest tests/test_assets.py -v`
Expected: still FAIL with `ModuleNotFoundError: No module named 'app'`. Continue to Task 20.

- [ ] **Step 8: Commit**

```bash
git add content/python-crud-app/app/uploads.py content/python-crud-app/app/storage.py content/python-crud-app/app/controllers/asset_controller.py content/python-crud-app/app/views/assets content/python-crud-app/app/views/error.html content/python-crud-app/tests/test_assets.py
git commit -m "feat: asset CRUD, image upload validation, blob storage helper"
```

---

## Task 20: Admin user management

**Files:**
- Create: `content/python-crud-app/app/controllers/admin_controller.py`, `content/python-crud-app/app/views/admin/users.html`
- Test: `content/python-crud-app/tests/test_admin.py`

**Interfaces:**
- Consumes: `User`, `ROLE_ADMIN`, `ROLE_USER` (Task 16); `login_required`, `admin_required`, `require_csrf`, `csrf_token` (Task 17); `get_session` (Task 15).
- Produces: `admin_blueprint` with routes `GET /admin/users`, `POST /admin/users/new`, `POST /admin/users/<id>/reset-password`, `POST /admin/users/<id>/delete` — Task 21's factory registers it.

- [ ] **Step 1: Write the failing tests**

```python
"""Admin-only user management, and that non-admins are refused."""
import re

from tests.conftest import login


def _csrf_from(page) -> str:
    return re.search(r'name="csrf_token" value="([^"]+)"', page.text).group(1)


def test_non_admin_cannot_reach_user_management(client):
    login(client, "demo", "demo-pass-123")
    resp = client.get("/admin/users")
    assert resp.status_code == 403


def test_admin_can_create_and_delete_a_user(client):
    login(client, "admin", "admin-pass-123")
    token = _csrf_from(client.get("/admin/users"))

    client.post("/admin/users/new", data={"username": "temp", "password": "temp-pass-123", "role": "user", "csrf_token": token})
    page = client.get("/admin/users")
    assert b"temp" in page.data

    from app.db import get_session
    from app.models.user import User
    db = get_session()
    temp = db.query(User).filter_by(username="temp").one()
    client.post(f"/admin/users/{temp.id}/delete", data={"csrf_token": token})
    page = client.get("/admin/users")
    assert b">temp<" not in page.data


def test_admin_cannot_delete_themselves(client):
    login(client, "admin", "admin-pass-123")
    token = _csrf_from(client.get("/admin/users"))
    from app.db import get_session
    from app.models.user import User
    db = get_session()
    admin = db.query(User).filter_by(username="admin").one()
    resp = client.post(f"/admin/users/{admin.id}/delete", data={"csrf_token": token})
    assert resp.status_code == 400
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd content/python-crud-app && python -m pytest tests/test_admin.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app'`.

- [ ] **Step 3: Write `app/controllers/admin_controller.py`**

```python
"""Admin-only user management: list, create, reset password, delete
(never yourself)."""
from flask import Blueprint, abort, redirect, render_template, request, session, url_for

from app.auth.security import admin_required, csrf_token, login_required, require_csrf
from app.db import get_session
from app.models.user import ROLE_ADMIN, ROLE_USER, User

admin_blueprint = Blueprint("admin", __name__, url_prefix="/admin")


@admin_blueprint.route("/users")
@login_required
@admin_required
def list_users():
    db = get_session()
    users = db.query(User).order_by(User.username).all()
    return render_template("admin/users.html", users=users, csrf_token=csrf_token(), error=None)


@admin_blueprint.route("/users/new", methods=["POST"])
@login_required
@admin_required
@require_csrf
def create_user():
    db = get_session()
    username = request.form.get("username", "").strip()
    password = request.form.get("password", "")
    role = request.form.get("role", ROLE_USER)
    if role not in (ROLE_ADMIN, ROLE_USER):
        abort(400)
    if not username or not password or db.query(User).filter_by(username=username).one_or_none():
        return redirect(url_for("admin.list_users"))
    user = User(username=username, role=role)
    user.set_password(password)
    db.add(user)
    db.commit()
    return redirect(url_for("admin.list_users"))


@admin_blueprint.route("/users/<int:user_id>/reset-password", methods=["POST"])
@login_required
@admin_required
@require_csrf
def reset_password(user_id: int):
    db = get_session()
    user = db.get(User, user_id)
    if user is None:
        abort(404)
    new_password = request.form.get("password", "")
    if new_password:
        user.set_password(new_password)
        user.failed_login_count = 0
        user.locked_until = None
        db.commit()
    return redirect(url_for("admin.list_users"))


@admin_blueprint.route("/users/<int:user_id>/delete", methods=["POST"])
@login_required
@admin_required
@require_csrf
def delete_user(user_id: int):
    if user_id == session["user_id"]:
        abort(400)
    db = get_session()
    user = db.get(User, user_id)
    if user is None:
        abort(404)
    db.delete(user)
    db.commit()
    return redirect(url_for("admin.list_users"))
```

- [ ] **Step 4: Write `app/views/admin/users.html`**

```html
{% extends "layout.html" %}
{% block content %}
<h1>Users</h1>
{% if error %}<p class="error" role="alert">{{ error }}</p>{% endif %}
<table>
  <tr><th>Username</th><th>Role</th><th>Locked</th><th>Actions</th></tr>
  {% for u in users %}
  <tr>
    <td>{{ u.username }}</td>
    <td>{{ u.role }}</td>
    <td>{{ 'yes' if u.is_locked() else 'no' }}</td>
    <td>
      <form method="post" action="{{ url_for('admin.reset_password', user_id=u.id) }}" class="inline">
        <input type="hidden" name="csrf_token" value="{{ csrf_token }}">
        <input type="password" name="password" placeholder="new password" required>
        <button type="submit">Reset password</button>
      </form>
      {% if u.id != session.get('user_id') %}
      <form method="post" action="{{ url_for('admin.delete_user', user_id=u.id) }}" class="inline">
        <input type="hidden" name="csrf_token" value="{{ csrf_token }}">
        <button type="submit">Delete</button>
      </form>
      {% endif %}
    </td>
  </tr>
  {% endfor %}
</table>
<h2>New user</h2>
<form method="post" action="{{ url_for('admin.create_user') }}">
  <input type="hidden" name="csrf_token" value="{{ csrf_token }}">
  <label for="new-username">Username</label>
  <input id="new-username" type="text" name="username" required>
  <label for="new-password">Password</label>
  <input id="new-password" type="password" name="password" required>
  <label for="new-role">Role</label>
  <select id="new-role" name="role">
    <option value="user">user</option>
    <option value="admin">admin</option>
  </select>
  <button type="submit">Create</button>
</form>
{% endblock %}
```

- [ ] **Step 5: Run — still blocked on the missing factory**

Run: `cd content/python-crud-app && python -m pytest tests/test_admin.py -v`
Expected: still FAIL with `ModuleNotFoundError: No module named 'app'`. Task 21 closes this out.

- [ ] **Step 6: Commit**

```bash
git add content/python-crud-app/app/controllers/admin_controller.py content/python-crud-app/app/views/admin content/python-crud-app/tests/test_admin.py
git commit -m "feat: admin user management"
```

---

## Task 21: Application factory — wire it all together

**Files:**
- Create: `content/python-crud-app/app/__init__.py`
- Modify: `content/python-crud-app/app/static/styles.css` (copy from source, append)

**Interfaces:**
- Consumes: every blueprint from Tasks 17–20 (`auth_blueprint`, `assets_blueprint`, `admin_blueprint`, `health_blueprint`), `Base`/`get_engine`/`init_engine` (Task 15), `seed_users` (Task 18).
- Produces: `create_app(test_config: dict | None = None) -> Flask` — this is what every test's `conftest.py` fixture calls, and what the Dockerfile's `CMD` calls as `app:create_app()`.

- [ ] **Step 1: Write `app/__init__.py`**

```python
"""Application factory: wires configuration, the database, logging, seeding
and the controllers together."""
import logging
import os

from flask import Flask, abort, render_template, request, session

from app.controllers.admin_controller import admin_blueprint
from app.controllers.asset_controller import assets_blueprint
from app.controllers.auth_controller import auth_blueprint
from app.controllers.health_controller import health_blueprint
from app.db import Base, SessionLocal, get_engine
from app.seed import seed_users

MEGABYTE = 1024 * 1024


def create_app(test_config: dict | None = None) -> Flask:
    app = Flask(__name__, template_folder="views")
    app.config.update(
        MAX_CONTENT_LENGTH=int(os.environ.get("APP_MAX_UPLOAD_MB", "10")) * MEGABYTE,
        SECRET_KEY=os.environ.get("APP_SECRET_KEY") or os.urandom(32),
        SESSION_COOKIE_SECURE=os.environ.get("APP_ENV", "production") != "development",
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
    )
    if test_config:
        app.config.update(test_config)

    configure_logging()

    Base.metadata.create_all(bind=get_engine())
    seed_users()

    app.register_blueprint(auth_blueprint)
    app.register_blueprint(assets_blueprint)
    app.register_blueprint(admin_blueprint)
    app.register_blueprint(health_blueprint)

    @app.before_request
    def require_platform_identity():
        # Container Apps built-in auth already refuses unauthenticated
        # requests before they reach the app; this header check is
        # defense-in-depth so the app never trusts network position alone.
        if app.config.get("TESTING"):
            return
        if request.path == "/healthz" or request.path.startswith("/static/"):
            return
        if not request.headers.get("X-MS-CLIENT-PRINCIPAL-NAME"):
            abort(401)

    @app.teardown_appcontext
    def remove_session(_exc=None):
        SessionLocal.remove()

    @app.errorhandler(413)
    def upload_too_large(_error):
        limit_mb = app.config["MAX_CONTENT_LENGTH"] // MEGABYTE
        return render_template("error.html", message=f"The file is larger than {limit_mb} MB."), 413

    @app.errorhandler(403)
    def forbidden(_error):
        return render_template("error.html", message="You don't have permission to do that."), 403

    @app.context_processor
    def inject_role():
        return {"current_role": session.get("role")}

    return app


def configure_logging() -> None:
    logging.basicConfig(level=os.environ.get("APP_LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(name)s %(message)s")
    if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
        from azure.monitor.opentelemetry import configure_azure_monitor

        configure_azure_monitor(logger_name="app")
```

- [ ] **Step 2: Copy and extend the stylesheet**

```bash
cp content/python-mvc-app/app/static/styles.css content/python-crud-app/app/static/styles.css
```

Append:
```css
.inline { display: inline; margin: 0; padding: 0; border: 0; background: none; }
nav { display: flex; gap: 12px; align-items: center; }
table { width: 100%; border-collapse: collapse; margin: 16px 0; }
td, th { padding: 8px; border-bottom: 1px solid var(--line); text-align: left; }
.assets { list-style: none; padding: 0; display: grid; gap: 16px; margin: 16px 0; }
.assets li { background: #fff; border: 1px solid var(--line); border-radius: 8px; padding: 16px; }
```

- [ ] **Step 3: Run the full test suite — this is where every earlier test finally goes green**

Run: `cd content/python-crud-app && python -m pytest -v`
Expected: `PASSED` for every test written in Tasks 15, 17, 18, 19, 20 (health, auth, seed, assets, admin). Fix whatever the wiring step surfaces (a missing `__init__.py` in a package directory is the most likely miss — add empty `app/auth/__init__.py`, `app/views/__init__.py` is not needed since `views` is a template folder, not a package).

- [ ] **Step 4: Commit**

```bash
git add content/python-crud-app/app/__init__.py content/python-crud-app/app/static/styles.css
git commit -m "feat: application factory — wires auth, assets, admin, seeding together"
```

---

## Task 22: App README

**Files:**
- Create: `content/python-crud-app/README.md`

- [ ] **Step 1: Write it**

```markdown
# python-crud-app

A Flask CRUD example for the `privately-accessible-container-app-with-database-and-storage`
golden template: an asset catalogue with its own username/password login,
layered behind the Container Apps Entra sign-in the infrastructure template
enforces in front.

## Running locally

No database or storage account needed — with `DATABASE_URL`/`DB_HOST` and
`AZURE_STORAGE_ACCOUNT_NAME` unset, the app uses a SQLite file and a local
folder under `APP_DATA_DIR` (defaults to `/tmp`).

```
pip install -r requirements-dev.txt
export SEED_ADMIN_PASSWORD=change-me APP_ENV=development
python -m flask --app app run
```

Sign in at `/login` as `admin` / `change-me`. The Entra header check in
`app/__init__.py` is skipped when `APP_ENV=development`.

## Tests

```
pip install -r requirements-dev.txt
pytest
```

## Environment variables

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` or `DB_HOST`/`DB_USER`/`DB_PASSWORD`/`DB_NAME` | PostgreSQL connection. Unset falls back to SQLite. |
| `AZURE_STORAGE_ACCOUNT_NAME` / `AZURE_STORAGE_CONTAINER` | Blob storage for images. Unset falls back to a local folder. |
| `APP_SECRET_KEY` | Flask session signing key. |
| `SEED_ADMIN_USERNAME` / `SEED_ADMIN_PASSWORD` / `SEED_DEMO_USERNAME` / `SEED_DEMO_PASSWORD` | Seed users created on first startup if missing. |
| `APP_MAX_FAILED_LOGINS` / `APP_LOCKOUT_MINUTES` | Login lockout (defaults 5 / 15). |
| `APP_MAX_UPLOAD_MB` | Upload size limit (default 10). |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Optional: OpenTelemetry export. |
| `APP_ENV=development` | Skips the Entra-header check so the app runs outside a Container App. |
```

- [ ] **Step 2: Commit**

```bash
git add content/python-crud-app/README.md
git commit -m "docs: python-crud-app README"
```

---

## Task 23: Template README (design decisions, cost), ARCHITECTURE.md, C4 diagrams

**Files:**
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/README.md`
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/ARCHITECTURE.md`
- Create: `infrastructure/privately-accessible-container-app-with-database-and-storage/c4-context.drawio`, `c4-containers.drawio`

- [ ] **Step 1: Write `README.md`**

Base it on `infrastructure/privately-accessible-container-app/README.md`'s structure (Design decisions table, Cost estimate, Folder layout, First-time setup, Delivering new versions). Reuse every row that still applies unchanged (Region, Availability zones for the Container Apps environment, Subnets, Hosting, Internal URL, Sign-in, Image, Logging, Scale, Governance) and add these new rows to `## Design decisions`:

| Concern | Decision | Why | Trade-off |
| --- | --- | --- | --- |
| App login | The Flask app has its own username/password login (session cookie, lockout after 5 failed attempts) behind the existing Entra sign-in | The request needs app-level credentials and roles (admin/user), not just network-position trust; Entra keeps outsiders out first | Two sign-ins for every user; the app now owns a password database it must hash and lock out correctly |
| Database | Azure Database for PostgreSQL Flexible Server, VNet-integrated, no public network access. `postgresql_ha_enabled` off in dev/qa, zone-redundant HA in uat/prod (needs a General Purpose/Memory Optimized SKU) | VNet integration keeps the database off the internet entirely; HA in uat/prod rehearses and covers a zone failure | Zone-redundant HA needs a non-Burstable SKU (about 10x a Burstable instance's cost) and doubles compute cost while it's on |
| Database credential | One administrator credential, generated by Terraform and stored in Key Vault, used by both Terraform and the app | Avoids a second Terraform provider (and the network path it would need into a private-only server) just to create a second, more restricted role | Not least-privilege: the app connects with the same credential Terraform uses to create the database. Acceptable because nothing else connects to this server; add a scoped role if that changes |
| Secrets | Terraform generates the DB password, Flask session key and seed users' passwords with `random_password` and writes them to a dedicated Key Vault (RBAC, private endpoint, no public access by default). The container app reads them as Key Vault-referenced secrets through its managed identity | Nothing sensitive sits in `terraform.tfvars` or the container image; rotation is a Terraform re-apply | Terraform's own write to the vault needs `key_vault_allowed_ip_ranges` opened during apply, or a self-hosted agent inside the spoke — the vault can't be both "write-only from Terraform" and "no public access at all" on the very first apply |
| Images | Blob storage, private endpoint only, `shared_access_key_enabled = false` — the app reads and writes with its managed identity, never an account key. Replication is `storage_replication_type` (ZRS dev/qa, GZRS uat/prod) | No storage key to leak or rotate; matches the "storage redundancy is always a variable" rule | The role assignment (Storage Blob Data Contributor) is scoped to the whole account, not just the `images` container — the built-in role doesn't support container-level scoping |

Append to `## Availability zones` reasoning (or add a note) that PostgreSQL HA and Blob replication are now the two additional zonal knobs, both off by default in dev/qa and on in uat/prod, matching the Container Apps environment's own `zone_redundancy_enabled`.

- [ ] **Step 2: Write the Cost estimate section**

Reuse the source template's Container Apps/Registry/DNS/alerts/monitoring numbers (they don't change) and add these rows, sourced from the Azure Retail Prices API for West Europe, retrieved 2026-09-28:

| Item | Price used | Dev/QA monthly | UAT/Prod monthly |
| --- | --- | --- | --- |
| PostgreSQL compute | Burstable B1ms $0.0199/hr, or General Purpose D2ds_v5 $0.212/hr × 2 (zone-redundant HA) | ~$14.53 | ~$309.52 |
| PostgreSQL storage | Premium SSD $0.1369/GiB-month, 32 GiB | ~$4.38 | ~$4.38+ |
| PostgreSQL backup storage | LRS $0.103/GiB-month (dev/qa); geo-redundant backup roughly doubles it in prod | ~$1–3 | ~$3–8 |
| Key Vault | Standard, $0.03 per 10K operations | <$1 | <$1 |
| Blob storage (images) | Hot LRS $0.0196/GiB-month (dev/qa), Hot GZRS ~$0.046/GiB-month (uat/prod); a few GiB of images | <$1 | ~$1–2 |
| Private endpoints (Key Vault, Storage) | Published rate ~$0.01/hr per endpoint + data processed, 2 endpoints | ~$14.60 | ~$14.60+ |
| **New total** | | **~$35–43** | **~$333–345** |
| **Existing template's total (Container Apps, Registry, DNS, alerts, monitoring)** | | ~$35 | ~$67 |
| **Combined total, mostly idle** | | **~$70–78/month** | **~$400–410/month** |

Note in the README: "The jump from dev/qa to uat/prod is dominated by zone-redundant PostgreSQL HA (two D2ds_v5 instances instead of one Burstable) — the same shape as the Container Apps replica cost in the sibling template, just larger. Re-check all prices in the calculator before committing a budget; the private-endpoint data-processing meter and the exact PostgreSQL backup-storage-included allowance are the two figures still worth confirming."

- [ ] **Step 3: Write `ARCHITECTURE.md`**

Base it on the source template's `ARCHITECTURE.md` C4 Mermaid model; add two containers (PostgreSQL Flexible Server, Storage Account) and one supporting container (Key Vault) at the container level, and the new relationships: Container App → Key Vault (reads secrets), Container App → PostgreSQL (reads/writes, password from Key Vault), Container App → Storage (reads/writes images, managed identity). Keep the system-context level (Task actor: "internal user") unchanged from the source template — the external boundary hasn't changed, only what's inside it.

- [ ] **Step 4: Generate the draw.io diagrams**

Invoke the `c4-drawio` skill against the `ARCHITECTURE.md` just written, targeting `c4-context.drawio` and `c4-containers.drawio` in this template's folder. Follow the skill's own steps for generating and checking the diagrams; there is no separate manual diagram-drawing step in this plan.

- [ ] **Step 5: Commit**

```bash
git add infrastructure/privately-accessible-container-app-with-database-and-storage/{README.md,ARCHITECTURE.md,c4-context.drawio,c4-containers.drawio}
git commit -m "docs: README design decisions/cost, ARCHITECTURE.md and C4 diagrams"
```

---

## Task 24: Update CLAUDE.md and GOLDEN-TEMPLATES.md

**Files:**
- Modify: `CLAUDE.md`
- Modify: `GOLDEN-TEMPLATES.md`

- [ ] **Step 1: Add a row to `CLAUDE.md`'s template table**

In the `Current templates` table, add:
```markdown
| Private (internal) container app with database and storage | `infrastructure/privately-accessible-container-app-with-database-and-storage/` | `content/python-crud-app/` |
```

- [ ] **Step 2: Add a row to `GOLDEN-TEMPLATES.md`'s catalogue table**

```markdown
| Privately accessible container app with database and storage | `infrastructure/privately-accessible-container-app-with-database-and-storage/` | `content/python-crud-app/` | A containerised backend with its own PostgreSQL database, Blob image storage and app-level username/password login, for **internal users** in assigned Entra groups |
```

- [ ] **Step 3: Verify no other doc references the old paths**

Run: `grep -rn "privately-accessible-container-app-with-database-and-storage" --include=*.md .` to confirm both files list it, and `grep -rn "python-crud-app" --include=*.md .` to confirm both files reference the content folder.
Expected: both greps show `CLAUDE.md` and `GOLDEN-TEMPLATES.md`.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md GOLDEN-TEMPLATES.md
git commit -m "docs: list the database/storage template in CLAUDE.md and GOLDEN-TEMPLATES.md"
```

---

## Final check (after all tasks)

- [ ] `terraform fmt -recursive infrastructure/privately-accessible-container-app-with-database-and-storage` — no diffs
- [ ] `terraform -chdir=infrastructure/privately-accessible-container-app-with-database-and-storage/stacks/container-app-with-database-and-storage validate` — success
- [ ] `terraform test` (all 4 environments, Task 13 Step 9) — all green
- [ ] `cd content/python-crud-app && pytest` — all green
- [ ] `git log --oneline` shows one commit per task, nothing left uncommitted (`git status` clean)
