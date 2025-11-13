# Agent Core Telemetry and Monitoring Infrastructure
# This file defines CloudWatch resources for comprehensive monitoring of Agent Core components

# CloudWatch Log Group for Agent Telemetry
resource "aws_cloudwatch_log_group" "agent_telemetry" {
  name              = "/aws/bedrock/agent-core-telemetry-${var.env}"
  retention_in_days = 30
  tags              = merge(local.tags, { Component = "AgentCoreTelemetry" })
}

# CloudWatch Log Group for Agent Core Tracing
resource "aws_cloudwatch_log_group" "agent_tracing" {
  name              = "/aws/bedrock/agent-core-tracing-${var.env}"
  retention_in_days = 30
  tags              = merge(local.tags, { Component = "AgentCoreTracing" })
}

# CloudWatch Dashboard for Agent Core Monitoring
resource "aws_cloudwatch_dashboard" "agent_core_dashboard" {
  dashboard_name = "agent-core-dashboard-${var.env}"
  
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
            ["AWS/Bedrock", "SuccessfulRequestCount", "ModelId", "anthropic.claude-3-sonnet-20240229-v1:0"],
            [".", "InvocationLatency", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Model Invocation Metrics"
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
            ["AWS/Bedrock", "InvocationClientErrors", "ModelId", "anthropic.claude-3-sonnet-20240229-v1:0"],
            [".", "InvocationServerErrors", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Model Error Metrics"
          period  = 300
          stat    = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "db-actions-${var.env}"],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", ".", { stat = "Average" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "DB Actions Lambda Metrics"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          query = "SOURCE '/aws/bedrock/agent-core-telemetry-${var.env}' | fields @timestamp, @message, tenant_id, operation_type, response_time, status_code | sort @timestamp desc | limit 20"
          region = var.region
          title  = "Agent Core Telemetry Logs"
          view   = "table"
        }
      },
      {
        type   = "text"
        x      = 0
        y      = 12
        width  = 24
        height = 2
        properties = {
          markdown = "# Agent Core Performance and Telemetry\nThis dashboard monitors the performance and operational metrics of the Cloudable.AI Agent Core system."
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 8
        height = 6
        properties = {
          metrics = [
            [ { "expression": "m1/m2*100", "label": "Knowledge Base Success Rate", "id": "e1" } ],
            [ "AWS/Bedrock", "KnowledgeBaseSuccessfulQueries", { "id": "m1", "visible": false } ],
            [ ".", "KnowledgeBaseTotalQueries", { "id": "m2", "visible": false } ]
          ]
          view    = "timeSeries"
          region  = var.region
          title   = "Knowledge Base Query Success Rate"
          period  = 300
          stat    = "Average"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 14
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Bedrock", "KnowledgeBaseQueryLatency", { stat = "Average" }],
            [".", "KnowledgeBaseQueryLatency", { stat = "p90" }],
            [".", "KnowledgeBaseQueryLatency", { stat = "p99" }]
          ]
          view    = "timeSeries"
          region  = var.region
          title   = "Knowledge Base Query Latency"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 14
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Bedrock", "AgentInvocationCount"],
            [".", "AgentSuccessfulInvocationCount"]
          ]
          view    = "timeSeries"
          region  = var.region
          title   = "Agent Invocation Metrics"
          period  = 300
          stat    = "Sum"
        }
      }
    ]
  })
}

# CloudWatch Alarm for High Agent Error Rate
resource "aws_cloudwatch_metric_alarm" "agent_error_rate" {
  alarm_name          = "agent-core-error-rate-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "InvocationClientErrors"
  namespace           = "AWS/Bedrock"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "This alarm monitors for high error rates in Agent Core operations"
  dimensions = {
    ModelId = "anthropic.claude-3-sonnet-20240229-v1:0"
  }
  
  alarm_actions = var.alert_sns_topics
  ok_actions    = var.alert_sns_topics
  
  tags = merge(local.tags, { Component = "AgentCoreMonitoring" })
}

# CloudWatch Alarm for Knowledge Base Query Latency
resource "aws_cloudwatch_metric_alarm" "kb_query_latency" {
  alarm_name          = "agent-core-kb-latency-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "KnowledgeBaseQueryLatency"
  namespace           = "AWS/Bedrock"
  period              = 300
  extended_statistic  = "p90"
  threshold           = 2000 # 2 seconds
  alarm_description   = "This alarm monitors for high latency in Knowledge Base queries"
  
  alarm_actions = var.alert_sns_topics
  ok_actions    = var.alert_sns_topics
  
  tags = merge(local.tags, { Component = "AgentCoreMonitoring" })
}

# CloudWatch Metric Filter for Agent Operations
resource "aws_cloudwatch_log_metric_filter" "agent_operations" {
  name           = "agent-core-operations-${var.env}"
  pattern        = "{ $.operation_type = * }"
  log_group_name = aws_cloudwatch_log_group.agent_telemetry.name

  metric_transformation {
    name      = "AgentOperationCount"
    namespace = "Cloudable/AgentCore"
    value     = "1"
    dimensions = {
      OperationType = "$.operation_type"
      TenantId = "$.tenant_id"
    }
  }
}

# CloudWatch Metric Filter for Agent Response Time
resource "aws_cloudwatch_log_metric_filter" "agent_response_time" {
  name           = "agent-core-response-time-${var.env}"
  pattern        = "{ $.response_time = * }"
  log_group_name = aws_cloudwatch_log_group.agent_telemetry.name

  metric_transformation {
    name      = "AgentResponseTime"
    namespace = "Cloudable/AgentCore"
    value     = "$.response_time"
    dimensions = {
      OperationType = "$.operation_type"
      TenantId = "$.tenant_id"
    }
  }
}

# Variables for alert topics
variable "alert_sns_topics" {
  description = "List of SNS topics ARNs for CloudWatch alerts"
  type        = list(string)
  default     = []
}
