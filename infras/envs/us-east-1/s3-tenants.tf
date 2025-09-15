resource "aws_s3_bucket" "tenant" {
  for_each = var.tenants
  bucket   = "cloudable-kb-${var.env}-${var.region}-${each.value.name}"

  tags = merge(local.tags, { tenant_id = each.key })
}

resource "aws_s3_bucket_public_access_block" "tenant" {
  for_each                = var.tenants
  bucket                  = aws_s3_bucket.tenant[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tenant" {
  for_each = var.tenants
  bucket   = aws_s3_bucket.tenant[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

