# AI Safety Monitoring and Alerting
# CloudWatch dashboards, alarms, and metrics for responsible AI monitoring

# CloudWatch Log Groups for AI safety events
resource "aws_cloudwatch_log_group" "ai_safety_events" {
  name              = "/aws/ai-safety/${var.env}"
  retention_in_days = 90
  
  tags = merge(local.tags, {
    Purpose = "AI Safety Monitoring"
  })
}

# Custom CloudWatch Metrics for AI Safety
/*
resource "aws_cloudwatch_log_metric_filter" "guardrail_blocks" {
  name           = "GuardrailBlocks-${var.env}"
  log_group_name = aws_cloudwatch_log_group.ai_safety_events.name
  pattern        = "[timestamp, request_id, level=\"ERROR\", message=\"Guardrail blocked*\"]"

  metric_transformation {
    name      = "GuardrailBlocks"
    namespace = "AI/Safety"
    value     = "1"
    
    default_value = "0"
  }
}
*/

/*
resource "aws_cloudwatch_log_metric_filter" "prompt_injection_attempts" {
  name           = "PromptInjectionAttempts-${var.env}"
  log_group_name = "/aws/lambda/orchestrator-${var.env}"
  pattern        = "[timestamp, request_id, level=\"WARNING\", message=\"Potential prompt injection detected*\"]"

  metric_transformation {
    name      = "PromptInjectionAttempts"
    namespace = "AI/Safety"
    value     = "1"
    
    default_value = "0"
  }
}
*/

/*
resource "aws_cloudwatch_log_metric_filter" "input_validation_failures" {
  name           = "InputValidationFailures-${var.env}"
  log_group_name = "/aws/lambda/orchestrator-${var.env}"
  pattern        = "[timestamp, request_id, level=\"ERROR\", message=\"Input validation failed*\"]"

  metric_transformation {
    name      = "InputValidationFailures"
    namespace = "AI/Safety"
    value     = "1"
    
    default_value = "0"
  }
}
*/

# Note: API Gateway V2 (HTTP API) doesn't create CloudWatch logs by default
# Rate limiting monitoring will be handled through API Gateway metrics instead
# resource "aws_cloudwatch_log_metric_filter" "rate_limit_exceeded" {
#   name           = "RateLimitExceeded-${var.env}"
#   log_group_name = "/aws/apigateway/${aws_apigatewayv2_api.http.id}/${aws_apigatewayv2_stage.default.name}"
#   pattern        = "[timestamp, request_id, status_code=\"429\", ...]"
#
#   metric_transformation {
#     name      = "RateLimitExceeded"
#     namespace = "AI/Safety"
#     value     = "1"
#     
#     default_value = "0"
#   }
# }

# CloudWatch Alarms for AI Safety
/* 
resource "aws_cloudwatch_metric_alarm" "high_guardrail_blocks" {
  alarm_name          = "high-guardrail-blocks-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "GuardrailBlocks"
  namespace           = "AI/Safety"
  period              = "300"  # 5 minutes
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This alarm monitors for high number of guardrail blocks indicating potential misuse"
  alarm_actions       = [aws_sns_topic.ai_safety_alerts.arn]
  ok_actions          = [aws_sns_topic.ai_safety_alerts.arn]
  
  tags = local.tags
}
*/

/*
resource "aws_cloudwatch_metric_alarm" "prompt_injection_spike" {
  alarm_name          = "prompt-injection-spike-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "PromptInjectionAttempts"
  namespace           = "AI/Safety"
  period              = "300"  # 5 minutes
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This alarm monitors for spikes in prompt injection attempts"
  alarm_actions       = [aws_sns_topic.ai_safety_alerts.arn]
  treat_missing_data  = "notBreaching"
  
  tags = local.tags
}
*/

/*
resource "aws_cloudwatch_metric_alarm" "high_validation_failures" {
  alarm_name          = "high-input-validation-failures-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "InputValidationFailures"
  namespace           = "AI/Safety"
  period              = "300"  # 5 minutes
  statistic           = "Sum"
  threshold           = "20"
  alarm_description   = "This alarm monitors for high number of input validation failures"
  alarm_actions       = [aws_sns_topic.ai_safety_alerts.arn]
  
  tags = local.tags
}
*/

resource "aws_cloudwatch_metric_alarm" "api_throttling_alarm" {
  alarm_name          = "api-throttling-alarm-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGatewayV2"
  period              = "300"  # 5 minutes
  statistic           = "Sum"
  threshold           = "20"
  alarm_description   = "This alarm monitors for high number of 4XX errors indicating potential rate limiting or abuse"
  alarm_actions       = [aws_sns_topic.ai_safety_alerts.arn]
  
  dimensions = {
    ApiId = aws_apigatewayv2_api.http.id
  }
  
  tags = local.tags
}

# SNS Topic for AI Safety Alerts
resource "aws_sns_topic" "ai_safety_alerts" {
  name         = "ai-safety-alerts-${var.env}"
  display_name = "AI Safety Alerts"
  
  tags = local.tags
}

resource "aws_sns_topic_subscription" "ai_safety_email_alerts" {
  count     = length(var.alert_emails)
  topic_arn = aws_sns_topic.ai_safety_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_emails[count.index]
}

# CloudWatch Dashboard for AI Safety Monitoring
resource "aws_cloudwatch_dashboard" "ai_safety" {
  dashboard_name = "AI-Safety-${var.env}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AI/Safety", "GuardrailBlocks"],
            [".", "PromptInjectionAttempts"],
            [".", "InputValidationFailures"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "AI Safety Events"
          period  = 300
          stat    = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "orchestrator-${var.env}"],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Lambda Performance"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", "chat-api-${var.env}"],
            [".", "4XXError", ".", "."],
            [".", "5XXError", ".", "."],
            [".", "Latency", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "API Gateway Metrics"
          period  = 300
        }
      }
    ]
  })
}

# AI Model Usage Tracking
/*
resource "aws_cloudwatch_log_metric_filter" "bedrock_model_invocations" {
  name           = "BedrockModelInvocations-${var.env}"
  log_group_name = "/aws/lambda/orchestrator-${var.env}"
  pattern        = "[timestamp, request_id, level=\"INFO\", message=\"Invoking agent with sessionState*\"]"

  metric_transformation {
    name      = "BedrockModelInvocations"
    namespace = "AI/Usage"
    value     = "1"
    
    default_value = "0"
  }
}
*/

/*
resource "aws_cloudwatch_metric_alarm" "unusual_model_usage" {
  alarm_name          = "unusual-model-usage-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BedrockModelInvocations"
  namespace           = "AI/Usage"
  period              = "3600"  # 1 hour
  statistic           = "Sum"
  threshold           = "1000"  # Adjust based on expected usage
  alarm_description   = "This alarm monitors for unusual spikes in AI model usage"
  alarm_actions       = [aws_sns_topic.ai_safety_alerts.arn]
  
  tags = local.tags
}
*/

# Output important monitoring resources
output "ai_safety_dashboard_url" {
  description = "URL to the AI Safety CloudWatch Dashboard"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.ai_safety.dashboard_name}"
}

output "ai_safety_sns_topic_arn" {
  description = "ARN of the AI Safety SNS topic for alerts"
  value       = aws_sns_topic.ai_safety_alerts.arn
}