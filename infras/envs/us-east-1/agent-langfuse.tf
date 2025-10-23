# Agent Core Langfuse Integration for Advanced Observability
# This file defines resources for Langfuse telemetry, tracing, and analytics

# SSM Parameters for Langfuse Credentials
resource "aws_ssm_parameter" "langfuse_public_key" {
  name        = "/cloudable/${var.env}/langfuse/public-key"
  description = "Langfuse Public Key for Agent Core observability"
  type        = "String"
  value       = var.langfuse_public_key
  tags        = merge(local.tags, { Component = "AgentObservability" })
}

resource "aws_ssm_parameter" "langfuse_secret_key" {
  name        = "/cloudable/${var.env}/langfuse/secret-key"
  description = "Langfuse Secret Key for Agent Core observability"
  type        = "SecureString"
  value       = var.langfuse_secret_key
  tags        = merge(local.tags, { Component = "AgentObservability" })
}

resource "aws_ssm_parameter" "langfuse_host" {
  name        = "/cloudable/${var.env}/langfuse/host"
  description = "Langfuse Host URL"
  type        = "String"
  value       = var.langfuse_host
  tags        = merge(local.tags, { Component = "AgentObservability" })
}

# Lambda Layer for Langfuse SDK
resource "aws_lambda_layer_version" "langfuse_layer" {
  layer_name          = "langfuse-sdk-layer-${var.env}"
  description         = "Langfuse Python SDK for Lambda functions"
  filename            = "${path.module}/layers/langfuse_layer.zip"
  source_code_hash    = filebase64sha256("${path.module}/layers/langfuse_layer.zip")
  compatible_runtimes = ["python3.9", "python3.10", "python3.11", "python3.12"]
}

# S3 Bucket for Langfuse Session Data Export
resource "aws_s3_bucket" "langfuse_data_export" {
  bucket = "cloudable-langfuse-data-${var.env}-${var.region}"
  
  tags = merge(local.tags, { 
    Component = "AgentObservability",
    Purpose   = "LangfuseDataExport"
  })
  
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "langfuse_data_export" {
  bucket = aws_s3_bucket.langfuse_data_export.id

  rule {
    id = "expire-old-data"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

# IAM Role for Langfuse Data Export Lambda
resource "aws_iam_role" "langfuse_export" {
  name = "langfuse-data-export-${var.env}-${var.region}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
  
  tags = merge(local.tags, { Component = "AgentObservability" })
}

resource "aws_iam_role_policy" "langfuse_export" {
  role = aws_iam_role.langfuse_export.id
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.langfuse_data_export.arn,
          "${aws_s3_bucket.langfuse_data_export.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter"
        ],
        Resource = [
          aws_ssm_parameter.langfuse_public_key.arn,
          aws_ssm_parameter.langfuse_secret_key.arn,
          aws_ssm_parameter.langfuse_host.arn
        ]
      }
    ]
  })
}

# CloudWatch Event Rule for Langfuse Data Export
resource "aws_cloudwatch_event_rule" "langfuse_data_export" {
  name        = "langfuse-data-export-${var.env}"
  description = "Daily Langfuse data export for analysis"
  
  schedule_expression = "cron(0 1 * * ? *)" # Run daily at 1 AM UTC
  
  tags = merge(local.tags, { Component = "AgentObservability" })
}

# Variables for Langfuse configuration
variable "langfuse_public_key" {
  description = "Langfuse public key for API authentication"
  type        = string
  default     = "pk-lf-..."
}

variable "langfuse_secret_key" {
  description = "Langfuse secret key for API authentication"
  type        = string
  default     = "sk-lf-..."
  sensitive   = true
}

variable "langfuse_host" {
  description = "Langfuse API host"
  type        = string
  default     = "https://cloud.langfuse.com"
}
