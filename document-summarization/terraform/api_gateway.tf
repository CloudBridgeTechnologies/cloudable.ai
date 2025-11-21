resource "aws_iam_role" "api_lambda_role" {
  name = "document-api-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "api_lambda_policy" {
  name = "document-api-policy"
  role = aws_iam_role.api_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.documents.arn}/*",
          "${aws_s3_bucket.documents.arn}"
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "upload_handler" {
  filename         = "../lambda/upload_handler.zip"
  function_name    = "document-upload-handler"
  role            = aws_iam_role.api_lambda_role.arn
  handler         = "upload_handler.lambda_handler"
  runtime         = "python3.12"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.documents.id
    }
  }
}

resource "aws_lambda_function" "summary_retriever" {
  filename         = "../lambda/summary_retriever.zip"
  function_name    = "document-summary-retriever"
  role            = aws_iam_role.api_lambda_role.arn
  handler         = "summary_retriever.lambda_handler"
  runtime         = "python3.12"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.documents.id
    }
  }
}

resource "aws_apigatewayv2_api" "document_api" {
  name          = "document-summarization-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.document_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "upload_integration" {
  api_id             = aws_apigatewayv2_api.document_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.upload_handler.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_integration" "summary_integration" {
  api_id             = aws_apigatewayv2_api.document_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.summary_retriever.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "upload_route" {
  api_id    = aws_apigatewayv2_api.document_api.id
  route_key = "POST /upload"
  target    = "integrations/${aws_apigatewayv2_integration.upload_integration.id}"
}

resource "aws_apigatewayv2_route" "summary_route" {
  api_id    = aws_apigatewayv2_api.document_api.id
  route_key = "GET /summary/{documentName}"
  target    = "integrations/${aws_apigatewayv2_integration.summary_integration.id}"
}

resource "aws_lambda_permission" "upload_api_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.document_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "summary_api_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.summary_retriever.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.document_api.execution_arn}/*/*"
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.document_api.api_endpoint
}
