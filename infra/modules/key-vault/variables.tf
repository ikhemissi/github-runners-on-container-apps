variable "name" {
  description = "Globally unique, 3 to 24 characters."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "secrets_officer_object_ids" {
  description = "Principals that write secrets (Key Vault Secrets Officer), e.g. the deployer, since Terraform writes the secrets it generates."
  type        = list(string)
  default     = []
}

variable "public_network_access_enabled" {
  description = "False once every client reaches the vault through the virtual network (the deployer included)."
  type        = bool
  default     = true
}

variable "private_endpoint" {
  description = "A private endpoint: its subnet, and the privatelink.vaultcore.azure.net zone it registers in. Null: none."
  # An object rather than a subnet id: whether there is one stays known at plan time, before a new subnet has its id.
  type = object({
    subnet_id           = string
    private_dns_zone_id = string
  })
  default = null
}
