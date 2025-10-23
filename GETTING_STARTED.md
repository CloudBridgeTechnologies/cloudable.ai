# Cloudable.AI - Getting Started Guide

This guide will walk you through the process of setting up and deploying the Cloudable.AI platform, a multi-tenant AI agent platform built on AWS Bedrock with enterprise-grade security controls.

## Prerequisites

Before you begin, make sure you have the following:

1. **AWS Account** with appropriate permissions to create:
   - Lambda functions
   - API Gateway
   - S3 buckets
   - IAM roles and policies
   - Bedrock agents and knowledge bases
   - OpenSearch serverless collections
   - CloudWatch resources
   - RDS Aurora PostgreSQL

2. **Development Environment**:
   - AWS CLI installed and configured
   - Terraform >= 1.5.0
   - Python 3.9+ (for Lambda functions)
   - Git client

3. **AWS Bedrock Access**:
   - Ensure your AWS account has access to Bedrock models
   - Claude 3 Sonnet should be enabled in your account

## Step 1: Clone the Repository

```bash
git clone https://github.com/CloudBridgeTechnologies/cloudable.ai.git
cd cloudable.ai
```

## Step 2: Configure AWS CLI

### Option 1: Default Profile

Configure your AWS CLI with your credentials:

```bash
aws configure
```

### Option 2: Named Profile

Create a specific profile for this project:

```bash
aws configure --profile cloudable
```

Then, set this profile for your current session:

```bash
export AWS_PROFILE=cloudable
```

## Step 3: Configure Environment

Create your tenant configuration file by copying the example:

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

## Step 4: Initialize Terraform Backend

For local development, you can use the local backend initially:

```bash
cd infras/envs/us-east-1
terraform init
```

For production environments, set up a remote S3 backend:

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://cloudable-tfstate-dev-$(date +%Y%m%d)

# Create DynamoDB table for state locking
aws dynamodb create-table \
    --table-name cloudable-tf-locks-dev \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region us-east-1
```

Then edit `backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "cloudable-tfstate-dev-YYYYMMDD"  # Replace with your bucket name
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloudable-tf-locks-dev"
    encrypt        = true
  }
}
```

Then reinitialize Terraform:

```bash
terraform init -reconfigure
```

## Step 5: Deploy Infrastructure

### Local Deployment

```bash
cd infras/envs/us-east-1
terraform apply -var-file=tenants.tfvars
```

### GitHub Actions Deployment

For automated deployments using GitHub Actions:

1. Set up GitHub repository secrets:
   - `AWS_ROLE_TO_ASSUME`: ARN of the IAM role to assume for GitHub Actions

2. Configure OIDC in your AWS account to allow GitHub Actions to assume the role:
   ```bash
   # Create OIDC provider
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
   
   # Create IAM role
   aws iam create-role \
     --role-name github-actions-role \
     --assume-role-policy-document file://github-actions-trust-policy.json
   
   # Attach policies
   aws iam attach-role-policy \
     --role-name github-actions-role \
     --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
   ```

3. Run the workflow from GitHub Actions:
   - Go to GitHub Actions > Terraform Deploy > Run workflow
   - Select the environment: `dev`
   - Click "Run workflow"

## Step 6: Set Up Langfuse Telemetry (Optional)

1. Create an account on [Langfuse](https://langfuse.com/)
2. Create a new project and get your API keys
3. Set up the following in AWS Systems Manager Parameter Store:
   ```bash
   aws ssm put-parameter \
     --name "/cloudable/dev/langfuse/public_key" \
     --value "your-public-key" \
     --type "SecureString"
   
   aws ssm put-parameter \
     --name "/cloudable/dev/langfuse/secret_key" \
     --value "your-secret-key" \
     --type "SecureString"
   ```

## Step 7: Verify Deployment

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

## Step 8: Test Document Processing

1. Upload a document:
   ```bash
   # Get presigned URL
   UPLOAD_RESPONSE=$(curl -X POST "$API_ENDPOINT/kb/upload-url" \
     -H "Content-Type: application/json" \
     -H "x-api-key: $API_KEY" \
     -d '{
       "tenant_id": "t001",
       "filename": "vacation-policy.pdf"
     }')
   
   PRESIGNED_URL=$(echo $UPLOAD_RESPONSE | jq -r '.presigned_url')
   
   # Upload document
   curl -X PUT "$PRESIGNED_URL" \
     -H "Content-Type: application/pdf" \
     --data-binary @vacation-policy.pdf
   ```

2. Query the knowledge base:
   ```bash
   curl -X POST "$API_ENDPOINT/kb/query" \
     -H "Content-Type: application/json" \
     -H "x-api-key: $API_KEY" \
     -d '{
       "tenant_id": "t001",
       "query": "What is our vacation policy?"
     }'
   ```

## Step 9: Monitor and Analyze

1. Access the CloudWatch dashboard:
   ```bash
   AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   echo "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=Cloudable-AI-Performance-dev"
   ```

2. View Langfuse traces:
   - Log in to your Langfuse account
   - Navigate to the Traces section
   - Filter by session ID or trace ID

## Troubleshooting

### Common Issues

1. **Terraform Error: Error creating CloudWatch Logs Log Group: ResourceAlreadyExistsException**
   - Solution: Import the existing resource into Terraform state:
     ```bash
     terraform import aws_cloudwatch_log_group.example /aws/lambda/function-name
     ```

2. **API Gateway 403 Forbidden**
   - Check that you're using the correct API key
   - Verify that the API key is associated with the correct usage plan
   - Check API Gateway deployment and stage

3. **Lambda Function Error**
   - Check CloudWatch Logs for the function
   - Ensure IAM roles have appropriate permissions
   - Verify environment variables are set correctly

### Getting Help

If you encounter issues:

1. Check the CloudWatch logs for detailed error messages
2. Review the GitHub issues for similar problems
3. Create a new issue with detailed information about your problem

## Next Steps

Once your platform is up and running:

1. **Add real tenant data**: Update the database with actual customer journey data
2. **Upload your documents**: Populate the knowledge base with your company's documents
3. **Customize the Agent**: Update the agent instructions to match your company's tone and requirements
4. **Set up monitoring alerts**: Configure CloudWatch alerts for important metrics
5. **Implement CI/CD**: Set up automated testing and deployment pipelines

For more detailed information, refer to the following documentation:
- [README.md](README.md) - Overview of the platform
- [WORKFLOW_EXECUTION_INSTRUCTIONS.md](WORKFLOW_EXECUTION_INSTRUCTIONS.md) - GitHub Actions workflow instructions
- [API_ENDPOINT_ARCHITECTURE.md](API_ENDPOINT_ARCHITECTURE.md) - API endpoint architecture details
- [AGENT_CORE_IMPLEMENTATION.md](AGENT_CORE_IMPLEMENTATION.md) - Agent Core implementation details

## Support

For support and questions:

- **Issues**: [GitHub Issues](https://github.com/CloudBridgeTechnologies/cloudable.ai/issues)
- **Discussions**: [GitHub Discussions](https://github.com/CloudBridgeTechnologies/cloudable.ai/discussions)
- **Email**: support@cloudbridge.co.uk
