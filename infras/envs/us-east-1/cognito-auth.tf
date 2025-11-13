# Cognito User Pool and Authentication Resources

# Amazon Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "cloudable-users-${var.env}"
  
  # Username and sign-in configuration
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  
  # Password policy
  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
    temporary_password_validity_days = 7
  }
  
  # MFA configuration
  mfa_configuration = "OPTIONAL"
  software_token_mfa_configuration {
    enabled = true
  }
  
  # Admin account recovery settings
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
  
  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  
  # Schema attributes
  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = true
    required            = true
  }
  
  schema {
    name                = "tenant_id"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 1
      max_length = 20
    }
  }
  
  # Lambda triggers (can be added later)
  # lambda_config {
  #   pre_sign_up = aws_lambda_function.pre_sign_up.arn
  # }
  
  tags = local.tags
}

# App client for API access
resource "aws_cognito_user_pool_client" "api_client" {
  name                = "cloudable-api-client-${var.env}"
  user_pool_id        = aws_cognito_user_pool.main.id
  
  # No client secret for public client
  generate_secret     = true
  
  # Authentication flows
  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]
  
  # Token validity
  refresh_token_validity = 30
  access_token_validity  = 1
  id_token_validity      = 1
  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
  
  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"
  
  # OAuth settings
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "openid", "profile"]
  allowed_oauth_flows_user_pool_client = true
  
  # Callback URLs
  callback_urls = ["https://${var.domain_name}/callback", "http://localhost:3000/callback"]
  logout_urls   = ["https://${var.domain_name}/logout", "http://localhost:3000/logout"]
}

# Create user group for each tenant
resource "aws_cognito_user_group" "tenant_groups" {
  for_each     = var.tenants
  name         = each.value.name
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "User group for tenant ${each.value.name}"
  precedence   = 10
}

# Create admin user group
resource "aws_cognito_user_group" "admin_group" {
  name         = "admins"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Administrators group"
  precedence   = 0  # Higher precedence than tenant groups
}

# DynamoDB Table for fine-grained tenant access control
resource "aws_dynamodb_table" "tenant_users" {
  name         = "tenant-users-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserId"
  range_key    = "TenantId"
  
  attribute {
    name = "UserId"
    type = "S"
  }
  
  attribute {
    name = "TenantId"
    type = "S"
  }
  
  attribute {
    name = "UserEmail"
    type = "S"
  }
  
  global_secondary_index {
    name               = "UserEmailIndex"
    hash_key           = "UserEmail"
    range_key          = "TenantId"
    projection_type    = "ALL"
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  # Using AWS managed key for encryption
  server_side_encryption {
    enabled = true
  }
  
  tags = local.tags
}

# Outputs
output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  description = "The client ID for the API client"
  value       = aws_cognito_user_pool_client.api_client.id
}
