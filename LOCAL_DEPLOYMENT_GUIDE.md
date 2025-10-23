# Cloudable.AI Local Deployment Guide

This guide provides instructions for deploying the Cloudable.AI platform from your local machine using Terraform.

## Prerequisites

- AWS CLI installed and configured
- Terraform v1.5.0 or newer
- jq (for parsing JSON outputs)

## Step 1: Set Up AWS Profile

Run the AWS profile setup script:

```bash
./setup_aws_profile.sh
```

This will:
1. Create an AWS CLI profile named "cloudable"
2. Generate a `set_aws_env.sh` script to set environment variables

After running the setup script, load the environment variables:

```bash
source set_aws_env.sh
```

## Step 2: Configure Terraform Backend (Optional)

By default, the deployment uses a local Terraform state. If you want to use a remote S3 backend:

1. Create an S3 bucket and DynamoDB table for state management:

```bash
aws s3 mb s3://cloudable-tfstate-dev-$(date +%Y%m%d)
aws dynamodb create-table \
    --table-name cloudable-tf-locks-dev \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
```

2. Edit `infras/envs/us-east-1/backend.tf` and uncomment the S3 backend configuration:

```hcl
terraform {
  backend "s3" {
    bucket         = "cloudable-tfstate-dev-YYYYMMDD"  # Replace with your bucket name
    key            = "envs/us-east-1/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloudable-tf-locks-dev"
    encrypt        = true
  }
}
```

## Step 3: Deploy Infrastructure

Run the deployment script:

```bash
./deploy_terraform.sh [environment] [region]
```

Parameters:
- `environment`: The environment to deploy to (default: dev)
- `region`: The AWS region to deploy to (default: us-east-1)

For example:

```bash
./deploy_terraform.sh dev us-east-1
```

The script will:
1. Create a `terraform.tfvars` file
2. Initialize Terraform
3. Create and apply a Terraform plan
4. Save outputs to `deployment_outputs.json`

## Step 4: Test API Endpoints

After deployment, test the API endpoints:

```bash
./test_api_endpoints.sh
```

This script will:
1. Load API endpoint details from `deployment_outputs.json`
2. Test all API endpoints (Chat, KB Query, Upload URL, etc.)
3. Save test results to `api_test_results.json`

## Step 5: Clean Up Resources (Optional)

When you're done with the environment, you can destroy all resources:

```bash
cd infras/envs/us-east-1
terraform destroy
```

## Troubleshooting

### Common Issues

1. **AWS Authentication Errors**:
   ```
   Error: No valid credential sources found
   ```
   - Ensure AWS credentials are properly configured
   - Run `source set_aws_env.sh` to set environment variables

2. **Terraform State Errors**:
   ```
   Error: Error loading state
   ```
   - Check backend configuration in `backend.tf`
   - Ensure S3 bucket and DynamoDB table exist

3. **API Gateway 403 Errors**:
   ```
   {"message":"Forbidden"}
   ```
   - Verify API key is correct in requests
   - Check API Gateway usage plan configuration

### Advanced Configuration

You can customize the deployment by editing:

- `infras/envs/us-east-1/terraform.tfvars`: Main configuration
- `infras/envs/us-east-1/variables.tf`: Variable definitions
- `infras/envs/us-east-1/locals.tf`: Local variables

## Additional Resources

- [AWS CLI Configuration](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Bedrock Documentation](https://docs.aws.amazon.com/bedrock)
