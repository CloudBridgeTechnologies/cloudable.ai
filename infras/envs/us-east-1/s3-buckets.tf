# Tenant S3 buckets for document storage with optimized configuration
resource "aws_s3_bucket" "tenant" {
  for_each = var.tenants
  bucket   = "cloudable-kb-${var.env}-${var.region}-${each.value.name}"

  # Enable versioning for document history tracking
  tags = merge(local.tags, {
    Name       = "cloudable-kb-${var.env}-${var.region}-${each.value.name}"
    Tenant     = each.value.name
    Encryption = "aws:kms"
    Purpose    = "Knowledge Base Documents"
  })

  # Allow destruction for cost savings
  lifecycle {
    prevent_destroy = false
  }
}

# Create S3 bucket for document summaries for each tenant
resource "aws_s3_bucket" "summary" {
  for_each = var.tenants
  bucket   = "cloudable-summaries-${var.env}-${var.region}-${each.value.name}"

  # Enable rich tagging for cost allocation and management
  tags = merge(local.tags, {
    Name       = "cloudable-summaries-${var.env}-${var.region}-${each.value.name}"
    Tenant     = each.value.name
    Encryption = "AES256"
    Purpose    = "Document Summaries"
  })

  # Allow destruction for cost savings
  lifecycle {
    prevent_destroy = false
  }
}

# Create a central logging bucket for S3 access logs
resource "aws_s3_bucket" "access_logs" {
  bucket = "cloudable-access-logs-${var.env}-${var.region}"
  
  tags = merge(local.tags, {
    Name    = "cloudable-access-logs-${var.env}-${var.region}"
    Purpose = "S3 Access Logging"
  })

  # Allow destruction for cost savings
  lifecycle {
    prevent_destroy = false
  }
}