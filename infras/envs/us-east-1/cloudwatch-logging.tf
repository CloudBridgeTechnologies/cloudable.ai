# CloudWatch Logging Configuration for all Lambda functions and API Gateway

# CloudWatch Log Group for orchestrator Lambda
resource "aws_cloudwatch_log_group" "orchestrator_logs" {
  name              = "/aws/lambda/orchestrator-${var.env}"
  retention_in_days = 30
  tags = merge(local.tags, {
    Service = "Orchestrator"
  })
  
  lifecycle {
    ignore_changes = [name]
    prevent_destroy = false
  }
}

# CloudWatch Log Group for KB Manager Lambda
resource "aws_cloudwatch_log_group" "kb_manager_logs" {
  name              = "/aws/lambda/${aws_lambda_function.kb_manager.function_name}"
  retention_in_days = 30
  tags = merge(local.tags, {
    Service = "KnowledgeBase"
  })
}

# CloudWatch Log Group for KB Sync Trigger Lambda
resource "aws_cloudwatch_log_group" "kb_sync_trigger_logs" {
  name              = "/aws/lambda/${aws_lambda_function.kb_sync_trigger.function_name}"
  retention_in_days = 30
  tags = merge(local.tags, {
    Service = "KnowledgeBase"
  })
}

# CloudWatch Log Group for Document Summarizer Lambda 
resource "aws_cloudwatch_log_group" "document_summarizer_logs" {
  name              = "/aws/lambda/${aws_lambda_function.document_summarizer.function_name}"
  retention_in_days = 30
  tags = merge(local.tags, {
    Service = "DocumentProcessing"
  })
}

# CloudWatch Log Group for API Gateway REST API
# Note: This resource is already defined in api-gateway.tf, so we're commenting it out here
# resource "aws_cloudwatch_log_group" "api_gateway_logs" {
#   name              = "/aws/apigateway/${aws_api_gateway_rest_api.secure_api.name}"
#   retention_in_days = 30
#   tags = merge(local.tags, {
#     Service = "APIGateway"
#   })
# }

# CloudWatch Log Group for API Gateway HTTP API
resource "aws_cloudwatch_log_group" "http_api_logs" {
  name              = "/aws/apigateway/${aws_apigatewayv2_api.http.name}"
  retention_in_days = 30
  tags = merge(local.tags, {
    Service = "APIGateway"
  })
}

# CloudWatch Log Group for OpenSearch Serverless collections
resource "aws_cloudwatch_log_group" "opensearch_logs" {
  for_each          = var.enable_bedrock_agents ? var.tenants : {}
  name              = "/aws/opensearchserverless/collection/${aws_opensearchserverless_collection.kb[each.key].name}"
  retention_in_days = 30
  tags = merge(local.tags, {
    Service = "OpenSearch",
    Tenant  = each.value.name
  })
}

# CloudWatch Alarms for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each            = {
    # orchestrator      = aws_lambda_function.orchestrator.function_name # Defined in lambda-orchestrator.tf
    kb_manager        = aws_lambda_function.kb_manager.function_name
    kb_sync_trigger   = aws_lambda_function.kb_sync_trigger.function_name
    document_summarizer = aws_lambda_function.document_summarizer.function_name
    s3_helper         = aws_lambda_function.s3_helper.function_name
  }
  
  alarm_name          = "lambda-errors-${each.value}-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 3
  alarm_description   = "This alarm monitors Lambda function errors"
  alarm_actions       = length(var.alert_emails) > 0 ? [aws_sns_topic.alerts[0].arn] : []
  
  dimensions = {
    FunctionName = each.value
  }
  
  tags = local.tags
}

# CloudWatch Alarms for DLQ message count
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  for_each            = {
    document_summarizer = aws_sqs_queue.document_summarizer_dlq.name
    s3_helper         = aws_sqs_queue.s3_helper_dlq.name
  }
  
  alarm_name          = "dlq-messages-${each.value}-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "This alarm monitors DLQ message count"
  alarm_actions       = length(var.alert_emails) > 0 ? [aws_sns_topic.alerts[0].arn] : []
  
  dimensions = {
    QueueName = each.value
  }
  
  tags = local.tags
}

# CloudWatch Alarms for API Gateway 4xx/5xx errors
resource "aws_cloudwatch_metric_alarm" "api_gateway_errors" {
  for_each            = {
    "4xx" = "4XXError"
    "5xx" = "5XXError"
  }
  
  alarm_name          = "api-gateway-${each.key}-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = each.value
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = each.key == "4xx" ? 20 : 5
  alarm_description   = "This alarm monitors API Gateway ${each.key} errors"
  alarm_actions       = length(var.alert_emails) > 0 ? [aws_sns_topic.alerts[0].arn] : []
  
  dimensions = {
    ApiName = aws_api_gateway_rest_api.secure_api.name
    Stage   = aws_api_gateway_stage.secure_api.stage_name
  }
  
  tags = local.tags
}

# CloudWatch Alarms for HTTP API Gateway 4xx/5xx errors
resource "aws_cloudwatch_metric_alarm" "http_api_gateway_errors" {
  for_each            = {
    "4xx" = "4xx"
    "5xx" = "5xx"
  }
  
  alarm_name          = "http-api-gateway-${each.key}-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = each.value
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = each.key == "4xx" ? 20 : 5
  alarm_description   = "This alarm monitors HTTP API Gateway ${each.key} errors"
  alarm_actions       = length(var.alert_emails) > 0 ? [aws_sns_topic.alerts[0].arn] : []
  
  dimensions = {
    ApiId = aws_apigatewayv2_api.http.id
    Stage = var.env
  }
  
  tags = local.tags
}

# SNS Topic for CloudWatch Alarms
resource "aws_sns_topic" "alerts" {
  count = length(var.alert_emails) > 0 ? 1 : 0
  
  name         = "cloudable-alerts-${var.env}"
  display_name = "Cloudable.AI Alerts"
  
  tags = local.tags
}

# SNS Topic Subscriptions for alert emails
resource "aws_sns_topic_subscription" "alert_email_subscriptions" {
  count     = length(var.alert_emails)
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_emails[count.index]
}
