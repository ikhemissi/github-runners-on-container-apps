# Terraform lint (make test-infra, CI): Terraform's recommended rules, and the azurerm rules (e.g. invalid SKUs or sizes).
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Off: the environment is meant to be deleted whole (azd down), and the vault holds only the GitHub Apps' keys, which
# are regenerated in GitHub if lost (docs/BOOTSTRAP.md, key rotation).
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
