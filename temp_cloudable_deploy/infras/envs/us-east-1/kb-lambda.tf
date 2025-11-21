# Lambda function configurations for Cloudable.AI KB Manager with pgvector support

# KB Manager Lambda function
resource "aws_lambda_function" "kb_manager" {
  function_name    = "kb-manager-${var.environment}"
  filename         = "${path.module}/kb_manager.zip"
  source_code_hash = filebase64sha256("${path.module}/kb_manager.zip")
  
  handler          = "main.handler"
  runtime          = "python3.9"
  timeout          = 900
  memory_size      = 512
  
  role             = aws_iam_role.kb_manager_role.arn
  
  environment {
    variables = {
      RDS_CLUSTER_ARN  = aws_rds_cluster.aurora_cluster.arn
      RDS_SECRET_ARN   = aws_secretsmanager_secret.db_credentials.arn
      RDS_DATABASE     = var.db_name
      ENV              = var.environment
      REGION           = var.region
      # Tenant-specific environment variables will be added here
      KB_ID_T001       = aws_bedrock_knowledge_base.kb_tenant_1.id
      DS_ID_T001       = aws_bedrock_data_source.ds_tenant_1.id
      BUCKET_T001      = aws_s3_bucket.tenant_1.bucket
      KB_ID_ACME       = aws_bedrock_knowledge_base.kb_tenant_acme.id
      DS_ID_ACME       = aws_bedrock_data_source.ds_tenant_acme.id
      BUCKET_ACME      = aws_s3_bucket.tenant_acme.bucket
      KB_ID_GLOBEX     = aws_bedrock_knowledge_base.kb_tenant_globex.id
      DS_ID_GLOBEX     = aws_bedrock_data_source.ds_tenant_globex.id
      BUCKET_GLOBEX    = aws_s3_bucket.tenant_globex.bucket
      S3_KMS_KEY_ARN   = aws_kms_key.s3_encryption_key.arn
      CLAUDE_MODEL_ARN = "anthropic.claude-3-sonnet-20240229-v1:0"
    }
  }
  
  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
  
  depends_on = [aws_rds_cluster_instance.aurora_instances]
}

# IAM Role for the KB Manager Lambda
resource "aws_iam_role" "kb_manager_role" {
  name = "kb-manager-role-${var.environment}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for KB Manager Lambda
resource "aws_iam_policy" "kb_manager_policy" {
  name = "kb-manager-policy-${var.environment}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [
          for bucket in [
            aws_s3_bucket.tenant_1.arn,
            aws_s3_bucket.tenant_acme.arn,
            aws_s3_bucket.tenant_globex.arn
          ] : "${bucket}/*"
        ]
      },
      {
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.tenant_1.arn,
          aws_s3_bucket.tenant_acme.arn,
          aws_s3_bucket.tenant_globex.arn
        ]
      },
      {
        Action = [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement"
        ]
        Effect   = "Allow"
        Resource = aws_rds_cluster.aurora_cluster.arn
      },
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.db_credentials.arn
      },
      {
        Action = [
          "bedrock:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Effect   = "Allow"
        Resource = [
          aws_kms_key.s3_encryption_key.arn,
          aws_kms_key.db_encryption_key.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "kb_manager_policy_attachment" {
  role       = aws_iam_role.kb_manager_role.name
  policy_arn = aws_iam_policy.kb_manager_policy.arn
}

# Create KMS key for S3 encryption
resource "aws_kms_key" "s3_encryption_key" {
  description             = "KMS key for S3 encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

# S3 buckets for tenants
resource "aws_s3_bucket" "tenant_1" {
  bucket = "cloudable-kb-${var.environment}-${var.region}-${formatdate("YYYYMMDDhhmmss", timestamp())}-t001"
}

resource "aws_s3_bucket" "tenant_acme" {
  bucket = "cloudable-kb-${var.environment}-${var.region}-${formatdate("YYYYMMDDhhmmss", timestamp())}-acme"
}

resource "aws_s3_bucket" "tenant_globex" {
  bucket = "cloudable-kb-${var.environment}-${var.region}-${formatdate("YYYYMMDDhhmmss", timestamp())}-globex"
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "tenant_1_encryption" {
  bucket = aws_s3_bucket.tenant_1.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_encryption_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tenant_acme_encryption" {
  bucket = aws_s3_bucket.tenant_acme.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_encryption_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tenant_globex_encryption" {
  bucket = aws_s3_bucket.tenant_globex.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_encryption_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Lambda function code with pgvector fixes
data "archive_file" "kb_manager_package" {
  type        = "zip"
  output_path = "${path.module}/kb_manager.zip"

  source {
    content = file("${path.module}/../lambdas/kb_manager/main.py")
    filename = "main.py"
  }

  source {
    content = file("${path.module}/../lambdas/kb_manager/rest_adapter.py")
    filename = "rest_adapter.py"
  }
  
  # Add any other necessary Lambda files
  dynamic "source" {
    for_each = fileset("${path.module}/../lambdas/kb_manager", "*.py")
    content {
      content  = file("${path.module}/../lambdas/kb_manager/${source.value}")
      filename = source.value
    }
  }

  source {
    content = <<-EOF
      """
      This file indicates that the pgvector fix has been applied to the Lambda function.
      Fix applied: ${timestamp()}
      
      Changes made:
      1. Updated vector format for pgvector compatibility (using brackets instead of braces)
      2. Fixed JSON parsing in rest_adapter to handle both string and dict formats
      3. Changed vector parameter format for RDS Data API compatibility
      """
      
      # Version of the fix
      PGVECTOR_FIX_VERSION = '1.0.0'
    EOF
    filename = "pgvector_fix.py"
  }
}

# Bedrock resources (simplified for example)
resource "aws_bedrock_knowledge_base" "kb_tenant_1" {
  name        = "cloudable-kb-t001-${var.environment}"
  description = "Knowledge base for tenant T001"
  
  storage_configuration {
    type = "RDS"
    rds_configuration {
      resource_arn = aws_rds_cluster.aurora_cluster.arn
      credentials_secret_arn = aws_secretsmanager_secret.db_credentials.arn
      database_name = var.db_name
      table_name = "kb_vectors_t001"
    }
  }
}

resource "aws_bedrock_knowledge_base" "kb_tenant_acme" {
  name        = "cloudable-kb-acme-${var.environment}"
  description = "Knowledge base for tenant ACME"
  
  storage_configuration {
    type = "RDS"
    rds_configuration {
      resource_arn = aws_rds_cluster.aurora_cluster.arn
      credentials_secret_arn = aws_secretsmanager_secret.db_credentials.arn
      database_name = var.db_name
      table_name = "kb_vectors_acme"
    }
  }
}

resource "aws_bedrock_knowledge_base" "kb_tenant_globex" {
  name        = "cloudable-kb-globex-${var.environment}"
  description = "Knowledge base for tenant Globex"
  
  storage_configuration {
    type = "RDS"
    rds_configuration {
      resource_arn = aws_rds_cluster.aurora_cluster.arn
      credentials_secret_arn = aws_secretsmanager_secret.db_credentials.arn
      database_name = var.db_name
      table_name = "kb_vectors_globex"
    }
  }
}

# Bedrock data sources (simplified)
resource "aws_bedrock_data_source" "ds_tenant_1" {
  knowledge_base_id = aws_bedrock_knowledge_base.kb_tenant_1.id
  name              = "s3-datasource-t001"
  data_source_configuration {
    s3_configuration {
      bucket_name = aws_s3_bucket.tenant_1.bucket
      inclusion_prefixes = ["documents/"]
    }
  }
}

resource "aws_bedrock_data_source" "ds_tenant_acme" {
  knowledge_base_id = aws_bedrock_knowledge_base.kb_tenant_acme.id
  name              = "s3-datasource-acme"
  data_source_configuration {
    s3_configuration {
      bucket_name = aws_s3_bucket.tenant_acme.bucket
      inclusion_prefixes = ["documents/"]
    }
  }
}

resource "aws_bedrock_data_source" "ds_tenant_globex" {
  knowledge_base_id = aws_bedrock_knowledge_base.kb_tenant_globex.id
  name              = "s3-datasource-globex"
  data_source_configuration {
    s3_configuration {
      bucket_name = aws_s3_bucket.tenant_globex.bucket
      inclusion_prefixes = ["documents/"]
    }
  }
}
