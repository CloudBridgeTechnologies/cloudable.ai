resource "aws_kms_key" "rds" {
  description         = "KMS key for RDS ${var.env}"
  enable_key_rotation = true
  tags                = local.tags
}

resource "aws_kms_key" "s3" {
  description         = "KMS key for S3 ${var.env}"
  enable_key_rotation = true
  tags                = local.tags
}

