# The runners' egress control (docs/DECISIONS.md, D20): with enable_egress_proxy, the runners reach the internet only
# through an allowlist proxy. A network security group on the runners' subnet denies their direct internet traffic,
# but for what the Container Apps platform needs (image pulls, sign-in, monitoring). The job sends its HTTP(S) through
# Squid (egress-proxy/), which runs in its own internal Container Apps environment: its subnet keeps the default
# outbound access, and only the virtual network reaches it. Turning it on replaces the runners' environment and job.

variable "enable_egress_proxy" {
  description = "Send the runners' internet traffic through the allowlist proxy (EGRESS_PROXY); needs the proxy image (EGRESS_PROXY_IMAGE_TAG)."
  type        = bool
}

variable "egress_proxy_image_tag" {
  description = "Tag of the egress proxy image in the project's registry (EGRESS_PROXY_IMAGE_TAG), e.g. the commit it was built from."
  type        = string

  validation {
    condition     = !var.enable_egress_proxy || var.egress_proxy_image_tag != ""
    error_message = "The egress proxy needs its image: build it (docs/BOOTSTRAP.md) and set EGRESS_PROXY_IMAGE_TAG."
  }
}

locals {
  egress_proxy_port = 3128
  egress_proxy_url  = var.enable_egress_proxy ? "http://${module.egress_proxy_environment[0].static_ip_address}:${local.egress_proxy_port}" : null

  # The runner and the steps' tools read either spelling; Node's built-in fetch reads them only with NODE_USE_ENV_PROXY.
  # The managed identity endpoint (localhost) is reached directly.
  runner_proxy_env = var.enable_egress_proxy ? {
    HTTPS_PROXY        = local.egress_proxy_url
    https_proxy        = local.egress_proxy_url
    HTTP_PROXY         = local.egress_proxy_url
    http_proxy         = local.egress_proxy_url
    NO_PROXY           = "localhost,127.0.0.1"
    no_proxy           = "localhost,127.0.0.1"
    NODE_USE_ENV_PROXY = "1"
  } : {}

  # Outbound traffic the Container Apps platform needs from the runners' subnet (learn.microsoft.com: "Securing a
  # virtual network in Azure Container Apps", workload profiles environment), all on port 443. Container Registry and
  # the region's Storage serve the image layers. Key Vault in the region: the platform reads the job's Key Vault
  # reference (the Scaler App's key) from this subnet; without it, creating the job fails (experiment 06).
  runner_platform_rules = [
    { priority = 100, name = "AllowMicrosoftContainerRegistry", service_tag = "MicrosoftContainerRegistry" },
    { priority = 110, name = "AllowAzureFrontDoorFirstParty", service_tag = "AzureFrontDoor.FirstParty" },
    { priority = 120, name = "AllowAzureActiveDirectory", service_tag = "AzureActiveDirectory" },
    { priority = 130, name = "AllowAzureMonitor", service_tag = "AzureMonitor" },
    { priority = 140, name = "AllowAzureContainerRegistry", service_tag = "AzureContainerRegistry" },
    { priority = 150, name = "AllowStorageInRegion", service_tag = "Storage.${var.location}" },
    { priority = 160, name = "AllowKeyVaultInRegion", service_tag = "AzureKeyVault.${var.location}" },
  ]
}

# The scale rule's KEDA scaler runs in the runners' environment and calls the GitHub API directly (it can't use the
# proxy): the NSG allows GitHub's API addresses, as GitHub publishes them, read at each plan (experiment 06).
data "http" "github_meta" {
  count = var.enable_egress_proxy ? 1 : 0
  url   = "https://api.github.com/meta"

  request_headers = {
    Accept = "application/vnd.github+json"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Could not read GitHub's addresses from https://api.github.com/meta."
    }
  }
}

locals {
  # IPv4 only: the subnet has no IPv6.
  github_api_addresses = var.enable_egress_proxy ? [
    for prefix in jsondecode(data.http.github_meta[0].response_body).api : prefix if !strcontains(prefix, ":")
  ] : []
}

resource "azurerm_network_security_group" "runners" {
  count               = var.enable_egress_proxy ? 1 : 0
  name                = "nsg-runners-${var.environment_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags

  dynamic "security_rule" {
    for_each = local.runner_platform_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = "VirtualNetwork"
      source_port_range          = "*"
      destination_address_prefix = security_rule.value.service_tag
      destination_port_range     = "443"
    }
  }

  security_rule {
    name                         = "AllowGitHubApi"
    priority                     = 200
    direction                    = "Outbound"
    access                       = "Allow"
    protocol                     = "Tcp"
    source_address_prefix        = "VirtualNetwork"
    source_port_range            = "*"
    destination_address_prefixes = local.github_api_addresses
    destination_port_range       = "443"
  }

  # Everything else to the internet; the virtual network (the proxy) stays reachable through the default rules.
  security_rule {
    name                       = "DenyInternet"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "Internet"
    destination_port_range     = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "runners" {
  count                     = var.enable_egress_proxy ? 1 : 0
  subnet_id                 = local.network.subnet_ids["container-apps"]
  network_security_group_id = azurerm_network_security_group.runners[0].id
}

module "egress_proxy_environment" {
  source                     = "./modules/container-apps-environment"
  count                      = var.enable_egress_proxy ? 1 : 0
  name                       = "cae-proxy-${var.environment_name}-${local.token}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  tags                       = local.tags
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  subnet_id                  = local.network.subnet_ids["egress-proxy"]
  internal                   = true
}

resource "azurerm_user_assigned_identity" "egress_proxy" {
  count               = var.enable_egress_proxy ? 1 : 0
  name                = "id-egress-proxy-${var.environment_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "egress_proxy_pull" {
  count                = var.enable_egress_proxy ? 1 : 0
  scope                = module.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.egress_proxy[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_container_app" "egress_proxy" {
  count                        = var.enable_egress_proxy ? 1 : 0
  name                         = "ca-egress-proxy-${var.environment_name}"
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = module.egress_proxy_environment[0].id
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.egress_proxy[0].id]
  }

  registry {
    server   = module.container_registry.login_server
    identity = azurerm_user_assigned_identity.egress_proxy[0].id
  }

  # TCP: the runners send plain HTTP and CONNECT requests to the environment's static IP. External here means the whole
  # virtual network, since the environment is internal.
  ingress {
    external_enabled = true
    transport        = "tcp"
    target_port      = local.egress_proxy_port
    exposed_port     = local.egress_proxy_port

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    # Always one replica: the runners can't start without it.
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "squid"
      image  = "${module.container_registry.login_server}/egress-proxy:${var.egress_proxy_image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  depends_on = [azurerm_role_assignment.egress_proxy_pull]
}

output "EGRESS_PROXY_URL" { value = coalesce(local.egress_proxy_url, "none") }
