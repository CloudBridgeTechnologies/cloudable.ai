# Bedrock Knowledge Base Resources

variable "embedding_model_arn" {
  description = "ARN of the embedding model to use"
  type        = string
  default     = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v1"
}

# Note: Knowledge Base resource moved to opensearch-indexes.tf
# Knowledge Base Data Source will be created via API
# The AWS provider doesn't yet support aws_bedrockagent_knowledge_base_data_source

