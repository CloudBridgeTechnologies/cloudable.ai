#!/bin/bash

# Script to deploy the fixed Langfuse integration

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================="
echo "  DEPLOYING FIXED LANGFUSE INTEGRATION"
echo -e "==========================================================${NC}"

# Set AWS region for this session
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1

# Create a Lambda deployment package with the fixed Langfuse integration
echo -e "\n${YELLOW}Creating Lambda deployment package...${NC}"

mkdir -p langfuse_fix_deployment
cd langfuse_fix_deployment

# Copy the fixed Langfuse module
cp ../infras/lambda/langfuse_fix.py ./langfuse_integration.py

# Install required packages
echo -e "\n${YELLOW}Installing required Python packages...${NC}"
pip install requests -t .

# Create the deployment package
echo -e "\n${YELLOW}Creating ZIP package...${NC}"
zip -r langfuse_fix.zip .

# Move back to project root
cd ..

# Update the Lambda function
echo -e "\n${YELLOW}Updating Lambda function...${NC}"
aws lambda update-function-configuration \
    --function-name kb-manager-dev-core \
    --handler langfuse_integration.handler \
    --timeout 30 \
    --memory-size 256 \
    --environment "Variables={LANGFUSE_HOST=https://cloud.langfuse.com,LANGFUSE_PROJECT_ID=cmhz8tqhk00duad07xptpuo06,LANGFUSE_ORG_ID=cmhz8tcqz00dpad07ee341p57,LANGFUSE_PUBLIC_KEY=pk-lf-dfa751eb-07c4-4f93-8edf-222e93e95466,LANGFUSE_SECRET_KEY=sk-lf-35fe11d6-e8ad-4371-be13-b83a1dfec6bd,CUSTOMER_STATUS_ENABLED=true,RDS_CLUSTER_ARN=arn:aws:rds:us-east-1:951296734820:cluster:aurora-dev-core-v2,RDS_SECRET_ARN=arn:aws:secretsmanager:us-east-1:951296734820:secret:aurora-dev-admin-secret-3Sszqw,RDS_DATABASE=cloudable}" \
    --region us-east-1

# Update the Lambda function code
echo -e "\n${YELLOW}Updating Lambda function code...${NC}"
aws lambda update-function-code \
    --function-name kb-manager-dev-core \
    --zip-file fileb://langfuse_fix_deployment/langfuse_fix.zip \
    --region us-east-1

# Clean up
rm -rf langfuse_fix_deployment

echo -e "\n${GREEN}Lambda function updated successfully with fixed Langfuse integration${NC}"

# Create a test event
echo -e "\n${YELLOW}Creating test event...${NC}"
TEST_EVENT='{
  "tenant": "acme",
  "query": "What is the status of our implementation?"
}'

# Invoke the Lambda function with the test event
echo -e "\n${YELLOW}Invoking Lambda function with test event...${NC}"
aws lambda invoke \
    --function-name kb-manager-dev-core \
    --payload "$TEST_EVENT" \
    --cli-binary-format raw-in-base64-out \
    output.json \
    --region us-east-1

# Show the output
echo -e "\n${YELLOW}Lambda function output:${NC}"
cat output.json
rm output.json

echo -e "\n${BLUE}=========================================================="
echo "  LANGFUSE INTEGRATION DEPLOYMENT COMPLETED"
echo -e "==========================================================${NC}"

echo -e "\nTo verify Langfuse integration:"
echo -e "1. Visit: ${GREEN}https://cloud.langfuse.com${NC}"
echo -e "2. Log in with your Langfuse account"
echo -e "3. Check for traces from the 'acme' tenant"
