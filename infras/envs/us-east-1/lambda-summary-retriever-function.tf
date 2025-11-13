# Summary Retriever Lambda for API access to document summaries
data "archive_file" "summary_retriever_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/summary_retriever"
  output_path = "${path.module}/summary_retriever.zip"
}

resource "aws_iam_role" "summary_retriever" {
  name               = "summary-retriever-${var.env}-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "summary_retriever" {
  role = aws_iam_role.summary_retriever.id
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
          "s3:HeadObject",
          "s3:ListBucket"
        ],
        Resource = flatten([
          for tenant_key, tenant in var.tenants : [
            "${aws_s3_bucket.tenant[tenant_key].arn}/*",
            aws_s3_bucket.tenant[tenant_key].arn,
            "${aws_s3_bucket.summary[tenant_key].arn}/*",
            aws_s3_bucket.summary[tenant_key].arn
          ]
        ])
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

resource "aws_lambda_function" "summary_retriever" {
  function_name    = "summary-retriever-${var.env}"
  role             = aws_iam_role.summary_retriever.arn
  filename         = data.archive_file.summary_retriever_zip.output_path
  source_code_hash = data.archive_file.summary_retriever_zip.output_base64sha256
  handler          = "main.handler"
  runtime          = "python3.12"
  timeout          = 900  # 15 minutes
  memory_size      = 256
  
  environment {
    variables = {
      REGION              = var.region
      ENV                 = var.env
      SUMMARY_BUCKET_SUFFIX = "summaries"
    }
  }
  
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "summary_retriever" {
  name              = "/aws/lambda/summary-retriever-${var.env}"
  retention_in_days = 30
  tags              = local.tags
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "allow_api_summary_retriever" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.summary_retriever.function_name
  principal     = "apigateway.amazonaws.com"
  
  # The source_arn has the format: arn:aws:execute-api:region:account-id:api-id/stage/method/resource-path
  source_arn    = "${aws_api_gateway_rest_api.secure_api.execution_arn}/*/*/*"
}

