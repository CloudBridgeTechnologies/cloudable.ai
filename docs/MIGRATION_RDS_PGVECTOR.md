# Migration from OpenSearch to RDS pgvector

## Overview

This document outlines the migration from OpenSearch Serverless to RDS PostgreSQL with pgvector for the Cloudable.AI vector search capabilities. The migration was completed to reduce costs while maintaining full functionality.

## Motivation

- **Cost Efficiency**: OpenSearch Serverless was costing approximately $175/month, while using our existing RDS infrastructure with pgvector has negligible additional cost.
- **Simplified Architecture**: Using RDS for both relational data and vector storage reduces the number of managed services.
- **Maintainability**: Having vector data in PostgreSQL allows for easier data management, backup, and replication.

## Changes Made

### Infrastructure Changes

1. **Disabled OpenSearch Resources**:
   - All OpenSearch Serverless collections, security policies, access policies were commented out in Terraform.
   - IAM policies for OpenSearch were removed or updated to focus on RDS access.

2. **RDS Updates**:
   - Added `enable_http_endpoint = true` to enable Data API v2 for Bedrock Knowledge Base.
   - Created SQL scripts to set up pgvector extension and necessary tables.

3. **Bedrock Knowledge Base Configuration**:
   - Updated to use RDS as the storage configuration type instead of OpenSearch.
   - Configured field mappings for embedding, text, metadata, and primary key fields.

4. **IAM Permissions**:
   - Added RDS Data API permissions to relevant IAM roles.
   - Added Secrets Manager permissions for RDS secret access.
   - Added KMS permissions for encrypting/decrypting RDS data.

### Lambda Function Updates

1. **KB Manager Lambda**:
   - Added RDS Data API client.
   - Implemented embedding generation using Amazon Titan embeddings.
   - Updated query_knowledge_base function to use pgvector for similarity search.
   - Added CloudWatch metrics for monitoring RDS queries.

2. **Orchestrator Lambda**:
   - Updated to call KB Manager Lambda for knowledge base operations.
   - Added environment variables for KB Manager function name.
   - Added permissions to invoke KB Manager Lambda.

3. **Monitoring**:
   - Added CloudWatch dashboard for KB metrics, RDS metrics, and Lambda metrics.
   - Added CloudWatch alarms for errors and high resource usage.

## Database Schema

The pgvector tables follow this structure:

```sql
CREATE TABLE kb_vectors_{tenant_name} (
    id UUID PRIMARY KEY,
    embedding vector(1536),
    chunk_text TEXT NOT NULL,
    metadata JSONB
);

-- HNSW index for fast vector similarity search
CREATE INDEX kb_vectors_{tenant_name}_embedding_idx
ON kb_vectors_{tenant_name}
USING hnsw (embedding vector_cosine_ops);

-- GIN index for text search
CREATE INDEX kb_vectors_{tenant_name}_chunk_text_gin_idx
ON kb_vectors_{tenant_name}
USING gin (to_tsvector('simple', chunk_text));
```

## Environment Variables

The following environment variables were added to Lambda functions:

- `RDS_CLUSTER_ARN`: ARN of the RDS cluster
- `RDS_SECRET_ARN`: ARN of the secret containing database credentials
- `RDS_DATABASE`: Database name (defaults to "cloudable")
- `KB_MANAGER_FUNCTION_NAME`: Name of the KB Manager Lambda function

## Testing

An end-to-end test script (`e2e_rds_pgvector_test.sh`) was created to validate the migration:

1. Creates a test document
2. Uploads it to S3
3. Triggers document processing
4. Queries the knowledge base
5. Tests chat with knowledge integration
6. Cleans up test files

## Performance Considerations

- **Query Speed**: pgvector with HNSW indexing provides efficient similarity search.
- **Scaling**: RDS Serverless v2 scales automatically based on load.
- **Limits**: Current implementation is optimized for medium-sized knowledge bases (up to several thousand documents).

## Future Improvements

1. **Connection Pooling**: Add connection pooling for high-volume scenarios.
2. **Partitioning**: Implement table partitioning for very large knowledge bases.
3. **Hybrid Search**: Combine vector search with keyword search for improved results.
4. **Query Caching**: Implement caching for frequently asked questions.
