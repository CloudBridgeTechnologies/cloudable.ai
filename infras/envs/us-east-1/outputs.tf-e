output "api_endpoint" { value = aws_apigatewayv2_api.http.api_endpoint }
output "rds_cluster_arn" { value = aws_rds_cluster.this.arn }
output "db_secret_arn" { value = aws_secretsmanager_secret.db.arn }

# Outputs for REST API Gateway
output "secure_api_id" {
  value = aws_api_gateway_rest_api.secure_api.id
  description = "The ID of the secure API Gateway"
}

output "secure_api_stage" {
  value = aws_api_gateway_stage.secure_api.stage_name
  description = "The stage name of the secure API Gateway"
}

# Outputs for Bedrock agents
output "agent_ids" {
  value = {
    for k, agent in aws_bedrockagent_agent.tenant : k => agent.id
  }
  description = "Map of tenant IDs to their agent IDs"
}

output "agent_aliases" {
  value = {
    for k, alias in aws_bedrockagent_agent_alias.tenant : k => alias.id
  }
  description = "Map of tenant IDs to their agent alias IDs"
}

# Outputs for knowledge bases
output "kb_ids" {
  value = {
    for k, kb in aws_bedrockagent_knowledge_base.tenant : k => kb.id
  }
  description = "Map of tenant IDs to their knowledge base IDs"
}

# Outputs for S3 buckets
output "tenant_bucket_names" {
  value = {
    for k, bucket in aws_s3_bucket.tenant : k => bucket.bucket
  }
  description = "Map of tenant IDs to their S3 bucket names"
}

output "summary_bucket_names" {
  value = {
    for k, bucket in aws_s3_bucket.summary : k => bucket.bucket
  }
  description = "Map of tenant IDs to their summary bucket names"
}

# Outputs for monitoring are defined in monitoring-ai-safety.tf

