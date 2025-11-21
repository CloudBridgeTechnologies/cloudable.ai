# HTTP API (API Gateway v2) definition
resource "aws_apigatewayv2_api" "http" {
  name          = "chat-api-${var.env}"
  protocol_type = "HTTP"
  description   = "HTTP API for direct agent interactions"
  
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization", "X-Api-Key", "X-Amz-Date", "X-Amz-Security-Token"]
    max_age       = 300
  }
  
  tags = merge(local.tags, {
    Service = "ChatAPI"
  })
}

# Default stage for HTTP API
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = var.env
  auto_deploy = true
  
  default_route_settings {
    throttling_burst_limit = var.api_throttling_burst_limit
    throttling_rate_limit  = var.api_throttling_rate_limit
    detailed_metrics_enabled = true
  }
  
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.http_api_logs.arn
    format          = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      integrationLatency = "$context.integrationLatency"
      integrationStatus = "$context.integrationStatus"
      errorMessage   = "$context.error.message"
    })
  }
  
  stage_variables = {
    throttling    = "enabled"
    logging_level = "INFO"
    env           = var.env
    region        = var.region
  }
  
  tags = local.tags
}

# Domain mapping for HTTP API (optional - commented out until domain is set up)
# resource "aws_apigatewayv2_domain_name" "http_api" {
#   domain_name = "api.${var.dns_domain}"
#   
#   domain_name_configuration {
#     certificate_arn = aws_acm_certificate.api_cert.arn
#     endpoint_type   = "REGIONAL"
#     security_policy = "TLS_1_2"
#   }
#   
#   tags = local.tags
# }
# 
# resource "aws_apigatewayv2_api_mapping" "http_api" {
#   api_id      = aws_apigatewayv2_api.http.id
#   domain_name = aws_apigatewayv2_domain_name.http_api.id
#   stage       = aws_apigatewayv2_stage.default.id
# }