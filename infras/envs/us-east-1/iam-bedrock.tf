data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "assume_bedrock" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:agent/*"]
    }
  }
}

resource "aws_iam_role" "agent" {
  name               = "agent-role-${var.env}-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.assume_bedrock.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "agent" {
  role = aws_iam_role.agent.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { 
        Effect = "Allow", 
        Action = "bedrock:*", 
        Resource = "*" 
      },
      { Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = aws_lambda_function.db_actions.arn }
    ]
  })
}

resource "aws_iam_role" "kb" {
  for_each           = var.tenants
  name               = "kb-role-${var.env}-${var.region}-${each.value.name}"
  assume_role_policy = data.aws_iam_policy_document.assume_bedrock.json
  tags               = merge(local.tags, { tenant_id = each.key })
}

resource "aws_iam_role_policy" "kb" {
  for_each = var.tenants
  role     = aws_iam_role.kb[each.key].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:ListBucket"],
        Resource = [
          aws_s3_bucket.tenant[each.key].arn,
          "${aws_s3_bucket.tenant[each.key].arn}/*"
        ]
      }
    ]
  })
}

