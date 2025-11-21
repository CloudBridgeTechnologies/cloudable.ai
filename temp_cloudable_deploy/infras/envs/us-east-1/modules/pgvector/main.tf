# Terraform module for setting up pgvector and Lambda integration

# RDS PostgreSQL pgvector extension setup
resource "aws_rds_cluster_parameter_group" "pgvector" {
  name        = "cloudable-pgvector-${var.environment}"
  family      = "aurora-postgresql14"
  description = "Parameter group for pgvector extension"

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,pgvector"
  }

  parameter {
    name  = "rds.allowed_extensions"
    value = "vector,uuid-ossp,pg_stat_statements"
  }

  tags = var.tags
}

# Lambda IAM Role for RDS data access
resource "aws_iam_role_policy" "lambda_rds_policy" {
  name   = "lambda-rds-pgvector-access-${var.environment}"
  role   = var.kb_manager_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement",
          "rds-data:CommitTransaction",
          "rds-data:RollbackTransaction",
          "rds-data:BeginTransaction"
        ]
        Effect   = "Allow"
        Resource = var.rds_cluster_arn
      },
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = var.rds_secret_arn
      }
    ]
  })
}

# Lambda function code update with pgvector compatibility
data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/lambda_package.zip"
  
  # These files will be overwritten with the updated versions
  excludes    = ["main.py", "rest_adapter.py"]
}

# Combine the base package with the updated files
resource "null_resource" "update_lambda_package" {
  triggers = {
    lambda_source_hash = filesha256("${var.lambda_source_dir}/main.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/temp
      cp ${path.module}/../../lambdas/kb_manager/main.py ${path.module}/temp/
      cp ${path.module}/../../lambdas/kb_manager/rest_adapter.py ${path.module}/temp/
      echo 'PGVECTOR_FIX_VERSION = "1.0.0"' > ${path.module}/temp/pgvector_fix.py
      cd ${path.module}/temp
      zip -r ../lambda_package.zip .
    EOT
  }

  depends_on = [data.archive_file.lambda_package]
}

# Lambda function update
resource "aws_lambda_function" "kb_manager" {
  function_name    = var.kb_manager_function_name
  filename         = "${path.module}/lambda_package.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_package.zip")
  
  role             = var.kb_manager_role_arn
  handler          = "main.handler"
  runtime          = "python3.12"
  timeout          = 900
  memory_size      = 512
  
  environment {
    variables = merge(var.existing_environment_variables, {
      RDS_CLUSTER_ARN = var.rds_cluster_arn
      RDS_SECRET_ARN  = var.rds_secret_arn
      RDS_DATABASE    = var.rds_database_name
    })
  }
  
  tags = var.tags

  depends_on = [null_resource.update_lambda_package]
}

# RDS pgvector initialization Lambda
resource "aws_lambda_function" "pgvector_init" {
  function_name    = "pgvector-init-${var.environment}"
  filename         = "${path.module}/pgvector_init_lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/pgvector_init_lambda.zip")
  
  role             = var.kb_manager_role_arn
  handler          = "setup_pgvector.handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 128
  
  environment {
    variables = {
      RDS_CLUSTER_ARN = var.rds_cluster_arn
      RDS_SECRET_ARN  = var.rds_secret_arn
      RDS_DATABASE    = var.rds_database_name
      TENANT_LIST     = jsonencode(var.tenant_ids)
      INDEX_TYPE      = var.pgvector_index_type
      ENVIRONMENT     = var.environment
    }
  }
  
  tags = var.tags
}

# Package the pgvector init script for Lambda
data "archive_file" "pgvector_init_lambda" {
  type        = "zip"
  output_path = "${path.module}/pgvector_init_lambda.zip"
  
  source {
    content  = file("${path.module}/../../envs/us-east-1/setup_pgvector.py")
    filename = "setup_pgvector.py"
  }
  
  source {
    content  = file("${path.module}/lambda_handler.py")
    filename = "lambda_handler.py"
  }
}

# Lambda invocation to setup pgvector
resource "null_resource" "invoke_pgvector_init" {
  triggers = {
    lambda_function = aws_lambda_function.pgvector_init.arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws lambda invoke \
        --function-name ${aws_lambda_function.pgvector_init.function_name} \
        --region ${var.region} \
        --payload '{}' \
        /tmp/pgvector_init_output.json
    EOT
  }

  depends_on = [aws_lambda_function.pgvector_init]
}

# CloudWatch Log Group for pgvector Lambda
resource "aws_cloudwatch_log_group" "pgvector_init_logs" {
  name              = "/aws/lambda/${aws_lambda_function.pgvector_init.function_name}"
  retention_in_days = 14
  tags              = var.tags
}

# CloudWatch metrics for pgvector query performance
resource "aws_cloudwatch_dashboard" "pgvector_metrics" {
  dashboard_name = "pgvector-performance-${var.environment}"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["CloudableAI/KB", "QueryDuration", "TenantId", "*", "Environment", var.environment]
          ]
          period = 300
          stat = "Average"
          title = "Vector Query Duration by Tenant"
          view = "timeSeries"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["CloudableAI/KB", "QueryResultCount", "TenantId", "*", "Environment", var.environment]
          ]
          period = 300
          stat = "Average"
          title = "Vector Query Result Count by Tenant"
          view = "timeSeries"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.kb_manager_function_name]
          ]
          period = 300
          stat = "Average"
          title = "KB Manager Lambda Duration"
          view = "timeSeries"
        }
      }
    ]
  })
}
