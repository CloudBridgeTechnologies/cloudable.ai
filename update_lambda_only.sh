#!/bin/bash

# Script to update only the Lambda function with Langfuse integration

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================="
echo "  UPDATING LAMBDA FUNCTION FOR LANGFUSE INTEGRATION"
echo -e "==========================================================${NC}"

# Set AWS region for this session
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1

# Check if Lambda package exists
PACKAGE_PATH="/Users/adrian/Projects/Cloudable.AI/infras/lambda/lambda_deployment_package.zip"
if [ ! -f $PACKAGE_PATH ]; then
    echo -e "${RED}Lambda deployment package not found. Please build it first.${NC}"
    exit 1
fi

# Get the Lambda function
echo -e "\n${YELLOW}Getting Lambda function details...${NC}"
LAMBDA_FUNCTION_NAME="kb-manager-dev-core"

function_info=$(aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "${RED}Lambda function ${LAMBDA_FUNCTION_NAME} not found${NC}"
    exit 1
fi

echo -e "${GREEN}Found Lambda function: ${LAMBDA_FUNCTION_NAME}${NC}"

# Update Lambda function code
echo -e "\n${YELLOW}Updating Lambda function code...${NC}"
aws lambda update-function-code \
    --function-name $LAMBDA_FUNCTION_NAME \
    --zip-file fileb://$PACKAGE_PATH

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to update Lambda function code${NC}"
    exit 1
else
    echo -e "${GREEN}Lambda function code updated successfully${NC}"
fi

# Update Lambda environment variables
echo -e "\n${YELLOW}Updating Lambda environment variables...${NC}"
aws lambda update-function-configuration \
    --function-name $LAMBDA_FUNCTION_NAME \
    --environment "Variables={LANGFUSE_HOST=https://eu.cloud.langfuse.com,LANGFUSE_PROJECT_ID=cmhz8tqhk00duad07xptpuo06,LANGFUSE_ORG_ID=cmhz8tcqz00dpad07ee341p57,LANGFUSE_PUBLIC_KEY=pk-lf-dfa751eb-07c4-4f93-8edf-222e93e95466,LANGFUSE_SECRET_KEY=sk-lf-35fe11d6-e8ad-4371-be13-b83a1dfec6bd,CUSTOMER_STATUS_ENABLED=true}"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to update Lambda environment variables${NC}"
    exit 1
else
    echo -e "${GREEN}Lambda environment variables updated successfully${NC}"
fi

# Get the API Gateway URL
echo -e "\n${YELLOW}Getting API Gateway URL...${NC}"
API_GATEWAY_ID=$(aws apigatewayv2 get-apis --query "Items[?Name=='cloudable-kb-api-core'].ApiId" --output text)

if [ -z "$API_GATEWAY_ID" ] || [ "$API_GATEWAY_ID" == "None" ]; then
    echo -e "${RED}API Gateway not found${NC}"
    exit 1
fi

API_URL="https://${API_GATEWAY_ID}.execute-api.${AWS_REGION}.amazonaws.com/dev"
echo -e "API Gateway URL: ${GREEN}$API_URL${NC}"

echo -e "\n${BLUE}=========================================================="
echo "  LAMBDA FUNCTION UPDATED SUCCESSFULLY"
echo -e "==========================================================${NC}"

# Output test instructions
echo -e "\n${BLUE}To test the API, run:${NC}"
echo -e "curl -X POST \"${API_URL}/api/kb/query\" -H \"Content-Type: application/json\" -H \"x-tenant-id: acme\" -H \"x-user-id: test-user\" -d '{\"tenant\": \"acme\", \"query\": \"What is our status?\"}'"
echo -e "curl -X POST \"${API_URL}/api/customer-status\" -H \"Content-Type: application/json\" -H \"x-tenant-id: acme\" -H \"x-user-id: test-user\" -d '{\"tenant\": \"acme\"}'"

echo -e "\n${BLUE}To check Langfuse traces, visit:${NC}"
echo -e "https://eu.cloud.langfuse.com"
