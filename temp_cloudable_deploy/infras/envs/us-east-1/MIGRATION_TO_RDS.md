# Migration from OpenSearch Serverless to RDS pgvector

## Cost Efficiency Decision
We've migrated from OpenSearch Serverless to RDS PostgreSQL with pgvector extension for cost efficiency:
- **OpenSearch Serverless**: ~$0.24/hour per OCU (OpenSearch Compute Unit) + storage costs
- **RDS pgvector**: Uses existing Aurora PostgreSQL infrastructure - **NO additional cost** for vector storage

## Changes Made

### 1. Updated Knowledge Base Configuration
- **File**: `opensearch-indexes.tf`
- Changed from `OPENSEARCH_SERVERLESS` to `RDS` storage type
- Uses existing Aurora PostgreSQL cluster

### 2. Updated IAM Permissions
- **File**: `iam-bedrock.tf`
- Replaced OpenSearch permissions with RDS Data API permissions
- Added Secrets Manager access for RDS credentials

### 3. Disabled OpenSearch Resources
- **Files**: 
  - `opensearch-serverless.tf` - Collections, security, and access policies commented out
  - `iam-bedrock.tf` - OpenSearch IAM policy commented out
  - `cloudwatch-logging.tf` - OpenSearch log groups (to be commented out)
  - `kb-opensearch-*.tf` - All OpenSearch-specific policies (to be commented out)

### 4. Created Setup Scripts
- **File**: `setup_pgvector.py` - Python script to enable pgvector and create tables
- **File**: `setup_pgvector.sql` - SQL script for manual setup

## Next Steps

1. **Deploy Infrastructure**:
   ```bash
   cd infras/envs/us-east-1
   terraform apply
   ```

2. **Setup pgvector Extension**:
   ```bash
   # Get RDS cluster ARN and secret ARN from Terraform outputs
   python3 setup_pgvector.py \
     --cluster-arn <cluster-arn> \
     --secret-arn <secret-arn> \
     --database cloudable \
     --tenants acme globex
   ```

3. **Verify Setup**:
   - Check Bedrock Knowledge Bases are created
   - Test document ingestion
   - Test knowledge base queries

## Cost Savings
- **Before**: OpenSearch Serverless costs (~$175/month minimum for 1 OCU)
- **After**: $0 additional cost (uses existing Aurora infrastructure)
- **Savings**: ~$175/month + storage costs

