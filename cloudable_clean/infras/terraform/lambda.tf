###############################################
# Lambda Function for Cloudable.AI API
###############################################

# Lambda function
resource "aws_lambda_function" "kb_manager" {
  function_name    = "kb-manager-dev-core"
  description      = "API handler for Cloudable.AI Knowledge Base"
  filename         = "../lambda/lambda_deployment_package.zip"
  source_code_hash = filebase64sha256("../lambda/lambda_deployment_package.zip")
  
  handler          = "lambda_function.handler"
  runtime          = "python3.9"
  timeout          = 30
  memory_size      = 256
  
  role             = aws_iam_role.lambda_role.arn
  
  environment {
    variables = {
      LANGFUSE_HOST        = "https://eu.cloud.langfuse.com"
      LANGFUSE_PROJECT_ID  = "cmhz8tqhk00duad07xptpuo06"
      LANGFUSE_ORG_ID      = "cmhz8tcqz00dpad07ee341p57"
      LANGFUSE_PUBLIC_KEY  = "pk-lf-dfa751eb-07c4-4f93-8edf-222e93e95466"
      LANGFUSE_SECRET_KEY  = "sk-lf-35fe11d6-e8ad-4371-be13-b83a1dfec6bd"
      RDS_CLUSTER_ARN      = aws_rds_cluster.aurora_cluster.arn
      RDS_SECRET_ARN       = aws_secretsmanager_secret.aurora_secret.arn
      RDS_DATABASE         = "cloudable"
      CUSTOMER_STATUS_ENABLED = "true"
    }
  }
  
  tags = {
    Name        = "kb-manager-lambda"
    Environment = "dev"
    Project     = "Cloudable.AI"
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.lambda_log_group
  ]
}

# Log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/kb-manager-dev-core"
  retention_in_days = 14
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "kb-manager-role-core"
  
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

# IAM policy for CloudWatch Logs
resource "aws_iam_policy" "lambda_logs" {
  name        = "kb-manager-logs-policy"
  description = "IAM policy for logging from Lambda function"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# IAM policy for RDS access
resource "aws_iam_policy" "lambda_rds" {
  name        = "kb-manager-rds-policy"
  description = "IAM policy for RDS Data API access"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement",
          "rds-data:BeginTransaction",
          "rds-data:CommitTransaction",
          "rds-data:RollbackTransaction"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.aurora_secret.arn
      }
    ]
  })
}

# Attach logging policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_logs.arn
}

# Attach RDS policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_rds" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_rds.arn
}
