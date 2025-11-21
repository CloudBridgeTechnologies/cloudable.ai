data "archive_file" "orchestrator_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/orchestrator"
  output_path = "${path.module}/orchestrator.zip"
}

resource "aws_iam_role" "orchestrator" {
  name               = "orchestrator-${var.env}-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

data "aws_caller_identity" "current_orch" {}

resource "aws_iam_role_policy" "orchestrator" {
  name = "orchestrator-policy-${var.env}"
  role = aws_iam_role.orchestrator.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogGroup", 
          "logs:CreateLogStream", 
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ],
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow",
        Action = [
          "bedrock:GetAgent",
          "bedrock:GetAgentAlias",
          "bedrock:InvokeAgent",
          "bedrock-agent:InvokeAgent"
        ],
        Resource = [
          "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current_orch.account_id}:agent/*",
          "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current_orch.account_id}:agent-alias/*/*"
        ]
      },
      {
        Effect   = "Allow",
        Action   = [
          "bedrock:InvokeAgent",
          "bedrock-agent:InvokeAgent"
        ],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = [
          "bedrock:InvokeModel", 
          "bedrock:InvokeModelWithResponseStream",
          "bedrock-runtime:InvokeModel",
          "bedrock-runtime:InvokeStream",
          "bedrock-agent:Retrieve",
          "bedrock-runtime:Retrieve"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ],
        Resource = aws_kms_key.s3.arn
      },
      {
        Effect = "Allow",
        Action = [
          "lambda:InvokeFunction"
        ],
        Resource = aws_lambda_function.kb_manager.arn
      }
    ]
  })
}

resource "aws_lambda_function" "orchestrator" {
  function_name    = "orchestrator-${var.env}"
  role             = aws_iam_role.orchestrator.arn
  filename         = data.archive_file.orchestrator_zip.output_path
  source_code_hash = data.archive_file.orchestrator_zip.output_base64sha256
  handler          = "main.handler"
  runtime          = "python3.12"
  timeout          = 900 # Increased to 15 minutes
  environment {
    variables = {
      REGION = var.region
      ENV    = var.env
      KB_MANAGER_FUNCTION_NAME = aws_lambda_function.kb_manager.function_name
    }
  }
  tags = local.tags
}

# CloudWatch Log Group for Lambda with explicit retention
# Using lifecycle = { ignore_changes = [name] } to prevent conflicts with auto-created log groups
# This resource should be imported using: terraform import aws_cloudwatch_log_group.orchestrator "/aws/lambda/orchestrator-dev"
resource "aws_cloudwatch_log_group" "orchestrator" {
  name              = "/aws/lambda/${aws_lambda_function.orchestrator.function_name}-v2"
  retention_in_days = 30
  tags              = local.tags
  
  lifecycle {
    # Naming with v2 suffix to prevent conflicts with auto-created log groups
    # ignore_changes  = [name]
    # Allow deletion in Terraform destroy operations
    prevent_destroy = false
  }
}

# Permissions for API Gateway to invoke Lambda
resource "aws_lambda_permission" "allow_api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.function_name
  principal     = "apigateway.amazonaws.com"
  
  # The source_arn has the format: arn:aws:execute-api:region:account-id:api-id/stage/method/resource-path
  source_arn    = "${aws_api_gateway_rest_api.secure_api.execution_arn}/*/*/*"
}

# Lambda Integration with API Gateway v2 (HTTP API)
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.orchestrator.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000
}

# HTTP API Chat Route
resource "aws_apigatewayv2_route" "post_chat" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /chat"
  
  # If we have an authorizer
  # authorization_type = "CUSTOM"
  # authorizer_id      = aws_apigatewayv2_authorizer.http_authorizer.id
  
  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}