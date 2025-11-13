data "aws_iam_policy_document" "assume_bedrock" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
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
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ], 
        Resource = [
          "arn:aws:bedrock:${var.region}::foundation-model/anthropic.claude-*",
          "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "bedrock:GetFoundationModelAvailability",
          "bedrock:ListFoundationModels"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "bedrock-agent:InvokeAgent"
        ],
        Resource = "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:agent/*"
      },
      { 
        Effect = "Allow", 
        Action = ["lambda:InvokeFunction"], 
        Resource = aws_lambda_function.db_actions.arn 
      }
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
        Action = [
          "s3:GetObject", 
          "s3:ListBucket",
          "s3:GetObjectVersion"
        ],
        Resource = [
          aws_s3_bucket.tenant[each.key].arn,
          "${aws_s3_bucket.tenant[each.key].arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "rds:DescribeDBClusters",
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement",
          "rds-data:BeginTransaction",
          "rds-data:CommitTransaction",
          "rds-data:RollbackTransaction"
        ],
        Resource = aws_rds_cluster.this.arn
      },
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = aws_secretsmanager_secret.db.arn
      },
      {
        Effect = "Allow",
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ],
        Resource = aws_kms_key.rds.arn
      },
      {
        Effect = "Allow",
        Action = [
          "bedrock:InvokeModel"
        ],
        Resource = [
          "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v1"
        ]
      }
    ]
  })
}

# OpenSearch policy DISABLED - Using RDS with pgvector instead
# resource "aws_iam_policy" "kb_manager_opensearch" {
#   name        = "kb-manager-opensearch-${var.env}-${var.region}"
#   description = "IAM policy for KB Manager to access OpenSearch Serverless"
#   
#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "aoss:APIAccessAll"
#         ],
#         Resource = [
#           for tenant_key, tenant in var.tenants :
#           aws_opensearchserverless_collection.kb[tenant_key].arn
#         ]
#       },
#       {
#         Effect = "Allow",
#         Action = [
#           "aoss:CreateIndex",
#           "aoss:DeleteIndex",
#           "aoss:UpdateIndex",
#           "aoss:DescribeIndex",
#           "aoss:ReadDocument",
#           "aoss:WriteDocument",
#           "aoss:BatchGetDocument",
#           "aoss:Search"
#         ],
#         Resource = [
#           for tenant_key, tenant in var.tenants :
#           "${aws_opensearchserverless_collection.kb[tenant_key].arn}/*"
#         ]
#       }
#     ]
#   })
# }

