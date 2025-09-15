variable "region" { type = string }
variable "env" { type = string }
variable "alert_emails" { type = list(string) }

variable "tenants" {
  description = "Map of tenants: { t001 = { name = \"acme\" }, ... }"
  type        = map(object({ name = string }))
}

variable "aurora_engine_version" {
  type    = string
  default = "15.10" # match current deployed engine to avoid downgrade
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

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "enable_bedrock_agents" {
  description = "Toggle Bedrock guardrails, knowledge bases, agents, associations, and action groups"
  type        = bool
  default     = false
}