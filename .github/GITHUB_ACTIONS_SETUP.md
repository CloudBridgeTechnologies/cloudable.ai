# GitHub Actions Setup Guide

This guide explains how to set up GitHub Actions workflows for automated deployment and testing of the Cloudable.AI platform.

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **GitHub Repository** with the Cloudable.AI codebase
3. **GitHub Actions** enabled for your repository

## Setting Up OIDC Provider

To allow GitHub Actions to assume an AWS IAM role, you need to set up an OIDC provider in your AWS account:

1. **Create OIDC Provider**:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

2. **Create Trust Policy**:

Replace `AWS_ACCOUNT_ID` with your actual AWS account ID in the `github-actions-trust-policy.json` file:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
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

3. **Create IAM Role**:

```bash
aws iam create-role \
  --role-name github-actions-role \
  --assume-role-policy-document file://github-actions-trust-policy.json
```

4. **Attach Policies to Role**:

For simplicity, you can attach the AdministratorAccess policy (for development only):

```bash
aws iam attach-role-policy \
  --role-name github-actions-role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

For production, it's recommended to create a more restricted policy:

```bash
aws iam create-policy \
  --policy-name github-actions-cloudable-policy \
  --policy-document file://github-actions-policy.json

aws iam attach-role-policy \
  --role-name github-actions-role \
  --policy-arn arn:aws:iam::AWS_ACCOUNT_ID:policy/github-actions-cloudable-policy
```

## GitHub Secrets Configuration

Set up the following repository secrets in GitHub:

1. Go to your GitHub repository
2. Navigate to **Settings > Secrets and variables > Actions**
3. Click on **New repository secret**
4. Add the following secrets:

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `AWS_ROLE_TO_ASSUME` | `arn:aws:iam::AWS_ACCOUNT_ID:role/github-actions-role` | ARN of the IAM role for GitHub Actions |
| `AWS_REGION` | `us-east-1` | AWS region for deployment |

## Available Workflows

The repository includes the following GitHub Actions workflows:

### 1. AWS Resources Setup (`aws-setup.yml`)

Sets up the AWS resources needed for Terraform state management (S3 bucket and DynamoDB table).

**Manual trigger parameters**:
- `environment`: Environment name (e.g., `dev`, `staging`, `prod`)
- `aws_region`: AWS region (default: `us-east-1`)
- `s3_bucket_name`: S3 bucket name for Terraform state
- `dynamodb_table_name`: DynamoDB table name for state locking

### 2. Terraform Deploy (`terraform-deploy.yml`)

Deploys the Cloudable.AI infrastructure using Terraform.

**Manual trigger parameters**:
- `environment`: Environment name (e.g., `dev`, `staging`, `prod`)
- `destroy`: Whether to destroy the infrastructure (default: `false`)

### 3. API Tests (`api-test.yml`)

Runs API tests against the deployed infrastructure.

**Manual trigger parameters**:
- `environment`: Environment name (e.g., `dev`, `staging`, `prod`)

### 4. Agent Core Monitoring (`agent-core-monitoring.yml`)

Monitors Agent Core performance and updates telemetry configuration.

**Manual trigger parameters**:
- `environment`: Environment name (e.g., `dev`, `staging`, `prod`)
- `update_langfuse`: Whether to update Langfuse credentials (default: `false`)
- `langfuse_public_key`: Langfuse public key (required if `update_langfuse` is `true`)
- `langfuse_secret_key`: Langfuse secret key (required if `update_langfuse` is `true`)

### 5. Lambda Update (`lambda-update.yml`)

Updates Lambda functions without redeploying the entire infrastructure.

**Manual trigger parameters**:
- `environment`: Environment name (e.g., `dev`, `staging`, `prod`)
- `function_name`: Name of the Lambda function to update (leave empty to update all functions)

## Running Workflows

To run a workflow manually:

1. Go to your GitHub repository
2. Navigate to **Actions**
3. Select the workflow you want to run
4. Click on **Run workflow**
5. Enter the required parameters
6. Click on **Run workflow**

## Workflow Dependencies

The workflows should be run in the following order:

1. AWS Resources Setup (`aws-setup.yml`) - only needed once
2. Terraform Deploy (`terraform-deploy.yml`)
3. API Tests (`api-test.yml`)

The Agent Core Monitoring and Lambda Update workflows can be run as needed after the infrastructure is deployed.

## Troubleshooting

If your workflows fail, check the following:

1. **OIDC Provider Configuration**: Ensure the OIDC provider is set up correctly in AWS
2. **IAM Role Permissions**: Ensure the role has the necessary permissions
3. **GitHub Secrets**: Ensure the secrets are set up correctly
4. **Workflow File Syntax**: Validate the workflow YAML syntax

Common errors:
- `AssumeRoleWithWebIdentity Error`: Check the trust policy configuration
- `Access Denied`: Check the IAM role permissions
- `Permission Denied`: Check the GitHub Actions permissions in the workflow file

## Best Practices

1. **Environment Variables**: Store sensitive information in GitHub Secrets
2. **Least Privilege**: Use the minimum required permissions for the IAM role
3. **Testing**: Always run tests after deployment
4. **Monitoring**: Set up monitoring and alerting for your infrastructure
5. **Documentation**: Keep this documentation up to date with any changes to the workflows
This guide explains how to set up GitHub Actions workflows for automated deployment and testing of the Cloudable.AI platform.

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **GitHub Repository** with the Cloudable.AI codebase
3. **GitHub Actions** enabled for your repository

## Setting Up OIDC Provider

To allow GitHub Actions to assume an AWS IAM role, you need to set up an OIDC provider in your AWS account:

1. **Create OIDC Provider**:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

2. **Create Trust Policy**:

Replace `AWS_ACCOUNT_ID` with your actual AWS account ID in the `github-actions-trust-policy.json` file:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
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

3. **Create IAM Role**:

```bash
aws iam create-role \
  --role-name github-actions-role \
  --assume-role-policy-document file://github-actions-trust-policy.json
```

4. **Attach Policies to Role**:

For simplicity, you can attach the AdministratorAccess policy (for development only):

```bash
aws iam attach-role-policy \
  --role-name github-actions-role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

For production, it's recommended to create a more restricted policy:

```bash
aws iam create-policy \
  --policy-name github-actions-cloudable-policy \
  --policy-document file://github-actions-policy.json

aws iam attach-role-policy \
  --role-name github-actions-role \
  --policy-arn arn:aws:iam::AWS_ACCOUNT_ID:policy/github-actions-cloudable-policy
```

## GitHub Secrets Configuration

Set up the following repository secrets in GitHub:

1. Go to your GitHub repository
2. Navigate to **Settings > Secrets and variables > Actions**
3. Click on **New repository secret**
4. Add the following secrets:

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `AWS_ROLE_TO_ASSUME` | `arn:aws:iam::AWS_ACCOUNT_ID:role/github-actions-role` | ARN of the IAM role for GitHub Actions |
| `AWS_REGION` | `us-east-1` | AWS region for deployment |

## Available Workflows

The repository includes the following GitHub Actions workflows:

### 1. AWS Resources Setup (`aws-setup.yml`)

Sets up the AWS resources needed for Terraform state management (S3 bucket and DynamoDB table).

**Manual trigger parameters**:
- `environment`: Environment name (e.g., `dev`, `staging`, `prod`)
- `aws_region`: AWS region (default: `us-east-1`)
- `s3_bucket_name`: S3 bucket name for Terraform state
- `dynamodb_table_name`: DynamoDB table name for state locking

### 2. Terraform Deploy (`terraform-deploy.yml`)

Deploys the Cloudable.AI infrastructure using Terraform.

**Manual trigger parameters**:
- `environment`: Environment name (e.g., `dev`, `staging`, `prod`)
- `destroy`: Whether to destroy the infrastructure (default: `false`)

### 3. API Tests (`api-test.yml`)

Runs API tests against the deployed infrastructure.

**Manual trigger parameters**:
- `environment`: Environment name (e.g., `dev`, `staging`, `prod`)

### 4. Agent Core Monitoring (`agent-core-monitoring.yml`)

Monitors Agent Core performance and updates telemetry configuration.

**Manual trigger parameters**:
- `environment`: Environment name (e.g., `dev`, `staging`, `prod`)
- `update_langfuse`: Whether to update Langfuse credentials (default: `false`)
- `langfuse_public_key`: Langfuse public key (required if `update_langfuse` is `true`)
- `langfuse_secret_key`: Langfuse secret key (required if `update_langfuse` is `true`)

### 5. Lambda Update (`lambda-update.yml`)

Updates Lambda functions without redeploying the entire infrastructure.

**Manual trigger parameters**:
- `environment`: Environment name (e.g., `dev`, `staging`, `prod`)
- `function_name`: Name of the Lambda function to update (leave empty to update all functions)

## Running Workflows

To run a workflow manually:

1. Go to your GitHub repository
2. Navigate to **Actions**
3. Select the workflow you want to run
4. Click on **Run workflow**
5. Enter the required parameters
6. Click on **Run workflow**

## Workflow Dependencies

The workflows should be run in the following order:

1. AWS Resources Setup (`aws-setup.yml`) - only needed once
2. Terraform Deploy (`terraform-deploy.yml`)
3. API Tests (`api-test.yml`)

The Agent Core Monitoring and Lambda Update workflows can be run as needed after the infrastructure is deployed.

## Troubleshooting

If your workflows fail, check the following:

1. **OIDC Provider Configuration**: Ensure the OIDC provider is set up correctly in AWS
2. **IAM Role Permissions**: Ensure the role has the necessary permissions
3. **GitHub Secrets**: Ensure the secrets are set up correctly
4. **Workflow File Syntax**: Validate the workflow YAML syntax

Common errors:
- `AssumeRoleWithWebIdentity Error`: Check the trust policy configuration
- `Access Denied`: Check the IAM role permissions
- `Permission Denied`: Check the GitHub Actions permissions in the workflow file

## Best Practices

1. **Environment Variables**: Store sensitive information in GitHub Secrets
2. **Least Privilege**: Use the minimum required permissions for the IAM role
3. **Testing**: Always run tests after deployment
4. **Monitoring**: Set up monitoring and alerting for your infrastructure
5. **Documentation**: Keep this documentation up to date with any changes to the workflows