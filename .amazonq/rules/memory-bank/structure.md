# Cloudable.AI Project Structure

## Directory Organization

### Core Infrastructure (`/infras/`)
- **`core/`** - Core infrastructure components and deployment scripts
  - Terraform configurations for main infrastructure
  - Database setup scripts (pgvector, customer status)
  - Lambda function implementations
  - Bedrock utilities and integrations
- **`lambdas/`** - Microservice Lambda functions
  - `kb_manager/` - Knowledge base operations and vector search
  - `document_summarizer/` - AI-powered document summarization
  - `s3_helper/` - S3 event handling and document processing
  - `orchestrator/` - Main API orchestration and routing
  - `authorizer/` - API authentication and authorization
  - `db_actions/` - Database operations and queries
- **`sql/`** - Database schema and seed data
- **`terraform/`** - Additional Terraform modules and configurations
- **`envs/`** - Environment-specific configurations (dev, us-east-1, state-bootstrap)

### Deployment and Testing
- **`test_files/`** - Sample documents for testing functionality
- **`test_scripts/`** - Comprehensive test suites for E2E validation
- **`langfuse_dashboard/`** - Monitoring and analytics dashboard
- **`docs/`** - Technical documentation and migration guides

### Configuration and Automation
- **`.github/workflows/`** - CI/CD pipelines for automated deployment
- **Root-level scripts** - Deployment, testing, and utility scripts

## Core Components and Relationships

### API Layer
```
API Gateway (REST) → Lambda Authorizer → Orchestrator Lambda
                                      ↓
                              Route to specific Lambda functions
```

### Document Processing Pipeline
```
Client Upload → S3 (via presigned URL) → S3 Event → S3 Helper Lambda
                                                         ↓
                                              Parallel Processing:
                                         ┌─ Document Summarizer
                                         └─ KB Sync Trigger → Bedrock KB
```

### Data Storage Architecture
```
PostgreSQL RDS (pgvector) ← Vector embeddings and metadata
S3 Buckets ← Raw documents and processed summaries
AWS Bedrock ← Knowledge base and LLM processing
```

### Multi-tenant Isolation
- **Tenant-specific S3 buckets**: `BUCKET_[TENANT]` environment variables
- **Database-level isolation**: Tenant ID filtering in all queries
- **API-level security**: X-User-ID header validation and routing

## Architectural Patterns

### Microservices Architecture
- **Single Responsibility**: Each Lambda function handles specific domain operations
- **Event-Driven**: S3 events trigger document processing workflows
- **API Gateway Pattern**: Centralized API management with distributed processing

### Infrastructure as Code
- **Terraform Modules**: Reusable infrastructure components
- **Environment Separation**: Dev, staging, and production configurations
- **State Management**: Remote state storage with proper locking

### Security Patterns
- **Defense in Depth**: WAF → API Gateway → Lambda Authorizer → Function-level security
- **Least Privilege**: IAM roles with minimal required permissions
- **Encryption**: At-rest and in-transit encryption for all data

### Monitoring and Observability
- **Structured Logging**: Consistent logging across all Lambda functions
- **Metrics Collection**: CloudWatch metrics and custom dashboards
- **Distributed Tracing**: Langfuse integration for AI interaction monitoring

## Development Workflow

### Local Development
1. **Environment Setup**: AWS credentials and region configuration
2. **Infrastructure Deployment**: Terraform-based resource provisioning
3. **Database Initialization**: pgvector setup and schema creation
4. **Testing**: Comprehensive E2E test suites

### CI/CD Pipeline
1. **Code Validation**: Automated testing and linting
2. **Infrastructure Deployment**: Terraform plan and apply
3. **Lambda Updates**: Function code deployment and configuration
4. **Integration Testing**: API endpoint validation and monitoring setup

### Multi-Environment Strategy
- **Development**: Full feature testing with isolated resources
- **Production**: Optimized configurations with enhanced monitoring
- **State Bootstrap**: Centralized Terraform state management