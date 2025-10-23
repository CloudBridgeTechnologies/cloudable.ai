# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Main API Gateway REST API with security enhancements
resource "aws_api_gateway_rest_api" "secure_api" {
  name        = "secure-api-${var.env}"
  description = "Secure API Gateway with API Key Authentication"
  
  # Enable API Gateway metrics for CloudWatch
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  # Enable compression to reduce bandwidth and costs
  minimum_compression_size = 1024
  
  # Enable binary support for handling files
  binary_media_types = [
    "application/pdf",
    "application/octet-stream",
    "image/*"
  ]
  
  tags = merge(local.tags, {
    Name        = "secure-api-${var.env}",
    Service     = "API",
    Description = "Main secure API gateway for Cloudable.AI"
  })
}

# API Gateway Stage with optimal configuration
resource "aws_api_gateway_stage" "secure_api" {
  deployment_id = aws_api_gateway_deployment.secure_api.id
  rest_api_id   = aws_api_gateway_rest_api.secure_api.id
  stage_name    = var.env
  
  # Enable detailed CloudWatch metrics
  xray_tracing_enabled = true
  
  # Apply cache settings for better performance
  cache_cluster_enabled = var.env == "prod" ? true : false
  cache_cluster_size    = var.env == "prod" ? "0.5" : null
  
  # Access logs disabled - requires CloudWatch Logs role ARN to be set in account settings
  # To enable logs, set up the role in the AWS Console first
  # access_log_settings {
  #   destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
  #   format = jsonencode({
  #     requestId      = "$context.requestId"
  #     ip             = "$context.identity.sourceIp"
  #     requestTime    = "$context.requestTime"
  #     httpMethod     = "$context.httpMethod"
  #     routeKey       = "$context.routeKey"
  #     status         = "$context.status"
  #     protocol       = "$context.protocol"
  #     responseLength = "$context.responseLength"
  #     userAgent      = "$context.identity.userAgent"
  #     apiKey         = "$context.identity.apiKey"
  #     path           = "$context.path"
  #     latency        = "$context.responseLatency"
  #   })
  # }
  
  # Add variables for environment-specific configurations
  variables = {
    "env"             = var.env
    "region"          = var.region
    "logging_level"   = var.env == "prod" ? "INFO" : "DEBUG"
    "throttling"      = "enabled"
  }
  
  tags = local.tags
}

# API Gateway CloudWatch Log Group
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${aws_api_gateway_rest_api.secure_api.name}"
  retention_in_days = 30
  
  tags = merge(local.tags, {
    Service = "APIGateway"
  })
}

# Chat API Resource
resource "aws_api_gateway_resource" "root" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  parent_id   = aws_api_gateway_rest_api.secure_api.root_resource_id
  path_part   = "chat"
}

# Chat API Method
resource "aws_api_gateway_method" "post_chat" {
  rest_api_id      = aws_api_gateway_rest_api.secure_api.id
  resource_id      = aws_api_gateway_resource.root.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

# Chat API Integration
resource "aws_api_gateway_integration" "chat_integration" {
  rest_api_id             = aws_api_gateway_rest_api.secure_api.id
  resource_id             = aws_api_gateway_resource.root.id
  http_method             = aws_api_gateway_method.post_chat.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:orchestrator-${var.env}/invocations"
}

# API Key for authentication
resource "aws_api_gateway_api_key" "client_key" {
  name        = "cloudable-api-key-${var.env}"
  description = "API Key for Cloudable.AI secure API access"
  
  tags = merge(local.tags, {
    Name        = "cloudable-api-key-${var.env}"
    Service     = "API"
    Description = "Main API key for secure access"
  })
}

# Usage Plan for API throttling and quotas
resource "aws_api_gateway_usage_plan" "standard" {
  name        = "cloudable-usage-plan-${var.env}"
  description = "Standard usage plan for Cloudable.AI API"
  
  # Throttling settings
  throttle_settings {
    rate_limit  = var.api_throttling_rate_limit
    burst_limit = var.api_throttling_burst_limit
  }
  
  # Quota settings
  quota_settings {
    limit  = 10000  # 10,000 requests per day
    period = "DAY"
  }
  
  # Associate with API stages
  api_stages {
    api_id = aws_api_gateway_rest_api.secure_api.id
    stage  = aws_api_gateway_stage.secure_api.stage_name
  }
  
  tags = merge(local.tags, {
    Name        = "cloudable-usage-plan-${var.env}"
    Service     = "API"
    Description = "Standard usage plan with throttling"
  })
}

# Link API key to usage plan
resource "aws_api_gateway_usage_plan_key" "main" {
  key_id        = aws_api_gateway_api_key.client_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.standard.id
}

# API Gateway Deployment with proper dependency management
resource "aws_api_gateway_deployment" "secure_api" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  
  # Ensure deployment happens after all resources are created
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.root.id,
      aws_api_gateway_method.post_chat.id,
      aws_api_gateway_integration.chat_integration.id,
      # Include KB API dependencies via the null_resource
      null_resource.kb_api_deployment_dependencies.id
    ]))
  }
  
  depends_on = [
    aws_api_gateway_method.post_chat,
    aws_api_gateway_integration.chat_integration,
    null_resource.kb_api_deployment_dependencies
  ]
  
  lifecycle {
    create_before_destroy = true
  }
}


# WAF Web ACL for API Gateway protection
resource "aws_wafv2_web_acl" "api_protection" {
  name        = "api-protection-${var.env}"
  description = "Web ACL for API Gateway protection"
  scope       = "REGIONAL"
  
  default_action {
    allow {}
  }
  
  # Rule to block SQL injection attacks
  rule {
    name     = "SQLInjectionProtection"
    priority = 1
    
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLInjectionProtection"
      sampled_requests_enabled   = true
    }
    
    override_action {
      none {}
    }
  }
  
  # Rule to block common vulnerabilities
  rule {
    name     = "CoreRuleSet"
    priority = 2
    
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CoreRuleSet"
      sampled_requests_enabled   = true
    }
    
    override_action {
      none {}
    }
  }
  
  # Rule to limit request rate
  rule {
    name     = "RateLimitRule"
    priority = 3
    
    action {
      block {}
    }
    
    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }
  
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "ApiProtection"
    sampled_requests_enabled   = true
  }
  
  tags = merge(local.tags, {
    Service = "Security"
  })
}

# WAF Web ACL Association with API Gateway
resource "aws_wafv2_web_acl_association" "api_waf_association" {
  resource_arn = aws_api_gateway_stage.secure_api.arn
  web_acl_arn  = aws_wafv2_web_acl.api_protection.arn
}

# API Gateway Request Validator to ensure proper request format
resource "aws_api_gateway_request_validator" "full_validator" {
  name                        = "full-validator"
  rest_api_id                 = aws_api_gateway_rest_api.secure_api.id
  validate_request_body       = true
  validate_request_parameters = true
}

# API Gateway Response for CORS
resource "aws_api_gateway_gateway_response" "cors" {
  rest_api_id   = aws_api_gateway_rest_api.secure_api.id
  response_type = "DEFAULT_4XX"
  
  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
  }
  
  response_templates = {
    "application/json" = "{\"message\":$context.error.messageString}"
  }
}

# Output API Gateway endpoints and details
output "secure_api_endpoint" {
  description = "The invoke URL for the secure API Gateway"
  value       = aws_api_gateway_stage.secure_api.invoke_url
}

output "secure_api_key" {
  description = "The API key for secure API access"
  value       = aws_api_gateway_api_key.client_key.value
  sensitive   = true
}

# API Gateway Method Settings for optimized performance
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  stage_name  = aws_api_gateway_stage.secure_api.stage_name
  method_path = "*/*"
  
  settings {
    metrics_enabled        = true
    # Logging is disabled - requires CloudWatch Logs role ARN to be set in account settings
    # logging_level        = "INFO"
    caching_enabled        = var.env == "prod" ? true : false
    cache_ttl_in_seconds   = 300
    throttling_rate_limit  = var.api_throttling_rate_limit
    throttling_burst_limit = var.api_throttling_burst_limit
  }
}
