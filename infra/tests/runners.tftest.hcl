# Offline tests of the Terraform root (no Azure access: every provider is mocked, and only plans run). They read as the
# flags' promises: the network, the egress proxy and the private DNS zone exist only when their flag is on, and the
# job's settings follow. The modules' own tests (modules/*/tests) cover what happens inside them.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      subscription_id = "00000000-0000-0000-0000-000000000000"
      object_id       = "00000000-0000-0000-0000-000000000002"
    }
  }
}
mock_provider "azapi" {}
mock_provider "azuread" {}
mock_provider "random" {}
mock_provider "time" {}
mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code   = 200
      response_body = "{\"api\": [\"192.0.2.0/24\", \"2001:db8::/32\"]}"
    }
  }
}

variables {
  environment_name                   = "runners-test"
  subscription_id                    = "00000000-0000-0000-0000-000000000000"
  location                           = "francecentral"
  tags                               = ""
  runner_image_tag                   = "test"
  runner_github_owner                = "octo-org"
  runner_github_repo                 = "octo-repo"
  runner_registrar_client_id         = "Iv1.test"
  runner_registrar_installation_id   = "1"
  runner_labels                      = "aca-agent"
  runner_group_id                    = 1
  runner_scaler_app_id               = "2"
  runner_scaler_installation_id      = "1"
  runner_max_executions              = 3
  runner_polling_interval_in_seconds = 30
  runner_idle_timeout_in_seconds     = 300
  runner_cpu                         = 2
  runner_replica_timeout_in_seconds  = 12600
  runner_oidc_environment            = "azure-dev"
  runner_deployer_oidc_subject       = ""
  runner_deployer_scope              = ""
  runner_deployer_role               = "Reader"
  budget_amount                      = 0
  enable_egress_proxy                = false
  egress_proxy_image_tag             = ""
  enable_private_networking          = false
}

run "every_flag_off" {
  command = plan

  assert {
    condition     = length(module.network) == 0 && length(azurerm_network_security_group.runners) == 0
    error_message = "No virtual network and no network security group when every flag is off."
  }

  assert {
    condition     = length(azurerm_container_app.egress_proxy) == 0
    error_message = "No egress proxy when it is off."
  }

  assert {
    condition     = !contains([for env in azurerm_container_app_job.runner.template[0].container[0].env : env.name], "HTTPS_PROXY")
    error_message = "The job gets no proxy setting without the egress proxy."
  }
}

run "egress_proxy" {
  command = plan

  variables {
    enable_egress_proxy    = true
    egress_proxy_image_tag = "test"
  }

  assert {
    condition     = keys(local.network.subnet_ids) == tolist(["container-apps", "egress-proxy"])
    error_message = "A subnet for the runners and one for the proxy."
  }

  assert {
    condition     = one([for rule in azurerm_network_security_group.runners[0].security_rule : rule if rule.access == "Deny"]).destination_address_prefix == "Internet"
    error_message = "The runners' subnet denies the internet."
  }

  assert {
    condition     = alltrue([for rule in azurerm_network_security_group.runners[0].security_rule : rule.access == "Deny" || rule.destination_port_range == "443"])
    error_message = "The runners' subnet allows the platform's service tags on port 443 only."
  }

  assert {
    condition     = local.github_api_addresses == tolist(["192.0.2.0/24"])
    error_message = "The scaler reaches GitHub's API addresses (IPv4) directly."
  }

  assert {
    condition     = azurerm_container_app.egress_proxy[0].ingress[0].transport == "tcp" && azurerm_container_app.egress_proxy[0].template[0].min_replicas == 1
    error_message = "The proxy always runs one replica, with TCP ingress."
  }

  assert {
    condition = alltrue([
      for name in ["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "NO_PROXY", "no_proxy", "NODE_USE_ENV_PROXY"] :
      contains([for env in azurerm_container_app_job.runner.template[0].container[0].env : env.name], name)
    ])
    error_message = "The job sends its traffic through the proxy, in both spellings, Node included."
  }
}

run "egress_proxy_needs_its_image" {
  command = plan

  variables {
    enable_egress_proxy = true
  }

  expect_failures = [var.egress_proxy_image_tag]
}

run "private_networking" {
  command = plan

  variables {
    enable_private_networking = true
  }

  assert {
    condition     = keys(local.network.subnet_ids) == tolist(["container-apps", "private-endpoints"])
    error_message = "A subnet for the runners and one for private endpoints; no proxy subnet."
  }

  assert {
    condition     = contains(keys(local.private_endpoint.private_dns_zone_ids), "privatelink.vaultcore.azure.net")
    error_message = "Key Vault's private DNS zone, for its private endpoint."
  }

  assert {
    condition     = length(azurerm_network_security_group.runners) == 0
    error_message = "Private networking alone leaves the runners' internet access open."
  }
}
