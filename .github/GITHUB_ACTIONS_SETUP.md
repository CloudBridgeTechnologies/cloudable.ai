# GitHub Actions Setup for Cloudable.AI

This guide explains how to set up GitHub Actions for the Cloudable.AI project. These workflows automate deployment, testing, and monitoring of the Agent Core implementation.

## Required GitHub Secrets

To use the workflows, you'll need to configure the following secrets in your GitHub repository:

### AWS Authentication

1. **AWS_ROLE_TO_ASSUME**
   - Role ARN for GitHub Actions to assume in your AWS account
   - Example: `arn:aws:iam::123456789012:role/github-actions-role`

### Langfuse Telemetry

2. **LANGFUSE_PUBLIC_KEY**
   - Your Langfuse public key
   - Example: `pk-lf-xxxxxxxxxxxxxxxx`

3. **LANGFUSE_SECRET_KEY**
   - Your Langfuse secret key
   - Example: `sk-lf-xxxxxxxxxxxxxxxx`

4. **LANGFUSE_HOST** (optional)
   - Langfuse API host, defaults to `https://cloud.langfuse.com`

## Setting Up AWS IAM Role for GitHub Actions

1. Create an IAM role in your AWS account:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:CloudBridgeTechnologies/cloudable.ai:*"
        }
      }
    }
  ]
}
```

2. Attach the following policies to the role:
   - `AmazonAPIGatewayAdministrator`
   - `AmazonS3FullAccess`
   - `AmazonDynamoDBFullAccess`
   - `AmazonRDSFullAccess`
   - `AmazonLambdaFullAccess`
   - `AmazonSSMFullAccess`
   - `AmazonBedrockFullAccess`
   - `CloudWatchFullAccess`
   - `IAMFullAccess`

3. Configure GitHub OIDC provider in AWS:
   - Go to IAM > Identity Providers > Add Provider
   - Select "OpenID Connect"
   - Provider URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`

## Setting Up GitHub Secrets

1. Go to your GitHub repository
2. Navigate to Settings > Secrets and variables > Actions
3. Click "New repository secret"
4. Add the required secrets as listed above

## Configuring Langfuse

1. Sign up for a Langfuse account at [https://langfuse.com](https://langfuse.com)
2. Create a new project
3. Get your API keys from the project settings
4. Add the keys to GitHub Secrets as described above

## Workflow Overview

1. **terraform-deploy.yml**: Deploys all infrastructure using Terraform
   - Triggered on push to main branch or manually
   - Validates, plans, and applies Terraform code
   - Updates API configuration after deployment

2. **api-test.yml**: Tests the API endpoints
   - Triggered after Terraform deployment or manually
   - Tests KB Query API and Chat API
   - Generates test reports

3. **agent-core-monitoring.yml**: Monitors the Agent Core
   - Runs on a schedule (every 6 hours) or manually
   - Checks agent status and telemetry
   - Updates Langfuse credentials if needed

4. **lambda-update.yml**: Updates Lambda functions
   - Triggered when Lambda code changes or manually
   - Updates specific functions or all functions
   - Tests the updated functions

## Using the Workflows

### Deploy Infrastructure

```bash
# From GitHub UI: Actions > Terraform Deploy > Run workflow
# Select the target environment (dev, qa, prod)
```

### Update Lambda Functions

```bash
# From GitHub UI: Actions > Update Lambda Functions > Run workflow
# Select the target environment
# Optionally specify a single function to update
```

### Run API Tests

```bash
# From GitHub UI: Actions > API Tests > Run workflow
# Select the target environment
```

### Monitor Agent Core

```bash
# From GitHub UI: Actions > Agent Core Monitoring > Run workflow
# Select the target environment
```
