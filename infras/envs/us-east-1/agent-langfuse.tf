# Agent Telemetry with Langfuse
# SSM Parameters for storing Langfuse credentials

resource "aws_ssm_parameter" "langfuse_host" {
  name        = "/cloudable/${var.env}/langfuse/host"
  description = "Langfuse Host URL"
  type        = "String"
  value       = "https://cloud.langfuse.com"
  tier        = "Standard"
  
  tags = merge(local.tags, {
    Component = "AgentObservability"
  })
}

resource "aws_ssm_parameter" "langfuse_public_key" {
  name        = "/cloudable/${var.env}/langfuse/public-key"
  description = "Langfuse Public Key for Agent Core observability"
  type        = "String"
  value       = "pk-lf-f4e93f2a-d021-4fbe-9352-deadbeef1234" # Replace with actual public key
  tier        = "Standard"
  
  tags = merge(local.tags, {
    Component = "AgentObservability"
  })
}

resource "aws_ssm_parameter" "langfuse_secret_key" {
  name        = "/cloudable/${var.env}/langfuse/secret-key"
  description = "Langfuse Secret Key for Agent Core observability"
  type        = "SecureString"
  value       = "sk-lf-25c9d45a-e53b-4d87-8fc9-d3adb33f5678" # Replace with actual secret key
  tier        = "Standard"
  
  tags = merge(local.tags, {
    Component = "AgentObservability"
  })
}

# CloudWatch Log Groups are defined in agent-core-telemetry.tf

# Langfuse data export bucket is defined in s3-buckets.tf
resource "aws_s3_bucket" "langfuse_data_export" {
  bucket        = "cloudable-langfuse-data-${var.env}-${var.region}-20251024142435"
  force_destroy = true  # Allow deleting non-empty buckets

  tags = merge(local.tags, {
    Name    = "cloudable-langfuse-data-${var.env}-${var.region}-20251024142435"
    Service = "AgentTelemetry"
  })

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_public_access_block" "langfuse_data_export" {
  bucket                  = aws_s3_bucket.langfuse_data_export.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "langfuse_data_export" {
  bucket = aws_s3_bucket.langfuse_data_export.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "langfuse_data_export" {
  bucket = aws_s3_bucket.langfuse_data_export.id
  
  rule {
    id     = "expire-old-data"
    status = "Enabled"
    
    filter {
      prefix = ""
    }
    
    expiration {
      days = 90
    }
  }
}
