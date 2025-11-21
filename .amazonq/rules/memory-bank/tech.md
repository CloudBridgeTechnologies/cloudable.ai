# Cloudable.AI Technology Stack

## Programming Languages and Versions

### Primary Languages
- **Python 3.9+** - Main development language for Lambda functions and utilities
- **HCL (HashiCorp Configuration Language)** - Terraform infrastructure as code
- **SQL** - PostgreSQL database schemas and queries
- **Shell/Bash** - Deployment and automation scripts

### Runtime Environments
- **AWS Lambda Runtime**: Python 3.9
- **PostgreSQL**: Version 15.12 (Aurora PostgreSQL)
- **Terraform**: >= 1.0.0

## Core AWS Services and Dependencies

### Compute and API
- **AWS Lambda** - Serverless compute for all business logic
- **API Gateway v2 (HTTP)** - REST API management and routing
- **AWS Bedrock** - LLM and embedding services (Claude Sonnet)

### Data Storage
- **Amazon RDS Aurora PostgreSQL** - Primary database with pgvector extension
  - Engine: aurora-postgresql 15.12
  - Serverless v2 scaling (0.5-1.0 ACU)
  - HTTP endpoint enabled for Data API
- **Amazon S3** - Document storage and static assets
- **AWS Secrets Manager** - Database credentials and API keys

### AI and ML Services
- **AWS Bedrock Knowledge Base** - Vector search and document indexing
- **pgvector Extension** - PostgreSQL vector similarity search
- **Claude Sonnet** - Text generation and document summarization

### Infrastructure and Security
- **AWS VPC** - Network isolation and security
- **AWS IAM** - Role-based access control
- **AWS WAF** - Web application firewall protection
- **AWS CloudWatch** - Logging and monitoring

## Build Systems and Package Management

### Python Dependencies
- **boto3** - AWS SDK for Python
- **psycopg2** - PostgreSQL adapter for Python
- **langfuse** - AI interaction monitoring and analytics
- **requests** - HTTP client library
- **numpy** - Numerical computing (for vector operations)
- **urllib3** - HTTP client utilities

### Infrastructure Tools
- **Terraform** - Infrastructure as Code
  - AWS Provider ~> 5.20
  - Local backend for development
  - Remote state for production
- **AWS CLI** - Command-line interface for AWS services

### Lambda Packaging
- **ZIP deployment packages** - Lambda function code and dependencies
- **Layer architecture** - Shared dependencies across functions
- **Custom build scripts** - Automated package creation

## Development Commands and Scripts

### Infrastructure Deployment
```bash
# Core infrastructure deployment
./deploy_terraform.sh

# Database setup with pgvector
./setup_pgvector.sh

# Customer status schema setup
./setup_customer_status.sh
```

### Testing and Validation
```bash
# End-to-end pipeline testing
./test_e2e_pipeline.sh

# Comprehensive test suite
./run_comprehensive_tests.sh

# Multi-tenant isolation testing
./test_tenant_isolation.sh

# API endpoint validation
./test_api_endpoints.sh
```

### Lambda Function Management
```bash
# Build Lambda packages
./create_lambda_package.sh

# Update Lambda functions only
./update_lambda_only.sh

# Deploy with Langfuse integration
./deploy_with_langfuse.sh
```

### Environment Management
```bash
# AWS environment setup
./set_aws_env.sh

# Profile configuration
./setup_aws_profile.sh

# Environment verification
./verify_environment.sh
```

## Configuration Management

### Environment Variables
- **RDS_CLUSTER_ARN** - Aurora cluster identifier
- **RDS_SECRET_ARN** - Database credentials secret
- **CLAUDE_MODEL_ARN** - Bedrock model identifier
- **BUCKET_[TENANT]** - Tenant-specific S3 buckets
- **REGION** - AWS deployment region (eu-west-1, us-east-1)

### Terraform Variables
- **aws_region** - Target AWS region
- **environment** - Deployment environment (dev, prod)
- **vpc_id** - Existing VPC identifier
- **cluster_identifier** - RDS cluster naming

### Database Configuration
- **pgvector extension** - Vector similarity search capability
- **Connection pooling** - RDS Data API for serverless connections
- **Multi-tenant schemas** - Tenant isolation at database level

## Monitoring and Observability

### Logging and Metrics
- **CloudWatch Logs** - Centralized logging for all Lambda functions
- **CloudWatch Metrics** - Performance and usage monitoring
- **Langfuse Analytics** - AI interaction tracking and evaluation

### Security and Compliance
- **IAM Least Privilege** - Minimal required permissions
- **VPC Security Groups** - Network-level access control
- **Encryption at Rest** - S3 and RDS encryption
- **API Key Authentication** - Secure API access control