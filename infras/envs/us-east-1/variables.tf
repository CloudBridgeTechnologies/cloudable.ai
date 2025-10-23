variable "region" { type = string }
variable "env" { type = string }
variable "alert_emails" {
  description = "Email addresses for CloudWatch alarms"
  type        = list(string)
  default     = ["admin@cloudable.ai"]
}

variable "tenants" {
  description = "Map of tenants: { t001 = { name = \"acme\" }, ... }"
  type        = map(object({ name = string }))
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.12" # match current deployed engine to avoid downgrade
}

# Bedrock models (allow override)
variable "embedding_model_arn" {
  type    = string
  default = "arn:aws:bedrock:eu-west-2::foundation-model/amazon.titan-embed-text-v2:0"
}

variable "agent_model_arn" {
  type    = string
  default = "arn:aws:bedrock:us-east-1:951296734820:inference-profile/us.anthropic.claude-sonnet-4-20250514-v1:0"
}

variable "api_throttling_burst_limit" {
  description = "API Gateway throttling burst limit"
  type        = number
  default     = 20
}

variable "api_throttling_rate_limit" {
  description = "API Gateway throttling rate limit"
  type        = number
  default     = 100
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

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "enable_bedrock_agents" {
  description = "Toggle Bedrock guardrails, knowledge bases, agents, associations, and action groups"
  type        = bool
  default     = true
}

variable "enable_advanced_security" {
  description = "Enable advanced security features"
  type        = bool
  default     = true
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

variable "domain_name" {
  description = "Domain name for CORS configuration"
  type        = string
  default     = "cloudable.ai"
}