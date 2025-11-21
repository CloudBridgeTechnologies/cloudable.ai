# Security Group for Lambda functions
resource "aws_security_group" "lambda_summarizer_sg" {
  count       = length(var.lambda_subnet_ids) > 0 ? 1 : 0
  name        = "lambda-sg-${var.env}"
  description = "Security group for Lambda functions"
  vpc_id      = data.aws_vpc.main[0].id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "lambda-sg-${var.env}"
  })
}

# Data source for VPC (simplified to avoid circular dependency)
data "aws_vpc" "main" {
  count   = length(var.lambda_subnet_ids) > 0 ? 1 : 0
  default = true
}

# Document Summarizer Lambda for generating document summaries
data "archive_file" "document_summarizer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/document_summarizer"
  output_path = "${path.module}/document_summarizer.zip"
}

# Create IAM role with least privilege for document summarizer lambda
resource "aws_iam_role" "document_summarizer" {
  name               = "document-summarizer-${var.env}-${var.region}"
  description        = "IAM role for document summarizer Lambda function"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  # Add permission boundary for organizational governance
  permissions_boundary = var.permission_boundary_arn

  tags = merge(local.tags, {
    Service = "DocumentSummarization"
  })
}

# Create CloudWatch Logs policy - scoped to specific log group
resource "aws_iam_policy" "document_summarizer_logs" {
  name        = "document-summarizer-logs-${var.env}-${var.region}"
  description = "IAM policy for document summarizer Lambda CloudWatch logs"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = [
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/document-summarizer-${var.env}:*"
        ]
      }
    ]
  })
}

# Create S3 read policy for tenant buckets
resource "aws_iam_policy" "document_summarizer_s3_read" {
  name        = "document-summarizer-s3-read-${var.env}-${var.region}"
  description = "IAM policy for document summarizer Lambda to read from tenant buckets"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:HeadObject",
          "s3:ListBucket"
        ],
        Resource = flatten([
          for tenant_key, tenant in var.tenants : [
            "${aws_s3_bucket.tenant[tenant_key].arn}/*",
            aws_s3_bucket.tenant[tenant_key].arn
          ]
        ])
      }
    ]
  })
}

# Create S3 write policy for summary buckets
resource "aws_iam_policy" "document_summarizer_s3_write" {
  name        = "document-summarizer-s3-write-${var.env}-${var.region}"
  description = "IAM policy for document summarizer Lambda to write to summary buckets"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject"
        ],
        Resource = flatten([
          for tenant_key, tenant in var.tenants : [
            "${aws_s3_bucket.summary[tenant_key].arn}/*",
            aws_s3_bucket.summary[tenant_key].arn
          ]
        ])
      }
    ]
  })
}

# Create Bedrock policy for Claude model access
resource "aws_iam_policy" "document_summarizer_bedrock" {
  name        = "document-summarizer-bedrock-${var.env}-${var.region}"
  description = "IAM policy for document summarizer Lambda to invoke Bedrock models"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "bedrock:InvokeModel"
        ],
        Resource = [
          "arn:aws:bedrock:${var.region}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "textract:DetectDocumentText"
        ],
        Resource = "*"
      }
    ]
  })
}

# Create KMS policy for encryption/decryption
resource "aws_iam_policy" "document_summarizer_kms" {
  name        = "document-summarizer-kms-${var.env}-${var.region}"
  description = "IAM policy for document summarizer Lambda to use KMS encryption"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ],
        Resource = aws_kms_key.s3.arn
      }
    ]
  })
}

# Create SQS policy for dead letter queue
resource "aws_iam_policy" "document_summarizer_sqs" {
  name        = "document-summarizer-sqs-${var.env}-${var.region}"
  description = "IAM policy for document summarizer Lambda to use SQS DLQ"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "sqs:SendMessage"
        ],
        Resource = [
          aws_sqs_queue.document_summarizer_dlq.arn
        ]
      }
    ]
  })
}

# Attach policies to role
resource "aws_iam_role_policy_attachment" "document_summarizer_logs_attach" {
  role       = aws_iam_role.document_summarizer.name
  policy_arn = aws_iam_policy.document_summarizer_logs.arn
}

resource "aws_iam_role_policy_attachment" "document_summarizer_s3_read_attach" {
  role       = aws_iam_role.document_summarizer.name
  policy_arn = aws_iam_policy.document_summarizer_s3_read.arn
}

resource "aws_iam_role_policy_attachment" "document_summarizer_s3_write_attach" {
  role       = aws_iam_role.document_summarizer.name
  policy_arn = aws_iam_policy.document_summarizer_s3_write.arn
}

resource "aws_iam_role_policy_attachment" "document_summarizer_bedrock_attach" {
  role       = aws_iam_role.document_summarizer.name
  policy_arn = aws_iam_policy.document_summarizer_bedrock.arn
}

resource "aws_iam_role_policy_attachment" "document_summarizer_kms_attach" {
  role       = aws_iam_role.document_summarizer.name
  policy_arn = aws_iam_policy.document_summarizer_kms.arn
}

resource "aws_iam_role_policy_attachment" "document_summarizer_sqs_attach" {
  role       = aws_iam_role.document_summarizer.name
  policy_arn = aws_iam_policy.document_summarizer_sqs.arn
}

# Create Lambda function with optimal configuration
resource "aws_lambda_function" "document_summarizer" {
  function_name    = "document-summarizer-${var.env}"
  description      = "Generates document summaries using Amazon Bedrock"
  role             = aws_iam_role.document_summarizer.arn
  filename         = data.archive_file.document_summarizer_zip.output_path
  source_code_hash = data.archive_file.document_summarizer_zip.output_base64sha256
  handler          = "main.handle_document_event"
  runtime          = "python3.12"

  # Configure generous timeout and memory for PDF processing and AI model calls
  timeout     = 900  # 15 minutes for processing very large documents
  memory_size = 2048 # 2GB for handling large PDFs and chunked summarization

  # Production-ready function configuration
  reserved_concurrent_executions = 10 # Limit concurrent executions

  # Environment variables
  environment {
    variables = {
      REGION                = var.region
      ENV                   = var.env
      CLAUDE_MODEL_ID       = "anthropic.claude-3-sonnet-20240229-v1:0"
      MAX_CHUNK_SIZE        = "8000"
      SUMMARY_BUCKET_SUFFIX = "summaries"
      # Add environment-specific configuration
      LOG_LEVEL = var.env == "prod" ? "INFO" : "DEBUG"
    }
  }

  # VPC configuration for enhanced security (only if subnets are provided)
  dynamic "vpc_config" {
    for_each = length(var.lambda_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.lambda_subnet_ids
      security_group_ids = [aws_security_group.lambda_sg[0].id]
    }
  }

  # Dead letter queue for failed events
  dead_letter_config {
    target_arn = aws_sqs_queue.document_summarizer_dlq.arn
  }

  # Enable X-Ray tracing for performance monitoring
  tracing_config {
    mode = "Active"
  }

  # Add comprehensive tags for resource governance
  tags = merge(local.tags, {
    Service     = "DocumentSummarization"
    Owner       = "DataProcessing"
    CostCenter  = "AI-Processing"
    Environment = var.env
  })

  depends_on = [
    aws_iam_role_policy_attachment.document_summarizer_logs_attach,
    aws_iam_role_policy_attachment.document_summarizer_s3_read_attach,
    aws_iam_role_policy_attachment.document_summarizer_s3_write_attach,
    aws_iam_role_policy_attachment.document_summarizer_bedrock_attach,
    aws_iam_role_policy_attachment.document_summarizer_kms_attach,
    aws_iam_role_policy_attachment.document_summarizer_sqs_attach
  ]
}

# Dead letter queue for failed summarization events
resource "aws_sqs_queue" "document_summarizer_dlq" {
  name                       = "document-summarizer-dlq-${var.env}"
  delay_seconds              = 0
  max_message_size           = 262144  # 256 KB
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 30

  # Enable encryption
  sqs_managed_sse_enabled = true

  tags = merge(local.tags, {
    Service = "DocumentSummarization"
  })
}

# S3 bucket configurations are defined in s3-buckets.tf

# S3 Event Notification to trigger document summarization
resource "aws_lambda_permission" "allow_document_summarizer" {
  for_each      = var.tenants
  statement_id  = "AllowS3SummarizerInvocation-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.document_summarizer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.tenant[each.key].arn
}
