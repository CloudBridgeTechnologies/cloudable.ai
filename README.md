# Colourable.AI - Multi-Tenant AWS Bedrock Agent Platform

[![Infrastructure](https://img.shields.io/badge/Infrastructure-Terraform-blue.svg)](https://terraform.io)
[![AWS](https://img.shields.io/badge/Cloud-AWS-orange.svg)](https://aws.amazon.com)
[![Bedrock](https://img.shields.io/badge/AI-AWS%20Bedrock-purple.svg)](https://aws.amazon.com/bedrock)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A production-ready, multi-tenant AI agent platform built on AWS Bedrock, designed to provide personalized customer insights through journey tracking and assessment summaries.

## 🚀 Features

- **Multi-Tenant Architecture**: Isolated data and AI agents per tenant
- **AWS Bedrock Integration**: Claude Sonnet 4 powered conversational AI
- **Real-time Data Access**: Direct database integration with Aurora PostgreSQL
- **RESTful API**: Clean HTTP endpoints for easy integration
- **Infrastructure as Code**: Complete Terraform deployment
- **Production Ready**: VPC isolation, encryption, monitoring, and logging

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   API Gateway   │────│  Orchestrator    │────│   Bedrock       │
│   (REST API)    │    │   Lambda         │    │   Agents        │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │                        │
                                │                        │
                       ┌──────────────────┐    ┌─────────────────┐
                       │   DB Actions     │    │   Aurora        │
                       │   Lambda         │────│   PostgreSQL    │
                       └──────────────────┘    └─────────────────┘
```

### Components

- **Orchestrator Lambda**: Handles API requests and manages Bedrock agent interactions
- **DB Actions Lambda**: Executes secure database queries with multi-tenant isolation
- **Bedrock Agents**: Tenant-specific AI agents with custom action groups
- **Aurora Database**: Serverless PostgreSQL with Data API for scalable data access
- **VPC**: Network isolation and security

## 🛠️ Quick Start

### Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.7.0
- Python 3.12+ (for Lambda functions)

### 1. Clone the Repository

```bash
git clone https://github.com/CloudBridgeTechnologies/colourable.ai.git
cd colourable.ai
```

### 2. Configure Environment

Create your tenant configuration file:

```bash
cp infras/envs/us-east-1/tenants.tfvars.example infras/envs/us-east-1/tenants.tfvars
```

Edit `tenants.tfvars` with your configuration:

```hcl
region = "us-east-1"
env    = "dev"

alert_emails = ["admin@yourdomain.com"]

tenants = {
  t001 = { name = "acme" }
  t002 = { name = "globex" }
}

enable_bedrock_agents = true
```

### 3. Deploy Infrastructure

#### Step 1: Deploy State Backend

```bash
cd infras/envs/state-bootstrap
terraform init
terraform apply
```

#### Step 2: Deploy Main Infrastructure

```bash
cd ../us-east-1
terraform init
terraform apply -var-file=tenants.tfvars
```

### 4. Verify Deployment

After deployment completes, test the API:

```bash
# Get the API endpoint
API_ENDPOINT=$(terraform output -raw api_endpoint)

# Test journey status
curl -X POST "$API_ENDPOINT/chat" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What is my journey status?",
    "tenant_id": "t001",
    "customer_id": "c001",
    "agent_alias_arn": "arn:aws:bedrock:us-east-1:ACCOUNT:agent-alias/AGENT_ID/ALIAS_ID"
  }'
```

## 📊 API Reference

### Chat Endpoint

**POST** `/chat`

Request body:
```json
{
  "message": "What is my journey status?",
  "tenant_id": "t001",
  "customer_id": "c001", 
  "agent_alias_arn": "arn:aws:bedrock:us-east-1:ACCOUNT:agent-alias/AGENT_ID/ALIAS_ID"
}
```

Response:
```json
{
  "answer": "Your journey status shows you are currently in the onboarding stage with 3 tasks completed. Your last update was on September 15, 2025 at 13:46:56.",
  "trace": []
}
```

### Supported Queries

- **Journey Status**: "What is my journey status?", "Show me my current progress"
- **Assessment Summary**: "Can you give me my assessment summary?", "What are my assessment results?"

## 🗄️ Database Schema

The system uses a multi-tenant database schema:

```sql
-- Tenants table
CREATE TABLE tenants (
  id VARCHAR(10) PRIMARY KEY,
  name VARCHAR(50) NOT NULL
);

-- Customers table  
CREATE TABLE customers (
  id VARCHAR(10) PRIMARY KEY,
  tenant_id VARCHAR(10) REFERENCES tenants(id),
  name VARCHAR(100) NOT NULL,
  email VARCHAR(100)
);

-- Journey tracking
CREATE TABLE journeys (
  id SERIAL PRIMARY KEY,
  tenant_id VARCHAR(10) REFERENCES tenants(id),
  customer_id VARCHAR(10) REFERENCES customers(id),
  stage VARCHAR(50) NOT NULL,
  tasks_completed INTEGER DEFAULT 0,
  last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Assessment data
CREATE TABLE assessments (
  id SERIAL PRIMARY KEY,
  tenant_id VARCHAR(10) REFERENCES tenants(id), 
  customer_id VARCHAR(10) REFERENCES customers(id),
  assessed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  q1 TEXT, q2 TEXT, q3 TEXT, q4 TEXT, q5 TEXT
);
```

## 🔧 Configuration

### Environment Variables

The system uses these key environment variables:

- `DB_CLUSTER_ARN`: Aurora cluster ARN
- `DB_SECRET_ARN`: Database credentials secret ARN  
- `DB_NAME`: Database name
- `REGION`: AWS region

### Terraform Variables

Key variables in `tenants.tfvars`:

| Variable | Description | Example |
|----------|-------------|---------|
| `region` | AWS region | `us-east-1` |
| `env` | Environment name | `dev` |
| `tenants` | Tenant configuration | `{t001 = {name = "acme"}}` |
| `enable_bedrock_agents` | Enable Bedrock agents | `true` |
| `alert_emails` | Notification emails | `["admin@domain.com"]` |

## 🔒 Security

- **Network Isolation**: All resources deployed in private VPC subnets
- **Encryption**: Data encrypted at rest and in transit
- **IAM**: Least privilege access with specific resource permissions
- **Multi-tenancy**: Database-level tenant isolation
- **Secrets Management**: AWS Secrets Manager for sensitive data

## 📈 Monitoring

The platform includes comprehensive monitoring:

- **CloudWatch Logs**: Application and infrastructure logs
- **CloudWatch Metrics**: Performance and usage metrics
- **AWS Budgets**: Cost monitoring and alerts
- **Lambda Insights**: Function performance monitoring

## 🚀 Deployment Environments

### Development
```bash
cd infras/envs/us-east-1
terraform workspace select dev  # or create if doesn't exist
terraform apply -var-file=tenants.tfvars
```

### Production
```bash
cd infras/envs/us-east-1
terraform workspace select prod
terraform apply -var-file=tenants.prod.tfvars
```

## 🧪 Testing

### Unit Tests
```bash
# Test Lambda functions locally
cd infras/lambdas/db_actions
python -m pytest tests/

cd ../orchestrator  
python -m pytest tests/
```

### Integration Tests
```bash
# Test full API flow
./scripts/test-api.sh
```

## 📝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Support

For support and questions:

- **Issues**: [GitHub Issues](https://github.com/CloudBridgeTechnologies/colourable.ai/issues)
- **Discussions**: [GitHub Discussions](https://github.com/CloudBridgeTechnologies/colourable.ai/discussions)
- **Email**: support@cloudbridge.tech

## 🙏 Acknowledgments

- AWS Bedrock team for the amazing AI capabilities
- Terraform team for infrastructure automation
- Claude AI for powering the conversational interface

---

**Built with ❤️ by CloudBridge Technologies**