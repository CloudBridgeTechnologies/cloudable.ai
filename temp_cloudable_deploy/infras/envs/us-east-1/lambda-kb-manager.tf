# KB Manager Lambda for knowledge base operations
data "archive_file" "kb_manager_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/kb_manager"
  output_path = "${path.module}/kb_manager.zip"
}

data "archive_file" "kb_sync_trigger_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/kb_sync_trigger"
  output_path = "${path.module}/kb_sync_trigger.zip"
}

resource "aws_iam_role" "kb_manager" {
  name               = "kb-manager-${var.env}-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "kb_manager" {
  role = aws_iam_role.kb_manager.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion"
        ],
        Resource = flatten([
          for tenant_key, tenant in var.tenants : [
            "${aws_s3_bucket.tenant[tenant_key].arn}",
            "${aws_s3_bucket.tenant[tenant_key].arn}/*"
          ]
        ])
      },
      {
        Effect = "Allow",
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ],
        Resource = aws_kms_key.s3.arn
      },
      {
        Effect = "Allow",
        Action = [
          "bedrock-agent:StartIngestionJob",
          "bedrock-agent:GetIngestionJob",
          "bedrock-agent:ListIngestionJobs",
          "bedrock-agent:GetKnowledgeBase",
          "bedrock-agent:GetDataSource",
          "bedrock:StartIngestionJob",
          "bedrock:GetIngestionJob"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "bedrock-agent-runtime:Retrieve",
          "bedrock-agent-runtime:RetrieveAndGenerate"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "bedrock:Retrieve"
        ],
        Resource = [
          for tenant_key, tenant in var.tenants :
          "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ],
        Resource = [
          "arn:aws:bedrock:${var.region}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0",
          "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v2:0",
          "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.anthropic.claude-sonnet-4-20250514-v1:0"
        ]
      },
      {
        Effect = "Allow",
        Action = [
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
          "cloudwatch:PutMetricData"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "kb_manager_v2" {
  function_name    = "kb-manager-${var.env}"
  role             = aws_iam_role.kb_manager.arn
  filename         = data.archive_file.kb_manager_zip.output_path
  source_code_hash = data.archive_file.kb_manager_zip.output_base64sha256
  handler          = "main.handler"
  runtime          = "python3.12"
  timeout          = 900  # 15 minutes for long operations
  memory_size      = 512
  
  environment {
    variables = {
      REGION = var.region
      ENV    = var.env
      
      # Knowledge Base Configuration
      KB_ID_T001 = aws_bedrockagent_knowledge_base.tenant["t001"].id
      KB_ID_T002 = aws_bedrockagent_knowledge_base.tenant["t002"].id
      
      # S3 Bucket Configuration
      BUCKET_T001 = aws_s3_bucket.tenant["t001"].id
      BUCKET_T002 = aws_s3_bucket.tenant["t002"].id
      
      # Data Source IDs
      DS_ID_T001 = "GHEBQFMETM"
      DS_ID_T002 = "5VQ0ED2HAW"
      
      # Model Configuration
      CLAUDE_MODEL_ARN = "anthropic.claude-3-sonnet-20240229-v1:0"
      
      # Encryption Configuration
      S3_KMS_KEY_ARN = aws_kms_key.s3.arn
      
      # RDS Configuration for pgvector
      RDS_CLUSTER_ARN = aws_rds_cluster.this.arn
      RDS_SECRET_ARN = aws_secretsmanager_secret.db.arn
      RDS_DATABASE = "cloudable"
    }
  }
  
  tags = local.tags
}

resource "aws_iam_role" "kb_sync_trigger" {
  name               = "kb-sync-trigger-${var.env}-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "kb_sync_trigger" {
  role = aws_iam_role.kb_sync_trigger.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["lambda:InvokeFunction"],
        Resource = aws_lambda_function.kb_manager.arn
      }
    ]
  })
}

resource "aws_lambda_function" "kb_sync_trigger" {
  function_name    = "kb-sync-trigger-${var.env}"
  role             = aws_iam_role.kb_sync_trigger.arn
  filename         = "${path.module}/kb_sync_trigger.zip"
  source_code_hash = data.archive_file.kb_sync_trigger_zip.output_base64sha256
  handler          = "main.handler"
  runtime          = "python3.12"
  timeout          = 900  # 15 minutes
  
  environment {
    variables = {
      KB_MANAGER_FUNCTION = aws_lambda_function.kb_manager.function_name
    }
  }
  
  tags = local.tags
}

# API Gateway Integration for KB Manager
resource "aws_apigatewayv2_integration" "kb_manager" {
  api_id           = aws_apigatewayv2_api.http.id
  integration_type = "AWS_PROXY"
  
  connection_type           = "INTERNET"
  description               = "Knowledge Base Manager Lambda Integration"
  integration_method        = "POST"
  integration_uri           = aws_lambda_function.kb_manager.invoke_arn
  payload_format_version    = "2.0"
  timeout_milliseconds      = 30000
}

resource "aws_lambda_permission" "allow_api_kb_manager" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kb_manager.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
  statement_id  = "AllowAPIGatewayInvokeKBManager"
}

# API Routes for KB Manager
resource "aws_apigatewayv2_route" "kb_query" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /kb/query"
  target    = "integrations/${aws_apigatewayv2_integration.kb_manager.id}"
}

resource "aws_apigatewayv2_route" "kb_upload_url" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /kb/upload-url"
  target    = "integrations/${aws_apigatewayv2_integration.kb_manager.id}"
}

resource "aws_apigatewayv2_route" "kb_upload_form" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /kb/upload-form"
  target    = "integrations/${aws_apigatewayv2_integration.kb_manager.id}"
}

resource "aws_apigatewayv2_route" "kb_sync" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /kb/sync"
  target    = "integrations/${aws_apigatewayv2_integration.kb_manager.id}"
}

resource "aws_apigatewayv2_route" "kb_ingestion_status" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /kb/ingestion-status"
  target    = "integrations/${aws_apigatewayv2_integration.kb_manager.id}"
}

# Update S3 helper to allow KB sync function
resource "aws_lambda_permission" "allow_s3_kb_sync" {
  for_each      = var.tenants
  statement_id  = "AllowS3KBSyncInvocation-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kb_sync_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.tenant[each.key].arn
}