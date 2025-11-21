# S3 bucket configuration for Cloudable.AI
resource "aws_s3_bucket" "tenant" {
  for_each      = var.tenants
  bucket        = "cloudable-kb-${var.env}-${var.region}-20251024142435-${each.value.name}"
  force_destroy = true  # Allow deleting non-empty buckets

  # Enable versioning for document history tracking
  tags = merge(local.tags, {
    Name       = "cloudable-kb-${var.env}-${var.region}-20251024142435-${each.value.name}"
    Tenant     = each.value.name
    Encryption = "aws:kms"
    Purpose    = "Knowledge Base Documents"
  })

  # Allow destruction for testing purposes
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket" "summary" {
  for_each      = var.tenants
  bucket        = "cloudable-summaries-${var.env}-${var.region}-20251024142435-${each.value.name}"
  force_destroy = true  # Allow deleting non-empty buckets

  tags = merge(local.tags, {
    Name       = "cloudable-summaries-${var.env}-${var.region}-20251024142435-${each.value.name}"
    Tenant     = each.value.name
    Encryption = "aws:kms"
    Purpose    = "Document Summaries Storage"
  })

  # Allow destruction for testing purposes
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket" "access_logs" {
  bucket        = "cloudable-access-logs-${var.env}-${var.region}-20251024142435"
  force_destroy = true  # Allow deleting non-empty buckets

  tags = merge(local.tags, {
    Name    = "cloudable-access-logs-${var.env}-${var.region}-20251024142435"
    Service = "S3Logging"
  })

  # Allow destruction for testing purposes
  lifecycle {
    prevent_destroy = false
  }
}

# Block public access for security
resource "aws_s3_bucket_public_access_block" "tenant" {
  for_each                = var.tenants
  bucket                  = aws_s3_bucket.tenant[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "summary" {
  for_each                = var.tenants
  bucket                  = aws_s3_bucket.summary[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for document history
resource "aws_s3_bucket_versioning" "tenant" {
  for_each = var.tenants
  bucket   = aws_s3_bucket.tenant[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "summary" {
  for_each = var.tenants
  bucket   = aws_s3_bucket.summary[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Configure server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "tenant" {
  for_each = var.tenants
  bucket   = aws_s3_bucket.tenant[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "summary" {
  for_each = var.tenants
  bucket   = aws_s3_bucket.summary[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Configure bucket policies
resource "aws_s3_bucket_policy" "tenant" {
  for_each = var.tenants
  bucket   = aws_s3_bucket.tenant[each.key].id
  policy   = data.aws_iam_policy_document.tenant_bucket_policy[each.key].json
}

data "aws_iam_policy_document" "tenant_bucket_policy" {
  for_each = var.tenants

  statement {
    sid    = "EnforceHTTPS"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::cloudable-kb-${var.env}-${var.region}-20251024142435-${each.value.name}",
      "arn:aws:s3:::cloudable-kb-${var.env}-${var.region}-20251024142435-${each.value.name}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "AllowAccessFromBedrockRole"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::cloudable-kb-${var.env}-${var.region}-20251024142435-${each.value.name}",
      "arn:aws:s3:::cloudable-kb-${var.env}-${var.region}-20251024142435-${each.value.name}/*"
    ]
  }
}

# Configure CORS for tenant buckets
resource "aws_s3_bucket_cors_configuration" "tenant" {
  for_each = var.tenants
  bucket   = aws_s3_bucket.tenant[each.key].id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE"]
    allowed_origins = ["https://*.${var.domain_name}"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Configure lifecycle rules
resource "aws_s3_bucket_lifecycle_configuration" "tenant" {
  for_each = var.tenants
  bucket   = aws_s3_bucket.tenant[each.key].id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
  }

  rule {
    id     = "cleanup-temp-files"
    status = "Enabled"

    filter {
      prefix = "temp/"
    }

    expiration {
      days = 7
    }
  }
  
  depends_on = [
    aws_s3_bucket_versioning.tenant,
    aws_s3_bucket_server_side_encryption_configuration.tenant
  ]
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "summary" {
  for_each = var.tenants
  bucket   = aws_s3_bucket.summary[each.key].id

  rule {
    id     = "archive-old-summaries"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
  
  depends_on = [
    aws_s3_bucket_versioning.summary,
    aws_s3_bucket_server_side_encryption_configuration.summary
  ]
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }
  }
  
  depends_on = [
    aws_s3_bucket_server_side_encryption_configuration.access_logs
  ]
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Configure logging
resource "aws_s3_bucket_logging" "tenant" {
  for_each      = var.tenants
  bucket        = aws_s3_bucket.tenant[each.key].id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "tenant-bucket-logs/${each.value.name}/"
}

resource "aws_s3_bucket_logging" "summary" {
  for_each      = var.tenants
  bucket        = aws_s3_bucket.summary[each.key].id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "summary-bucket-logs/${each.value.name}/"
}

# Configure intelligent tiering
# Replaced with standard lifecycle rule as intelligent tiering had incorrect configuration
resource "aws_s3_bucket_lifecycle_configuration" "tenant_tiering" {
  for_each = var.tenants
  bucket   = aws_s3_bucket.tenant[each.key].id

  rule {
    id     = "archive-old-data"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 180
      storage_class = "DEEP_ARCHIVE"
    }
  }
  
  depends_on = [
    aws_s3_bucket_versioning.tenant,
    aws_s3_bucket_server_side_encryption_configuration.tenant,
    aws_s3_bucket_lifecycle_configuration.tenant
  ]
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# S3 event notifications are defined in lambda-s3-helper.tf

