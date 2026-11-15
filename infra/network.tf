# The virtual network, created only when a feature needs one: the egress proxy (egress-proxy.tf) puts the runners and
# the proxy in their own subnets; private networking adds a private endpoint for Key Vault. Without either, every service
# is reached over its public endpoint, with Entra authentication. Module calls read their subnet and private DNS zones
# from local.network (subnet ids by role: "container-apps", "egress-proxy", "private-endpoints").

variable "enable_private_networking" {
  description = "Give Key Vault a private endpoint in the virtual network (PRIVATE_NETWORKING). The vault stays reachable publicly, with Entra authentication, until every client (the deployer included) works from the network (docs/DECISIONS.md, D21)."
  type        = bool
}

locals {
  network_enabled = var.enable_egress_proxy || var.enable_private_networking

  # Each Container Apps environment needs its own subnet, delegated to it, /27 or larger.
  subnets = merge(
    { "container-apps" = { address_prefix = "10.0.0.0/24", delegation = "Microsoft.App/environments" } },
    var.enable_egress_proxy ? { "egress-proxy" = { address_prefix = "10.0.1.0/27", delegation = "Microsoft.App/environments" } } : {},
    var.enable_private_networking ? { "private-endpoints" = { address_prefix = "10.0.2.0/28" } } : {},
  )
}

module "network" {
  source              = "./modules/network"
  count               = local.network_enabled ? 1 : 0
  name                = "vnet-${var.environment_name}-${local.token}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags
  address_space       = "10.0.0.0/16"
  subnets             = local.subnets
  private_dns_zones   = var.enable_private_networking ? ["privatelink.vaultcore.azure.net"] : []
}

locals {
  network = {
    subnet_ids           = local.network_enabled ? module.network[0].subnet_ids : {}
    private_dns_zone_ids = local.network_enabled ? module.network[0].private_dns_zone_ids : {}
  }
}
