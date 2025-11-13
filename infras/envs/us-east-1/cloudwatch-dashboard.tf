resource "aws_cloudwatch_dashboard" "kb_monitoring" {
  dashboard_name = "kb-rds-monitoring-${var.env}"
  
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
            ["CloudableAI/KB", "QueryDuration", "Environment", var.env, "TenantId", "t001"],
            ["CloudableAI/KB", "QueryDuration", "Environment", var.env, "TenantId", "t002"]
          ]
          period = 60
          stat = "Average"
          region = var.region
          title = "KB Query Duration (ms)"
          view = "timeSeries"
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
            ["CloudableAI/KB", "QueryResultCount", "Environment", var.env, "TenantId", "t001"],
            ["CloudableAI/KB", "QueryResultCount", "Environment", var.env, "TenantId", "t002"]
          ]
          period = 60
          stat = "Average"
          region = var.region
          title = "KB Query Result Count"
          view = "timeSeries"
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
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", "aurora-${var.env}"]
          ]
          period = 60
          stat = "Average"
          region = var.region
          title = "RDS CPU Utilization"
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "ServerlessDatabaseCapacity", "DBClusterIdentifier", "aurora-${var.env}"]
          ]
          period = 60
          stat = "Average"
          region = var.region
          title = "RDS Serverless Capacity"
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.kb_manager.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.orchestrator.function_name]
          ]
          period = 60
          stat = "Average"
          region = var.region
          title = "Lambda Duration"
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.kb_manager.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.orchestrator.function_name]
          ]
          period = 60
          stat = "Sum"
          region = var.region
          title = "Lambda Errors"
          view = "timeSeries"
        }
      }
    ]
  })
}

# Create CloudWatch alarms for KB Manager Lambda errors
resource "aws_cloudwatch_metric_alarm" "kb_manager_errors" {
  alarm_name          = "kb-manager-errors-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "This alarm monitors KB Manager Lambda errors"
  
  dimensions = {
    FunctionName = aws_lambda_function.kb_manager.function_name
  }
  
  tags = local.tags
}

# Create CloudWatch alarm for RDS high CPU usage
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "rds-cpu-high-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This alarm monitors RDS CPU usage"
  
  dimensions = {
    DBClusterIdentifier = "aurora-${var.env}"
  }
  
  tags = local.tags
}
