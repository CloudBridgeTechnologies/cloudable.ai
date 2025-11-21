resource "aws_cloudwatch_log_group" "orchestrator" {
  name              = "/aws/lambda/orchestrator-${var.env}"
  retention_in_days = 30
  tags              = local.tags
}

resource "aws_cloudwatch_log_group" "db_actions" {
  name              = "/aws/lambda/db-actions-${var.env}"
  retention_in_days = 30
  tags              = local.tags
}

