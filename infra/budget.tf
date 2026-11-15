# A monthly budget on the resource group (PRD-001, Phase 6): alerts at 80 % of the actual spend and 100 % of the
# forecast, to the resource group's Owners, so no e-mail address is configured anywhere. A budget alerts; it does not
# stop anything.

variable "budget_amount" {
  description = "Monthly budget of the resource group, in the subscription's billing currency (BUDGET_AMOUNT); 0: no budget."
  type        = number
}

# The budget starts with the month it was created in; kept in the state so later applies don't move it.
resource "time_static" "budget_start" {}

resource "azurerm_consumption_budget_resource_group" "main" {
  count             = var.budget_amount > 0 ? 1 : 0
  name              = "budget-${var.environment_name}"
  resource_group_id = azurerm_resource_group.main.id
  amount            = var.budget_amount
  time_grain        = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", time_static.budget_start.rfc3339)
  }

  notification {
    threshold      = 80
    threshold_type = "Actual"
    operator       = "GreaterThanOrEqualTo"
    contact_roles  = ["Owner"]
  }

  notification {
    threshold      = 100
    threshold_type = "Forecasted"
    operator       = "GreaterThanOrEqualTo"
    contact_roles  = ["Owner"]
  }
}
