# Cloudable.AI

Cloudable.AI is a multi-tenant, vector search platform that integrates with AWS Bedrock for embeddings and LLM capabilities, using PostgreSQL with pgvector for similarity search.

## Architecture

The system consists of:
- **API Gateway**: Handles API requests for document uploads, KB sync, KB queries, chat, and customer status
- **Lambda Functions**: Process API requests and interact with AWS services
- **PostgreSQL RDS**: Stores vector embeddings and customer data using pgvector extension
- **S3**: Stores uploaded documents
- **AWS Bedrock**: Generates embeddings and powers LLM responses
- **Terraform**: IaC for deploying all resources

## Features

- **Document Management**: Upload documents and generate vector embeddings
- **Knowledge Base**: Query a vector database with natural language
- **Chat Interface**: Interact with LLM with knowledge base augmentation
- **Customer Status**: Track customer progress through implementation stages
- **Multi-tenancy**: Complete isolation between tenants
- **RBAC**: Role-based access control for different user types

## Directory Structure

```
.
├── infras/
│   ├── core/              # Core infrastructure Terraform and setup scripts
│   ├── lambdas/           # Lambda function code
│   │   ├── kb_manager/    # Main Lambda for KB operations
│   │   └── ...
│   ├── sql/               # SQL scripts for database setup
│   └── terraform/         # Additional Terraform configurations
├── test_files/            # Files used for testing
└── *.sh                   # Various utility and test scripts
```

## Deployment

1. Configure AWS credentials
2. Run the deployment script:
   ```bash
   ./deploy_terraform.sh
   ```
3. Set up the database with pgvector:
   ```bash
   ./setup_pgvector.sh
   ```

## Testing

Run the end-to-end test to verify functionality:

```bash
./test_e2e_pipeline.sh
```

This tests:
- Health check
- Document upload
- KB synchronization
- KB querying
- Chat functionality
- Customer status retrieval
- Error handling
- Multi-tenant isolation

## API Endpoints

- `/api/health` - Health check
- `/api/upload-url` - Get presigned URL for S3 upload
- `/api/kb/sync` - Trigger knowledge base sync for a document
- `/api/kb/query` - Query the knowledge base
- `/api/chat` - Chat with or without knowledge base context
- `/api/customer-status` - Get customer implementation status

All endpoints require authentication via the `X-User-ID` header.

## Configuration

The application is configured via environment variables in the Lambda function:
- `BUCKET_[TENANT]` - S3 bucket for each tenant
- `RDS_CLUSTER_ARN` - ARN of the RDS cluster
- `RDS_SECRET_ARN` - ARN of the RDS credentials in Secrets Manager
- `CLAUDE_MODEL_ARN` - ARN of the Claude model in Bedrock
- `REGION` - AWS region (eu-west-1)

## License

Proprietary software. All rights reserved.