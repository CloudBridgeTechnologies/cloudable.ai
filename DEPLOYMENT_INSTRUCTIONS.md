# Cloudable.AI Deployment Instructions

This document provides step-by-step instructions for deploying the Cloudable.AI platform with Agent Core and Langfuse telemetry using GitHub Actions workflows.

## Prerequisites

1. **AWS Account**: You must have an AWS account with appropriate permissions
2. **GitHub Repository**: Code pushed to the CloudBridgeTechnologies/cloudable.ai repository
3. **Langfuse Account**: For telemetry and tracing capabilities (optional but recommended)

## Initial Setup

### 1. Configure AWS OIDC Provider for GitHub Actions

Follow the instructions in `.github/GITHUB_ACTIONS_SETUP.md` to set up the AWS IAM role and OIDC provider for GitHub Actions.

### 2. Configure GitHub Secrets

Add the following secrets to your GitHub repository:
- `AWS_ROLE_TO_ASSUME`: ARN of the IAM role created in step 1
- `LANGFUSE_PUBLIC_KEY`: Your Langfuse public key
- `LANGFUSE_SECRET_KEY`: Your Langfuse secret key
- `LANGFUSE_HOST`: Langfuse API host (optional)

## Deployment Process

### Option 1: Manual Deployment via GitHub Actions

1. **Trigger Terraform Deployment**:
   - Go to the GitHub repository
   - Navigate to Actions > Terraform Deploy > Run workflow
   - Select the target environment (dev, qa, prod)
   - Click "Run workflow"

2. **Wait for Deployment to Complete**:
   - The workflow will validate, plan, and apply the Terraform configuration
   - This may take 15-20 minutes for a complete deployment
   - Once completed, API details will be automatically updated

3. **Run API Tests**:
   - Navigate to Actions > API Tests > Run workflow
   - Select the same environment
   - Click "Run workflow"
   - This will verify that all API endpoints are working correctly

4. **Update Lambda Functions** (if needed):
   - Navigate to Actions > Update Lambda Functions > Run workflow
   - Select the environment
   - Optionally specify a specific function to update
   - Click "Run workflow"

### Option 2: Automatic Deployment via Git Push

1. **Push Code to Main Branch**:
   - The Terraform deployment workflow is automatically triggered on push to main
   - Changes to `infras/**` files will trigger deployment
   - Changes to Lambda function code will trigger Lambda updates

2. **Monitor Deployment Progress**:
   - Check the Actions tab for deployment status
   - View deployment logs for detailed information

## Post-Deployment Validation

### 1. Manual Validation

Run the validation script to ensure all components are properly configured:

```bash
cd infras/envs/us-east-1
python validate_agent_core.py --tenant-id t001 --env dev
```

### 2. Test API Endpoints

Test the API endpoints using curl or Postman:

**KB Query API**:
```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: YOUR_API_KEY" \
  -d '{"tenant_id":"t001","query":"What are the AI services offered by AWS?"}' \
  https://YOUR_API_ID.execute-api.us-east-1.amazonaws.com/dev/kb/query
```

**Chat API**:
```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: YOUR_API_KEY" \
  -d '{"tenant_id":"t001","customer_id":"test_user","message":"What is my journey status?"}' \
  https://YOUR_API_ID.execute-api.us-east-1.amazonaws.com/dev/chat
```

### 3. Check Agent Core Monitoring

1. **Run Agent Core Monitoring**:
   - Navigate to Actions > Agent Core Monitoring > Run workflow
   - Select the environment
   - Click "Run workflow"

2. **Review Monitoring Report**:
   - Download the monitoring report artifact
   - Verify that all components are healthy

## Troubleshooting

### Common Issues

1. **Terraform Deployment Failures**:
   - Check the Terraform logs for specific errors
   - Verify that AWS credentials and permissions are correct
   - Check for resource naming conflicts or limits

2. **API Endpoint Failures**:
   - Check Lambda function logs in CloudWatch
   - Verify that API Gateway is correctly configured
   - Check API key and usage plan settings

3. **Agent Core Issues**:
   - Verify that Bedrock Agent is in "PREPARED" state
   - Check Knowledge Base status and configuration
   - Review agent logs in CloudWatch

### Support

For additional assistance, contact the CloudBridge Technologies support team or open an issue on GitHub.

## Agent Core Capabilities

The Agent Core implementation provides:

1. **Advanced Reasoning**: Enhanced agentic capabilities with contextual awareness
2. **Intelligent Routing**: Smart routing between personal data and knowledge base
3. **Comprehensive Telemetry**: Detailed logging and tracing with Langfuse
4. **Performance Monitoring**: Real-time metrics and dashboards in CloudWatch

For more details on the Agent Core implementation, refer to the `AGENT_CORE_IMPLEMENTATION.md` document.
