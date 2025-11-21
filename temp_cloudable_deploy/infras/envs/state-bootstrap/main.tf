locals {
  name_prefix = "${var.project}-${var.env}"
  tags = {
    project = var.project
    env     = var.env
  }
}

resource "aws_s3_bucket" "tf_state" {
  bucket        = "${var.project}-tfstate-${var.env}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = "${local.name_prefix}-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  tags = local.tags
}

data "aws_caller_identity" "current" {}

output "state_bucket" { value = aws_s3_bucket.tf_state.bucket }
output "lock_table"   { value = aws_dynamodb_table.tf_lock.name }

resource "aws_iam_role" "deployer" {
  count              = var.create_deployer_role ? 1 : 0
  name               = "${local.name_prefix}-tf-deployer"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" },
      Action = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "deployer" {
  for_each = var.create_deployer_role ? toset(var.deployer_managed_policies) : []
  role     = aws_iam_role.deployer[0].name
  policy_arn = each.value
}

output "deployer_role_arn" {
  value       = try(aws_iam_role.deployer[0].arn, null)
  description = "IAM role to assume for Terraform deploys"
}

