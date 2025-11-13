# Cloudable.AI Updated Deployment Guide

This guide provides instructions for deploying the Cloudable.AI platform using the updated deployment scripts.

## Deployment Options

The deployment script now supports multiple options for handling different scenarios:

```bash
./deploy_terraform.sh [--import] [--destroy] [--auto-approve] [--env ENV] [--region REGION]
```

### Options:

- `--import`: Run in import mode to import existing resources into Terraform state
- `--destroy`: Run in destroy mode to destroy all Terraform-managed resources
- `--auto-approve`: Skip confirmation prompts
- `--env`: Specify the environment (default: dev)
- `--region`: Specify the AWS region (default: us-east-1)

## Handling Existing Resources

If you encounter errors about existing resources during deployment, you have two options:

### Option 1: Import Existing Resources

If you want to keep the existing resources and import them into Terraform state:

```bash
./deploy_terraform.sh --import --env dev
```

This will:
1. Initialize Terraform
2. Run the import script to import existing resources
3. Add the resources to Terraform state

### Option 2: Delete Existing Resources

If you want to delete the existing resources and create new ones:

```bash
./destroy_existing_resources.sh dev us-east-1
```

This will:
1. Identify existing resources that conflict with deployment
2. Delete them from AWS
3. Allow you to run the deployment script again

## Deployment Steps

### Step 1: Set Up AWS Profile

```bash
# Configure AWS CLI
aws configure

# OR use a specific profile
aws configure --profile cloudable
export AWS_PROFILE=cloudable
```

### Step 2: Handle Existing Resources

First, check if there are existing resources:

```bash
./deploy_terraform.sh --env dev
```

If you encounter errors about existing resources, choose one of these approaches:

```bash
# Option 1: Import existing resources
./deploy_terraform.sh --import --env dev

# Option 2: Delete existing resources
./destroy_existing_resources.sh dev us-east-1
```

### Step 3: Deploy Infrastructure

After handling existing resources, deploy the infrastructure:

```bash
./deploy_terraform.sh --env dev
```

### Step 4: Test API Endpoints

Once deployment is complete, test the API endpoints:

```bash
./test_api_endpoints.sh
```

### Step 5: Clean Up (Optional)

When you no longer need the infrastructure:

```bash
./deploy_terraform.sh --destroy --env dev
```

## Troubleshooting

### Common Issues

1. **Resource Already Exists Errors**:
   - Use the import script: `./deploy_terraform.sh --import --env dev`
   - Or delete existing resources: `./destroy_existing_resources.sh dev us-east-1`

2. **Permission Issues**:
   - Ensure your AWS credentials have the necessary permissions
   - Check IAM policies for the required services

3. **Deployment Timeouts**:
   - Some resources like OpenSearch collections can take a long time to create
   - Lambda function creation may timeout if the package is large

4. **State File Issues**:
   - If the state file becomes corrupted, you can reinitialize with `terraform init -reconfigure`
   - For remote state issues, check S3 bucket and DynamoDB table permissions

This guide provides instructions for deploying the Cloudable.AI platform using the updated deployment scripts.

## Deployment Options

The deployment script now supports multiple options for handling different scenarios:

```bash
./deploy_terraform.sh [--import] [--destroy] [--auto-approve] [--env ENV] [--region REGION]
```

### Options:

- `--import`: Run in import mode to import existing resources into Terraform state
- `--destroy`: Run in destroy mode to destroy all Terraform-managed resources
- `--auto-approve`: Skip confirmation prompts
- `--env`: Specify the environment (default: dev)
- `--region`: Specify the AWS region (default: us-east-1)

## Handling Existing Resources

If you encounter errors about existing resources during deployment, you have two options:

### Option 1: Import Existing Resources

If you want to keep the existing resources and import them into Terraform state:

```bash
./deploy_terraform.sh --import --env dev
```

This will:
1. Initialize Terraform
2. Run the import script to import existing resources
3. Add the resources to Terraform state

### Option 2: Delete Existing Resources

If you want to delete the existing resources and create new ones:

```bash
./destroy_existing_resources.sh dev us-east-1
```

This will:
1. Identify existing resources that conflict with deployment
2. Delete them from AWS
3. Allow you to run the deployment script again

## Deployment Steps

### Step 1: Set Up AWS Profile

```bash
# Configure AWS CLI
aws configure

# OR use a specific profile
aws configure --profile cloudable
export AWS_PROFILE=cloudable
```

### Step 2: Handle Existing Resources

First, check if there are existing resources:

```bash
./deploy_terraform.sh --env dev
```

If you encounter errors about existing resources, choose one of these approaches:

```bash
# Option 1: Import existing resources
./deploy_terraform.sh --import --env dev

# Option 2: Delete existing resources
./destroy_existing_resources.sh dev us-east-1
```

### Step 3: Deploy Infrastructure

After handling existing resources, deploy the infrastructure:

```bash
./deploy_terraform.sh --env dev
```

### Step 4: Test API Endpoints

Once deployment is complete, test the API endpoints:

```bash
./test_api_endpoints.sh
```

### Step 5: Clean Up (Optional)

When you no longer need the infrastructure:

```bash
./deploy_terraform.sh --destroy --env dev
```

## Troubleshooting

### Common Issues

1. **Resource Already Exists Errors**:
   - Use the import script: `./deploy_terraform.sh --import --env dev`
   - Or delete existing resources: `./destroy_existing_resources.sh dev us-east-1`

2. **Permission Issues**:
   - Ensure your AWS credentials have the necessary permissions
   - Check IAM policies for the required services

3. **Deployment Timeouts**:
   - Some resources like OpenSearch collections can take a long time to create
   - Lambda function creation may timeout if the package is large

4. **State File Issues**:
   - If the state file becomes corrupted, you can reinitialize with `terraform init -reconfigure`
   - For remote state issues, check S3 bucket and DynamoDB table permissions
