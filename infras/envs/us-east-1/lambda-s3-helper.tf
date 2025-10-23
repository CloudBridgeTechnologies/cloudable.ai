# S3 Helper Lambda for document preprocessing
data "archive_file" "s3_helper_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/s3_helper"
  output_path = "${path.module}/s3_helper.zip"
}

resource "aws_iam_role" "s3_helper" {
  name               = "s3-helper-${var.env}-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "s3_helper" {
  role = aws_iam_role.s3_helper.id
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
          "s3:GetObjectVersion",
          "s3:GetObjectTagging",
          "s3:PutObjectTagging"
        ],
        Resource = flatten([
          for tenant_key, tenant in var.tenants : [
            "${aws_s3_bucket.tenant[tenant_key].arn}/*"
          ]
        ])
      },
      {
        Effect = "Allow",
        Action = [
          "lambda:InvokeFunction"
        ],
        Resource = aws_lambda_function.kb_sync_trigger.arn
      },
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

resource "aws_lambda_function" "s3_helper" {
  function_name    = "s3-helper-${var.env}"
  role            = aws_iam_role.s3_helper.arn
  filename        = data.archive_file.s3_helper_zip.output_path
  source_code_hash = data.archive_file.s3_helper_zip.output_base64sha256
  handler         = "main.handle_s3_event"
  runtime         = "python3.12"
  timeout         = 900  # Increased to 15 minutes
  
  environment {
    variables = {
      REGION = var.region
      ENV    = var.env
      KB_SYNC_FUNCTION = aws_lambda_function.kb_sync_trigger.function_name
    }
  }
  
  tags = local.tags
}

# S3 Event Notification to process documents
resource "aws_s3_bucket_notification" "s3_helper" {
  for_each = var.tenants
  bucket   = aws_s3_bucket.tenant[each.key].id

  lambda_function {
    id                  = "s3-helper-raw"
    lambda_function_arn = aws_lambda_function.s3_helper.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "documents/raw/"
    filter_suffix       = ".pdf"
  }

  lambda_function {
    id                  = "document-summarizer-processed"
    lambda_function_arn = aws_lambda_function.document_summarizer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "documents/processed/"
    filter_suffix       = "_processed_summary.pdf" # Changed suffix to avoid conflict
  }

  lambda_function {
    id                  = "kb-sync-processed"
    lambda_function_arn = aws_lambda_function.kb_sync_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "documents/processed/"
    filter_suffix       = "_processed_kb.pdf" # Changed suffix to avoid conflict
  }

  depends_on = [
    aws_lambda_permission.allow_s3_helper,
    aws_lambda_permission.allow_document_summarizer,
    aws_lambda_permission.allow_s3_kb_sync
  ]
}

# Permission for S3 to invoke Lambda
resource "aws_lambda_permission" "allow_s3_helper" {
  for_each      = var.tenants
  statement_id  = "AllowS3Invocation-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_helper.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.tenant[each.key].arn
}
