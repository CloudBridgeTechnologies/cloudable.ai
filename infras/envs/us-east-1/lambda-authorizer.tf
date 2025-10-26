# Lambda Authorizer for API Gateway

# Package the Lambda function code
data "archive_file" "authorizer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/authorizer"
  output_path = "${path.module}/authorizer.zip"
}

# CloudWatch Log Group for Lambda Authorizer
resource "aws_cloudwatch_log_group" "authorizer_logs" {
  name              = "/aws/lambda/api-authorizer-${var.env}"
  retention_in_days = 30
  tags = merge(local.tags, {
    Service = "Security"
  })
}

# IAM Role for Lambda Authorizer
resource "aws_iam_role" "authorizer" {
  name = "api-authorizer-role-${var.env}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
  
  tags = local.tags
}

# IAM Policy for Lambda Authorizer
resource "aws_iam_policy" "authorizer_policy" {
  name        = "api-authorizer-policy-${var.env}"
  description = "IAM policy for API Gateway Lambda authorizer"
  
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
          aws_cloudwatch_log_group.authorizer_logs.arn,
          "${aws_cloudwatch_log_group.authorizer_logs.arn}:*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query"
        ],
        Resource = aws_dynamodb_table.tenant_users.arn
      },
      {
        Effect = "Allow",
        Action = [
          "cognito-idp:DescribeUserPool",
          "cognito-idp:DescribeUserPoolClient"
        ],
        Resource = [
          aws_cognito_user_pool.main.arn,
          "${aws_cognito_user_pool.main.arn}/client/${aws_cognito_user_pool_client.api_client.id}"
        ]
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "authorizer_policy_attachment" {
  role       = aws_iam_role.authorizer.name
  policy_arn = aws_iam_policy.authorizer_policy.arn
}

# Lambda Authorizer function
resource "aws_lambda_function" "authorizer" {
  function_name    = "api-authorizer-${var.env}"
  role             = aws_iam_role.authorizer.arn
  filename         = data.archive_file.authorizer_zip.output_path
  source_code_hash = data.archive_file.authorizer_zip.output_base64sha256
  handler          = "main.handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128
  
  environment {
    variables = {
      USER_POOL_ID    = aws_cognito_user_pool.main.id
      USER_POOL_REGION = var.region
      CLIENT_ID       = aws_cognito_user_pool_client.api_client.id
      TENANT_TABLE    = aws_dynamodb_table.tenant_users.name
      ENV             = var.env
    }
  }
  
  tracing_config {
    mode = "Active"
  }
  
  tags = merge(local.tags, {
    Service = "Security"
  })
}

# API Gateway Lambda Authorizer (REST API)
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "cognito-jwt-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.secure_api.id
  authorizer_uri         = aws_lambda_function.authorizer.invoke_arn
  authorizer_credentials = aws_iam_role.authorizer_invocation.arn
  type                   = "REQUEST"
  identity_source        = "method.request.header.Authorization"
}

# IAM Role for API Gateway to invoke the authorizer
resource "aws_iam_role" "authorizer_invocation" {
  name = "api-gateway-auth-invocation-${var.env}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })
  
  tags = local.tags
}

# IAM Policy to allow API Gateway to invoke the authorizer
resource "aws_iam_role_policy" "authorizer_invocation" {
  name = "api-gateway-auth-invocation-policy-${var.env}"
  role = aws_iam_role.authorizer_invocation.id
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = "lambda:InvokeFunction",
      Effect   = "Allow",
      Resource = aws_lambda_function.authorizer.arn
    }]
  })
}

# Lambda permission for API Gateway to invoke the authorizer
resource "aws_lambda_permission" "authorizer_permission" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.secure_api.execution_arn}/*"
}

# HTTP API Lambda Authorizer
resource "aws_apigatewayv2_authorizer" "http_authorizer" {
  name                              = "lambda-authorizer"
  api_id                            = aws_apigatewayv2_api.http.id
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = aws_lambda_function.authorizer.invoke_arn
  identity_sources                  = ["$request.header.Authorization"]
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = false
}
