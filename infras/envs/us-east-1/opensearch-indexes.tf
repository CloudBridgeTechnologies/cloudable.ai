# Approach: Use OpenSearch Serverless as the vector store

resource "aws_bedrockagent_knowledge_base" "tenant" {
  for_each    = var.enable_bedrock_agents ? var.tenants : {}
  name        = "kb-${var.env}-${each.value.name}"
  description = "Knowledge base for ${each.value.name} tenant"
  role_arn    = aws_iam_role.kb[each.key].arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = var.embedding_model_arn
    }
  }

  # Use OpenSearch Serverless
  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb[each.key].arn
      vector_index_name = "default-index"
      field_mapping {
        vector_field   = "vector"
        text_field     = "text"
        metadata_field = "metadata"
      }
    }
  }

  tags = merge(local.tags, {
    tenant_id = each.key
  })
  
  depends_on = [
    aws_opensearchserverless_access_policy.bedrock_kb_access,
    aws_opensearchserverless_collection.kb,
    aws_iam_role_policy.kb,
    aws_opensearchserverless_security_policy.bedrock_network
  ]
}