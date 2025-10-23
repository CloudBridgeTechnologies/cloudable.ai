# Cloudable.AI - Responsible AI Multi-Tenant Platform

[![Infrastructure](https://img.shields.io/badge/Infrastructure-Terraform-blue.svg)](https://terraform.io)
[![AWS](https://img.shields.io/badge/Cloud-AWS-orange.svg)](https://aws.amazon.com)
[![Bedrock](https://img.shields.io/badge/AI-AWS%20Bedrock-purple.svg)](https://aws.amazon.com/bedrock)
[![Security](https://img.shields.io/badge/Security-Responsible%20AI-red.svg)](#-responsible-ai--security-features)
[![Monitoring](https://img.shields.io/badge/Monitoring-CloudWatch-yellow.svg)](#-monitoring--analytics)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Agent](https://img.shields.io/badge/Agent-Bedrock%20Agent%20Core-blueviolet)](https://aws.amazon.com/bedrock/agent-core)
[![Telemetry](https://img.shields.io/badge/Telemetry-Langfuse-lightgrey)](https://langfuse.com)

A production-ready, multi-tenant AI agent platform built on AWS Bedrock with enterprise-grade responsible AI security controls. Designed to provide personalized customer insights through journey tracking and assessment summaries while ensuring safety, privacy, and compliance.

> **🆕 Latest Update**: Enhanced with AWS Bedrock Agent Core and Langfuse telemetry for advanced observability, tracing, and performance monitoring. Now with CI/CD via GitHub Actions workflows.

## 🚀 Features

### 🛡️ **Responsible AI & Security**
- **API Key Authentication**: Secure API access with API keys and usage plans
- **Advanced Content Filtering**: HIGH-strength guardrails for hate, violence, sexual content, and misconduct
- **Prompt Injection Protection**: Real-time detection and blocking of malicious prompts
- **PII Data Protection**: Automatic blocking/anonymization of emails, phones, SSN, credit cards
- **Input Validation**: Comprehensive sanitization and format validation
- **Rate Limiting**: API throttling (10 RPS) with burst capacity protection (20 requests)

### 🏗️ **Platform Architecture**
- **Multi-Tenant Architecture**: Isolated data and AI agents per tenant
- **AWS Bedrock Integration**: Claude Sonnet powered conversational AI with inference profiles
- **Real-time Data Access**: Direct database integration with Aurora PostgreSQL
- **RESTful API**: Clean HTTP endpoints with security controls
- **Infrastructure as Code**: Complete Terraform deployment
- **CI/CD Pipeline**: GitHub Actions workflows for deployment and testing

### 📊 **Monitoring & Observability**
- **AI Safety Dashboard**: Real-time monitoring of security events and threats
- **CloudWatch Alerting**: Automated notifications for security violations
- **Audit Trails**: Complete logging of all AI interactions and security events
- **Usage Analytics**: Model invocation tracking and anomaly detection
- **Langfuse Telemetry**: Advanced LLM observability with session-based tracing and quality scoring
- **Production Ready**: VPC isolation, encryption, comprehensive monitoring

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   API Gateway   │────│  Orchestrator    │────│   Bedrock       │
│  + Rate Limiting│    │  + Agent Core    │    │  + Guardrails   │
│  + Throttling   │    │  + Telemetry     │    │  + Content Filt.│
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                        │
         │                       │                        │
         ▼                       ▼                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  CloudWatch     │    │   DB Actions     │    │   Aurora        │
│  + Monitoring   │    │   Lambda         │────│   PostgreSQL    │
│  + Alerting     │    │  + SQL Security  │    │  + Encryption   │
│  + Dashboard    │    └──────────────────┘    └─────────────────┘
└─────────────────┘
```

### Agent Core Components

- **Orchestrator Lambda**: Enhanced with Agent Core for intelligent routing and reasoning
- **Langfuse Integration**: Advanced telemetry and tracing for response quality scoring
- **Bedrock Agents**: Tenant-specific AI agents with optimized inference parameters
- **Knowledge Base Integration**: Seamless connection to Bedrock Knowledge Bases
- **Action Groups**: Advanced API schemas for flexible function calling

## 🚀 Quick Start

### Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.5.0
- Python 3.9+ (for Lambda functions)
- GitHub account with appropriate secrets configured (for CI/CD)

### 1. Clone the Repository

```bash
git clone https://github.com/CloudBridgeTechnologies/cloudable.ai.git
cd cloudable.ai
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

### 3. Deploy Using GitHub Actions

Follow the instructions in [WORKFLOW_EXECUTION_INSTRUCTIONS.md](WORKFLOW_EXECUTION_INSTRUCTIONS.md) to deploy using GitHub Actions workflows.

For local deployment:

```bash
cd infras/envs/us-east-1
terraform init
terraform apply -var-file=tenants.tfvars
```

### 4. Verify Deployment

After deployment completes, test the API:

```bash
# Get the API endpoint and secure API key
API_ENDPOINT=$(terraform output -raw secure_api_endpoint)
API_KEY=$(terraform output -raw secure_api_key)

# Test journey status
curl -X POST "$API_ENDPOINT/chat" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{
    "message": "What is my journey status?",
    "tenant_id": "t001",
    "customer_id": "c001",
    "session_id": "test-session-001"
  }'
```

## 📊 API Reference

### Authentication

All API endpoints are protected with API key authentication. You need to include the API key in the `x-api-key` header:

```bash
curl -X POST "$API_ENDPOINT/chat" \
  -H "Content-Type: application/json" \
  -H "x-api-key: your-api-key-value" \
  -d '{"tenant_id": "t001", "customer_id": "c001", "message": "Hello"}'
```

To retrieve your API key:

```bash
cd infras/envs/us-east-1
terraform output -raw secure_api_key
```

### Chat Endpoint (Agent Core)

**POST** `/chat`

Request body:
```json
{
  "message": "What is my journey status?",
  "tenant_id": "t001",
  "customer_id": "c001", 
  "session_id": "unique-session-id-123",
  "trace_id": "optional-trace-id-for-telemetry"
}
```

Headers:
```
Content-Type: application/json
x-api-key: your-api-key-value
```

Response:
```json
{
  "answer": "Your journey status shows you are currently in the onboarding stage with 3 tasks completed. Your last update was on September 15, 2025 at 13:46:56.",
  "trace": [],
  "session_id": "unique-session-id-123",
  "trace_id": "generated-trace-id-xyz",
  "analysis": {
    "quality_score": 0.92,
    "response_time_ms": 1245,
    "sentiment": "positive"
  }
}
```

### Supported Queries

- **Journey Status**: "What is my journey status?", "Show me my current progress"
- **Assessment Summary**: "Can you give me my assessment summary?", "What are my assessment results?"
- **Knowledge Queries**: "What is our vacation policy?", "How do I submit an expense report?"

## 🛠️ AWS Profile Configuration

To configure AWS profiles for this project:

1. Create or edit the `~/.aws/credentials` file:

```ini
[cloudable]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
region = us-east-1
```

2. Create or edit the `~/.aws/config` file:

```ini
[profile cloudable]
region = us-east-1
output = json
```

3. Export the profile before running Terraform:

```bash
export AWS_PROFILE=cloudable
terraform apply -var-file=tenants.tfvars
```

4. For GitHub Actions, configure the following secrets:

```
AWS_ROLE_TO_ASSUME=arn:aws:iam::YOUR_ACCOUNT_ID:role/github-actions-role
```

## 📈 Monitoring & Telemetry

### Langfuse Observability

The platform integrates Langfuse for advanced LLM observability:

- **Session-Based Tracing**: Track multi-turn conversations
- **Response Quality Scoring**: Automatically evaluate response quality
- **Latency Monitoring**: Track end-to-end and component-level response times
- **Error Analysis**: Identify patterns in failed interactions
- **User Feedback Collection**: Capture explicit and implicit user feedback

### CloudWatch Dashboard

Access the CloudWatch dashboard:
- **AI Performance**: `https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=Cloudable-AI-Performance-dev`
- **Security Events**: `https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=Cloudable-AI-Security-dev`

## 🧪 Testing

### Local Testing

Run the local workflow test script to validate configurations:

```bash
./local_workflow_test.sh
```

### GitHub Actions Testing

1. Go to GitHub Actions > API Tests > Run workflow
2. Select the environment: `dev`
3. Click "Run workflow"

## 🔧 Configuration

### Environment Variables

The system uses these key environment variables:

- `TELEMETRY_ENABLED`: Enable/disable telemetry (default: true)
- `LANGFUSE_PUBLIC_KEY`: Langfuse public key for telemetry
- `LANGFUSE_SECRET_KEY`: Langfuse secret key for telemetry
- `LANGFUSE_HOST`: Langfuse API host (default: https://api.langfuse.com)
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
| `agent_model_arn` | Bedrock model ARN | `anthropic.claude-3-sonnet-20240229-v1:0` |

## 🙏 Acknowledgments

- AWS Bedrock team for the amazing AI capabilities
- Terraform team for infrastructure automation
- Claude AI for powering the conversational interface
- Langfuse for advanced LLM observability

---

**Built with ❤️ by CloudBridge Technologies**