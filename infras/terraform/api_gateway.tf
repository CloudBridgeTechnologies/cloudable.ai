###############################################
# API Gateway for Cloudable.AI API
###############################################

resource "aws_apigatewayv2_api" "cloudable_api" {
  name          = "cloudable-kb-api-core"
  protocol_type = "HTTP"
  
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
    allow_headers = ["*"]
  }
  
  tags = {
    Name        = "cloudable-api"
    Environment = "dev"
    Project     = "Cloudable.AI"
  }
}

resource "aws_apigatewayv2_stage" "dev" {
  api_id      = aws_apigatewayv2_api.cloudable_api.id
  name        = "dev"
  auto_deploy = true
  
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      path           = "$context.path"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      integrationStatus = "$context.integrationStatus"
      integrationLatency = "$context.integrationLatency"
      responseLatency = "$context.responseLatency"
    })
  }
  
  tags = {
    Name        = "dev-stage"
    Environment = "dev"
    Project     = "Cloudable.AI"
  }
}

resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/cloudable-api-logs"
  retention_in_days = 14
}

# Lambda integration for API Gateway
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.cloudable_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.kb_manager.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Health check route
resource "aws_apigatewayv2_route" "health_route" {
  api_id    = aws_apigatewayv2_api.cloudable_api.id
  route_key = "GET /api/health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# KB query route
resource "aws_apigatewayv2_route" "kb_query_route" {
  api_id    = aws_apigatewayv2_api.cloudable_api.id
  route_key = "POST /api/kb/query"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# KB sync route
resource "aws_apigatewayv2_route" "kb_sync_route" {
  api_id    = aws_apigatewayv2_api.cloudable_api.id
  route_key = "POST /api/kb/sync"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Chat route
resource "aws_apigatewayv2_route" "chat_route" {
  api_id    = aws_apigatewayv2_api.cloudable_api.id
  route_key = "POST /api/chat"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Upload URL route
resource "aws_apigatewayv2_route" "upload_url_route" {
  api_id    = aws_apigatewayv2_api.cloudable_api.id
  route_key = "POST /api/upload-url"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Customer status route
resource "aws_apigatewayv2_route" "customer_status_route" {
  api_id    = aws_apigatewayv2_api.cloudable_api.id
  route_key = "POST /api/customer-status"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "api_gateway_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kb_manager.function_name
  principal     = "apigateway.amazonaws.com"
  
  # Allow invocation from any stage of the API
  source_arn = "${aws_apigatewayv2_api.cloudable_api.execution_arn}/*/*"
}
