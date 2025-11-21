#!/bin/bash

# Script to package and deploy Lambda function with Langfuse integration

set -e

echo "Deploying Lambda function with Langfuse integration..."

# Check if we're in the correct directory
if [[ ! -f "lambda_function_simple.py" ]]; then
    echo "Error: Must be run from the infras/core directory"
    exit 1
fi

# Create a temporary directory for packaging
TEMP_DIR=$(mktemp -d)
echo "Created temporary directory: $TEMP_DIR"

# Copy Lambda function and dependencies
cp lambda_function_simple.py $TEMP_DIR/
cp langfuse_integration.py $TEMP_DIR/
cp tenant_rbac.py $TEMP_DIR/ 2>/dev/null || echo "Warning: tenant_rbac.py not found"
cp seed_rbac_roles.py $TEMP_DIR/ 2>/dev/null || echo "Warning: seed_rbac_roles.py not found"
cp tenant_metrics.py $TEMP_DIR/ 2>/dev/null || echo "Warning: tenant_metrics.py not found"
cp bedrock_utils.py $TEMP_DIR/ 2>/dev/null || echo "Warning: bedrock_utils.py not found" 
cp customer_status_handler.py $TEMP_DIR/ 2>/dev/null || echo "Warning: customer_status_handler.py not found"

# Install Langfuse in the package
echo "Installing Langfuse package..."
pip install langfuse -t $TEMP_DIR

# Create zip file
cd $TEMP_DIR
zip -r lambda_function_with_langfuse.zip ./*
cd -
cp $TEMP_DIR/lambda_function_with_langfuse.zip .

# Clean up temp directory
rm -rf $TEMP_DIR

echo "Package created: lambda_function_with_langfuse.zip"

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo "AWS CLI not found. Please install it to continue with deployment."
    exit 1
fi

# Get the Lambda function name from Terraform output
LAMBDA_FUNCTION_NAME=$(terraform output -raw kb_lambda_function_name 2>/dev/null || echo "kb-manager-dev-core")

echo "Updating Lambda function: $LAMBDA_FUNCTION_NAME"

# Update the Lambda function
aws lambda update-function-code \
    --function-name $LAMBDA_FUNCTION_NAME \
    --zip-file fileb://lambda_function_with_langfuse.zip \
    --region us-east-1

# Update Lambda environment variables to add Langfuse configuration
echo "Adding Langfuse configuration to Lambda environment variables..."
aws lambda update-function-configuration \
    --function-name $LAMBDA_FUNCTION_NAME \
    --environment Variables="{
        RDS_CLUSTER_ARN=$(terraform output -raw rds_cluster_arn 2>/dev/null || echo ''),
        RDS_SECRET_ARN=$(terraform output -raw rds_secret_arn 2>/dev/null || echo ''),
        RDS_DATABASE=$(terraform output -raw rds_database_name 2>/dev/null || echo 'cloudable'),
        LANGFUSE_PUBLIC_KEY=pk-lf-dfa751eb-07c4-4f93-8edf-222e93e95466,
        LANGFUSE_SECRET_KEY=sk-lf-35fe11d6-e8ad-4371-be13-b83a1dfec6bd,
        LANGFUSE_HOST=https://cloud.langfuse.com
    }" \
    --region us-east-1

echo "Deployment complete! Please update the Langfuse API keys in the Lambda environment variables."
echo "You can find the keys at https://cloud.langfuse.com/settings/api-keys"
echo ""
echo "To use your own API keys, run:"
echo "aws lambda update-function-configuration \\"
echo "    --function-name $LAMBDA_FUNCTION_NAME \\"
echo "    --environment Variables=\"{\\"
echo "        LANGFUSE_PUBLIC_KEY=pk_your_public_key,\\"
echo "        LANGFUSE_SECRET_KEY=sk_your_secret_key\\"
echo "    }\" \\"
echo "    --region us-east-1"
