# Private container hosting: a registry, an internal-only Container Apps
# environment in the spoke subnet, the Private DNS zone that resolves its
# domain, and the container app itself.
#
# The app is created only when create_container_app = true, because the
# registry is empty on the first apply: apply once, push the first image,
# then apply again with create_container_app = true.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "environment_name" {
  type = string
}

variable "container_app_name" {
  type = string
}

variable "registry_name" {
  type = string
}

variable "managed_identity_name" {
  type = string
}

variable "subnet_id" {
  description = "Subnet delegated to Microsoft.App/environments (at least /27)."
  type        = string
}

variable "dns_zone_virtual_network_ids" {
  description = "VNets that resolve the environment's domain: the spoke, plus the hub when users reach the app through it."
  type        = map(string)
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "zone_redundancy_enabled" {
  description = "Spread the environment and its replicas across availability zones. Fixed at creation."
  type        = bool
  default     = false
}

variable "registry_sku" {
  type    = string
  default = "Basic"
}

variable "registry_zone_redundancy_enabled" {
  description = "Premium registries only. Fixed at creation."
  type        = bool
  default     = false
}

variable "create_container_app" {
  type    = bool
  default = false
}

variable "image_repository" {
  description = "Repository in the registry, e.g. python-mvc-app."
  type        = string
}

variable "initial_image_tag" {
  description = "Tag used when the app is first created. Later deployments change the image outside Terraform."
  type        = string
  default     = "initial"
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "health_path" {
  type    = string
  default = "/healthz"
}

variable "cpu" {
  type    = number
  default = 1
}

variable "memory" {
  type    = string
  default = "2Gi"
}

variable "min_replicas" {
  type    = number
  default = 1
}

variable "max_replicas" {
  type    = number
  default = 1
}

variable "environment_variables" {
  description = "Plain settings passed to the container."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secret name => value. Each one is passed to the container as an environment variable named by secret_environment_variables."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "secret_environment_variables" {
  description = "Environment variable name => secret name."
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_user_assigned_identity" "app" {
  name                = var.managed_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Basic by default: private endpoints and zone redundancy need Premium, which a
# small workload does not justify. Admin user and anonymous pull are off; the app
# pulls with its identity.
resource "azurerm_container_registry" "this" {
  name                    = var.registry_name
  resource_group_name     = var.resource_group_name
  location                = var.location
  sku                     = var.registry_sku
  zone_redundancy_enabled = var.registry_zone_redundancy_enabled
  admin_enabled           = false
  anonymous_pull_enabled  = false
  tags                    = var.tags
}

resource "azurerm_role_assignment" "app_pulls_images" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

resource "azurerm_container_app_environment" "this" {
  name                           = var.environment_name
  resource_group_name            = var.resource_group_name
  location                       = var.location
  infrastructure_subnet_id       = var.subnet_id
  internal_load_balancer_enabled = true
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  logs_destination               = "log-analytics"
  zone_redundancy_enabled        = var.zone_redundancy_enabled
  tags                           = var.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

# The environment's domain resolves to its internal load balancer.
resource "azurerm_private_dns_zone" "environment" {
  name                = azurerm_container_app_environment.this.default_domain
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.environment.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_container_app_environment.this.static_ip_address]
}

resource "azurerm_private_dns_zone_virtual_network_link" "environment" {
  for_each = var.dns_zone_virtual_network_ids

  name                  = "link-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.environment.name
  virtual_network_id    = each.value
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_container_app" "this" {
  count = var.create_container_app ? 1 : 0

  name                         = var.container_app_name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  registry {
    server   = azurerm_container_registry.this.login_server
    identity = azurerm_user_assigned_identity.app.id
  }

  dynamic "secret" {
    for_each = nonsensitive(toset(keys(var.secrets)))
    content {
      name  = secret.value
      value = var.secrets[secret.value]
    }
  }

  # In an internal environment, "external" means reachable from the VNet and
  # the networks peered to it, never from the internet.
  ingress {
    external_enabled           = true
    target_port                = var.container_port
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "app"
      image  = "${azurerm_container_registry.this.login_server}/${var.image_repository}:${var.initial_image_tag}"
      cpu    = var.cpu
      memory = var.memory

      dynamic "env" {
        for_each = var.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secret_environment_variables
        content {
          name        = env.key
          secret_name = env.value
        }
      }

      liveness_probe {
        transport = "HTTP"
        port      = var.container_port
        path      = var.health_path
      }

      readiness_probe {
        transport = "HTTP"
        port      = var.container_port
        path      = var.health_path
      }
    }
  }

  lifecycle {
    # The delivery pipeline deploys new images; Terraform only sets the first one.
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.app_pulls_images]
}

output "container_app_id" {
  value = one(azurerm_container_app.this[*].id)
}

output "container_app_fqdn" {
  value = one(azurerm_container_app.this[*].ingress[0].fqdn)
}

output "registry_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "registry_id" {
  value = azurerm_container_registry.this.id
}

output "environment_default_domain" {
  value = azurerm_container_app_environment.this.default_domain
}

output "environment_static_ip_address" {
  value = azurerm_container_app_environment.this.static_ip_address
}
