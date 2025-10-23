# Data Source for processed S3 documents
# Temporarily disabled due to quota limit of 5 data sources per KB
# Uncomment and fix after cleaning up existing data sources
/*
resource "aws_bedrockagent_data_source" "tenant_processed_s3" {
  for_each         = var.tenants
  knowledge_base_id = aws_bedrockagent_knowledge_base.tenant[each.key].id
  name             = "s3-processed-docs-${each.value.name}"
  description      = "S3 processed document source for ${each.value.name}"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.tenant[each.key].arn
      inclusion_prefixes = ["documents/*_processed"]
    }
  }

  # Chunking strategy
  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 300
        overlap_percentage = 20
      }
    }
    # Note: In the AWS Console, we'd set:
    # document_enrichment_configuration {
    #   metadata_field_updates {
    #     s3_metadata_field = "kb_metadata"
    #     target_metadata_field = "metadata"
    #   }
    # }
    # But Terraform provider doesn't yet support this
  }
}
*/
