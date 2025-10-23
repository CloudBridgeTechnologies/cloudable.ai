# KB API Resources
resource "aws_api_gateway_resource" "kb" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  parent_id   = aws_api_gateway_rest_api.secure_api.root_resource_id
  path_part   = "kb"
}

# KB Query Endpoint
resource "aws_api_gateway_resource" "kb_query" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  parent_id   = aws_api_gateway_resource.kb.id
  path_part   = "query"
}

resource "aws_api_gateway_method" "post_kb_query" {
  rest_api_id      = aws_api_gateway_rest_api.secure_api.id
  resource_id      = aws_api_gateway_resource.kb_query.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
  request_validator_id = aws_api_gateway_request_validator.full_validator.id
  
  request_models = {
    "application/json" = aws_api_gateway_model.kb_query_request.name
  }
}

resource "aws_api_gateway_integration" "kb_query_integration" {
  rest_api_id             = aws_api_gateway_rest_api.secure_api.id
  resource_id             = aws_api_gateway_resource.kb_query.id
  http_method             = aws_api_gateway_method.post_kb_query.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:orchestrator-${var.env}/invocations"
}

# KB Upload URL Endpoint
resource "aws_api_gateway_resource" "kb_upload_url" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  parent_id   = aws_api_gateway_resource.kb.id
  path_part   = "upload-url"
}

resource "aws_api_gateway_method" "post_kb_upload_url" {
  rest_api_id      = aws_api_gateway_rest_api.secure_api.id
  resource_id      = aws_api_gateway_resource.kb_upload_url.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
  request_validator_id = aws_api_gateway_request_validator.full_validator.id
  
  request_models = {
    "application/json" = aws_api_gateway_model.kb_upload_url_request.name
  }
}

resource "aws_api_gateway_integration" "kb_upload_url_integration" {
  rest_api_id             = aws_api_gateway_rest_api.secure_api.id
  resource_id             = aws_api_gateway_resource.kb_upload_url.id
  http_method             = aws_api_gateway_method.post_kb_upload_url.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:s3-helper-${var.env}/invocations"
}

# KB Sync Endpoint
resource "aws_api_gateway_resource" "kb_sync" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  parent_id   = aws_api_gateway_resource.kb.id
  path_part   = "sync"
}

resource "aws_api_gateway_method" "post_kb_sync" {
  rest_api_id      = aws_api_gateway_rest_api.secure_api.id
  resource_id      = aws_api_gateway_resource.kb_sync.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
  request_validator_id = aws_api_gateway_request_validator.full_validator.id
  
  request_models = {
    "application/json" = aws_api_gateway_model.kb_sync_request.name
  }
}

resource "aws_api_gateway_integration" "kb_sync_integration" {
  rest_api_id             = aws_api_gateway_rest_api.secure_api.id
  resource_id             = aws_api_gateway_resource.kb_sync.id
  http_method             = aws_api_gateway_method.post_kb_sync.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:kb-manager-${var.env}/invocations"
}

# Summary endpoints
resource "aws_api_gateway_resource" "summary" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  parent_id   = aws_api_gateway_rest_api.secure_api.root_resource_id
  path_part   = "summary"
}

resource "aws_api_gateway_resource" "summary_tenant" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  parent_id   = aws_api_gateway_resource.summary.id
  path_part   = "{tenant}"
}

resource "aws_api_gateway_resource" "summary_document" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  parent_id   = aws_api_gateway_resource.summary_tenant.id
  path_part   = "{document_id}"
}

resource "aws_api_gateway_method" "get_summary" {
  rest_api_id      = aws_api_gateway_rest_api.secure_api.id
  resource_id      = aws_api_gateway_resource.summary_document.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
  
  request_parameters = {
    "method.request.path.tenant"      = true,
    "method.request.path.document_id" = true
  }
}

resource "aws_api_gateway_integration" "get_summary_integration" {
  rest_api_id             = aws_api_gateway_rest_api.secure_api.id
  resource_id             = aws_api_gateway_resource.summary_document.id
  http_method             = aws_api_gateway_method.get_summary.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:summary-retriever-${var.env}/invocations"
}

resource "aws_api_gateway_method" "post_summary" {
  rest_api_id      = aws_api_gateway_rest_api.secure_api.id
  resource_id      = aws_api_gateway_resource.summary_document.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
  
  request_parameters = {
    "method.request.path.tenant"      = true,
    "method.request.path.document_id" = true
  }
}

resource "aws_api_gateway_integration" "post_summary_integration" {
  rest_api_id             = aws_api_gateway_rest_api.secure_api.id
  resource_id             = aws_api_gateway_resource.summary_document.id
  http_method             = aws_api_gateway_method.post_summary.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:document-summarizer-${var.env}/invocations"
}

# CORS support for summary endpoint
resource "aws_api_gateway_method" "options_summary" {
  rest_api_id      = aws_api_gateway_rest_api.secure_api.id
  resource_id      = aws_api_gateway_resource.summary_document.id
  http_method      = "OPTIONS"
  authorization    = "NONE"
  api_key_required = false
}

resource "aws_api_gateway_integration" "options_summary_integration" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  resource_id = aws_api_gateway_resource.summary_document.id
  http_method = aws_api_gateway_method.options_summary.http_method
  type        = "MOCK"
  
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_summary_200" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  resource_id = aws_api_gateway_resource.summary_document.id
  http_method = aws_api_gateway_method.options_summary.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_summary_response" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  resource_id = aws_api_gateway_resource.summary_document.id
  http_method = aws_api_gateway_method.options_summary.http_method
  status_code = aws_api_gateway_method_response.options_summary_200.status_code
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Models for request validation
resource "aws_api_gateway_model" "kb_query_request" {
  rest_api_id  = aws_api_gateway_rest_api.secure_api.id
  name         = "KBQueryRequest"
  description  = "JSON schema for KB query request validation"
  content_type = "application/json"
  
  schema = jsonencode({
    "$schema"    = "http://json-schema.org/draft-04/schema#",
    "title"      = "KBQueryRequest",
    "type"       = "object",
    "required"   = ["tenant_id", "query"],
    "properties" = {
      "tenant_id" = {
        "type" = "string"
      },
      "query" = {
        "type" = "string"
      },
      "max_results" = {
        "type" = "integer"
      }
    }
  })
}

resource "aws_api_gateway_model" "kb_upload_url_request" {
  rest_api_id  = aws_api_gateway_rest_api.secure_api.id
  name         = "KbUploadUrlRequest"
  description  = "Schema for KB Upload URL API requests"
  content_type = "application/json"
  schema       = jsonencode({
    type       = "object",
    properties = {
      tenant_id = { type = "string" },
      file_name = { type = "string" }
    },
    required   = ["tenant_id", "file_name"]
  })
}

resource "aws_api_gateway_model" "kb_sync_request" {
  rest_api_id  = aws_api_gateway_rest_api.secure_api.id
  name         = "KbSyncRequest"
  description  = "Schema for KB Sync API requests"
  content_type = "application/json"
  schema       = jsonencode({
    type       = "object",
    properties = {
      tenant_id   = { type = "string" },
      document_id = { type = "string" }
    },
    required   = ["tenant_id", "document_id"]
  })
}

# Add dependency to the API Gateway Deployment
resource "aws_cloudwatch_log_group" "kb_api_logs" {
  name              = "/aws/apigateway/kb-api-${var.env}"
  retention_in_days = 30
  tags = merge(local.tags, {
    Service = "APIGateway"
  })
}

# Update the deployment trigger in aws_api_gateway_deployment.secure_api
locals {
  kb_api_dependencies = [
    aws_api_gateway_resource.kb.id,
    aws_api_gateway_resource.kb_query.id,
    aws_api_gateway_method.post_kb_query.id,
    aws_api_gateway_integration.kb_query_integration.id,
    aws_api_gateway_resource.kb_upload_url.id,
    aws_api_gateway_method.post_kb_upload_url.id,
    aws_api_gateway_integration.kb_upload_url_integration.id,
    aws_api_gateway_resource.kb_sync.id,
    aws_api_gateway_method.post_kb_sync.id,
    aws_api_gateway_integration.kb_sync_integration.id,
    aws_api_gateway_resource.summary.id,
    aws_api_gateway_resource.summary_tenant.id,
    aws_api_gateway_resource.summary_document.id,
    aws_api_gateway_method.get_summary.id,
    aws_api_gateway_integration.get_summary_integration.id,
    aws_api_gateway_method.post_summary.id,
    aws_api_gateway_integration.post_summary_integration.id,
    aws_api_gateway_method.options_summary.id,
    aws_api_gateway_integration.options_summary_integration.id
  ]
}

# This empty resource ensures the deployment depends on all KB API resources
resource "null_resource" "kb_api_deployment_dependencies" {
  triggers = {
    dependencies = sha1(jsonencode(local.kb_api_dependencies))
  }
}
