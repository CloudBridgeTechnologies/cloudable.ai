# Approach: Use RDS PostgreSQL with pgvector as the vector store
# This is the most cost-efficient option since we're using existing Aurora infrastructure

resource "aws_bedrockagent_knowledge_base" "tenant" {
  for_each    = var.enable_bedrock_agents ? var.tenants : {}
  name        = "kb-${var.env}-${each.value.name}"
  description = "Knowledge base for ${each.value.name} tenant using RDS pgvector"
  role_arn    = aws_iam_role.kb[each.key].arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = var.embedding_model_arn
    }
  }

  # Use RDS PostgreSQL with pgvector (cost-efficient - uses existing Aurora)
  storage_configuration {
    type = "RDS"
    rds_configuration {
      resource_arn          = aws_rds_cluster.this.arn
      credentials_secret_arn = aws_secretsmanager_secret.db.arn
      database_name         = aws_rds_cluster.this.database_name
      table_name            = "kb_vectors_${each.value.name}"
      field_mapping {
        vector_field     = "embedding"
        text_field       = "chunk_text"
        metadata_field   = "metadata"
        primary_key_field = "id"
      }
    }
  }

  tags = merge(local.tags, {
    tenant_id = each.key
  })
  
  depends_on = [
    aws_rds_cluster.this,
    aws_secretsmanager_secret.db,
    aws_iam_role_policy.kb
  ]
}