data "archive_file" "orchestrator_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambdas/orchestrator"
  output_path = "${path.module}/orchestrator.zip"
}

resource "aws_iam_role" "orchestrator" {
  name               = "orchestrator-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

data "aws_caller_identity" "current_orch" {}

resource "aws_iam_role_policy" "orchestrator" {
  role = aws_iam_role.orchestrator.id
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
          "bedrock:GetAgent",
          "bedrock:GetAgentAlias",
          "bedrock:InvokeAgent"
        ],
        Resource = [
          "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current_orch.account_id}:agent/*",
          "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current_orch.account_id}:agent-alias/*/*"
        ]
      },
      {
        Effect   = "Allow",
        Action   = ["bedrock:InvokeAgent"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:Retrieve"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "orchestrator" {
  function_name = "orchestrator-${var.env}"
  role          = aws_iam_role.orchestrator.arn
  filename      = data.archive_file.orchestrator_zip.output_path
  source_code_hash = data.archive_file.orchestrator_zip.output_base64sha256
  handler       = "main.handler"
  runtime       = "python3.12"
  timeout       = 20
  environment {
    variables = {
      REGION = var.region
    }
  }
  tags = local.tags
}

resource "aws_apigatewayv2_api" "http" {
  name          = "chat-api-${var.env}"
  protocol_type = "HTTP"
  tags          = local.tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.orchestrator.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_chat" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
  tags        = local.tags
}

resource "aws_lambda_permission" "allow_api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

