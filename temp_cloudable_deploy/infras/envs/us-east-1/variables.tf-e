# Core variables
variable "region" {
  description = "AWS region for infrastructure deployment"
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "dev"
}

variable "domain_name" {
  description = "Domain name for CORS configuration"
  type        = string
  default     = "cloudable.ai"
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.12" # Keeping current version to avoid downgrade
}

variable "tenants" {
  description = "Map of tenant configurations"
  type = map(object({
    name = string
  }))
  default = {
    t001 = { name = "acme" }
    t002 = { name = "globex" }
  }
}

# API security and networking
variable "api_throttling_rate_limit" {
  description = "API Gateway throttling rate limit (requests per second)"
  type        = number
  default     = 10
}

variable "api_throttling_burst_limit" {
  description = "API Gateway throttling burst limit"
  type        = number
  default     = 20
}

variable "lambda_subnet_ids" {
  description = "List of subnet IDs for Lambda VPC configuration"
  type        = list(string)
  default     = []
}

# Security variables
variable "permission_boundary_arn" {
  description = "ARN of IAM permission boundary to apply to all roles"
  type        = string
  default     = ""
}

# Monitoring variables
variable "enable_xray" {
  description = "Enable AWS X-Ray tracing"
  type        = bool
  default     = true
}

variable "alert_emails" {
  description = "Email addresses for CloudWatch alarms"
  type        = list(string)
  default     = []
}

# Bedrock variables
# embedding_model_arn is now defined in bedrock-knowledge-base.tf

variable "agent_model_arn" {
  description = "ARN for the Bedrock agent model"
  type        = string
  default     = "arn:aws:bedrock:us-east-1:975049969923:inference-profile/us.anthropic.claude-sonnet-4-20250514-v1:0"
}

# Document processing variables
variable "enable_document_summarization" {
  description = "Enable document summarization functionality"
  type        = bool
  default     = true
}

variable "max_document_size_mb" {
  description = "Maximum allowed document size in MB"
  type        = number
  default     = 50
}

# Feature flags
variable "enable_bedrock_agents" {
  description = "Enable Bedrock agents functionality"
  type        = bool
  default     = true
}

variable "enable_advanced_security" {
  description = "Enable advanced security features"
  type        = bool
  default     = true
}

# S3 feature toggles
variable "enable_bucket_logging" {
  description = "Enable detailed S3 access logging"
  type        = bool
  default     = false
}

variable "enable_intelligent_tiering" {
  description = "Enable S3 intelligent tiering rules"
  type        = bool
  default     = false
}

# Remote state variables
variable "remote_state_bucket" {
  description = "S3 bucket for Terraform remote state"
  type        = string
  default     = "cloudable-tfstate"
}

variable "remote_state_key" {
  description = "S3 key for Terraform remote state"
  type        = string
  default     = "terraform.tfstate"
}
