resource "aws_budgets_budget" "monthly" {
  name         = "cloudable-${var.env}-spend"
  budget_type  = "COST"
  limit_amount = "500"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit = true
    include_refund = true
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.alert_emails
  }

  tags = local.tags
}

