# GitHub Actions Workflow Execution Instructions

## Step 1: Set Up AWS Resources

1. Go to GitHub Actions > AWS Resources Setup > Run workflow
2. Enter the following information:
   - **Environment**: `dev`
   - **AWS Region**: `us-east-1`
   - **S3 bucket name for Terraform state**: `cloudable-tfstate-dev-YYYYMMDD` (replace YYYYMMDD with today's date)
   - **DynamoDB table name for state locking**: `cloudable-tf-locks-dev`
3. Click "Run workflow"

## Step 2: Deploy Infrastructure

After the AWS Resources Setup workflow completes successfully:

1. Go to GitHub Actions > Terraform Deploy > Run workflow
2. Select the environment: `dev`
3. Click "Run workflow"

## Step 3: Test API Endpoints

After the Terraform Deploy workflow completes successfully:

1. Go to GitHub Actions > API Tests > Run workflow
2. Select the environment: `dev`
3. Click "Run workflow"

## Step 4: Monitor Agent Core

After the infrastructure is deployed:

1. Go to GitHub Actions > Agent Core Monitoring > Run workflow
2. Select the environment: `dev`
3. Click "Run workflow"

## Step 5: Update Lambda Functions (as needed)

When you need to update Lambda functions:

1. Go to GitHub Actions > Update Lambda Functions > Run workflow
2. Select the environment: `dev`
3. Optionally specify a specific function to update (leave blank to update all functions)
4. Click "Run workflow"

## Troubleshooting

If any workflow fails, check the following:

1. **AWS Credentials**: Ensure the `AWS_ROLE_TO_ASSUME` secret is correctly set and has the necessary permissions.
2. **Terraform Backend**: If the backend configuration fails, check the S3 bucket and DynamoDB table created in Step 1.
3. **Resource Limits**: Check if you've hit any AWS service limits.
4. **CloudWatch Logs**: Check the CloudWatch Logs for detailed error messages.

## Important Notes

- **Costs**: The deployed resources will incur AWS charges. Remember to destroy resources when not needed.
- **Cleanup**: To destroy resources, run the Terraform Deploy workflow with the `-destroy` flag (add this option if needed).
- **Secrets**: Ensure all required GitHub Secrets are configured before running the workflows.
