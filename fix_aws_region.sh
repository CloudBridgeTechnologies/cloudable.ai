#!/bin/bash

# Script to fix AWS region configuration and set environment variables consistently

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================="
echo "  FIXING AWS REGION CONFIGURATION"
echo -e "==========================================================${NC}"

# Current region
current_region=$(aws configure get region)
echo -e "Current configured region: ${YELLOW}${current_region}${NC}"

# Set the correct region to us-east-1
echo -e "\n${YELLOW}Setting AWS region to us-east-1 for this session...${NC}"
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1

echo -e "${GREEN}AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}${NC}"
echo -e "${GREEN}AWS_REGION=${AWS_REGION}${NC}"

# Check the RDS cluster
echo -e "\n${YELLOW}Checking RDS clusters in us-east-1...${NC}"
rds_clusters=$(aws rds describe-db-clusters --query "DBClusters[*].DBClusterIdentifier" --output text)

if [ -z "$rds_clusters" ]; then
    echo -e "${RED}No RDS clusters found in us-east-1${NC}"
    exit 1
else
    echo -e "${GREEN}Found RDS clusters: ${rds_clusters}${NC}"
fi

# Get the RDS cluster ARN
echo -e "\n${YELLOW}Getting RDS cluster ARN...${NC}"
RDS_CLUSTER_ARN=$(aws rds describe-db-clusters --db-cluster-identifier aurora-dev-core-v2 --query "DBClusters[0].DBClusterArn" --output text)

if [ -z "$RDS_CLUSTER_ARN" ] || [ "$RDS_CLUSTER_ARN" == "None" ]; then
    echo -e "${RED}Failed to get RDS cluster ARN${NC}"
    exit 1
else
    echo -e "${GREEN}RDS cluster ARN: ${RDS_CLUSTER_ARN}${NC}"
fi

# Get the Lambda function to update
echo -e "\n${YELLOW}Getting Lambda function details...${NC}"
LAMBDA_FUNCTION_NAME="kb-manager-dev-core"

function_info=$(aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "${RED}Lambda function ${LAMBDA_FUNCTION_NAME} not found${NC}"
    exit 1
fi

echo -e "${GREEN}Found Lambda function: ${LAMBDA_FUNCTION_NAME}${NC}"

# Get the RDS secret ARN
echo -e "\n${YELLOW}Getting RDS secret ARN...${NC}"
RDS_SECRET_ARN=$(aws secretsmanager list-secrets --query "SecretList[?contains(Name, 'aurora-dev-admin')].ARN" --output text)

if [ -z "$RDS_SECRET_ARN" ] || [ "$RDS_SECRET_ARN" == "None" ]; then
    echo -e "${RED}Failed to get RDS secret ARN${NC}"
    exit 1
else
    echo -e "${GREEN}RDS secret ARN: ${RDS_SECRET_ARN}${NC}"
fi

# Get the RDS database name
echo -e "\n${YELLOW}Getting RDS database name...${NC}"
RDS_DATABASE=$(aws lambda get-function-configuration --function-name $LAMBDA_FUNCTION_NAME --query "Environment.Variables.RDS_DATABASE" --output text)

if [ -z "$RDS_DATABASE" ] || [ "$RDS_DATABASE" == "None" ]; then
    echo -e "${YELLOW}RDS database name not found in Lambda environment, using default 'cloudable'${NC}"
    RDS_DATABASE="cloudable"
else
    echo -e "${GREEN}RDS database name: ${RDS_DATABASE}${NC}"
fi

# Update Lambda environment variables
echo -e "\n${YELLOW}Updating Lambda environment variables...${NC}"
aws lambda update-function-configuration \
    --function-name $LAMBDA_FUNCTION_NAME \
    --environment "Variables={
        LANGFUSE_HOST=https://cloud.langfuse.com,
        RDS_DATABASE=$RDS_DATABASE,
        RDS_SECRET_ARN=$RDS_SECRET_ARN,
        LANGFUSE_PUBLIC_KEY=pk-lf-dfa751eb-07c4-4f93-8edf-222e93e95466,
        LANGFUSE_SECRET_KEY=sk-lf-35fe11d6-e8ad-4371-be13-b83a1dfec6bd,
        RDS_CLUSTER_ARN=$RDS_CLUSTER_ARN,
        CUSTOMER_STATUS_ENABLED=true
    }"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to update Lambda environment variables${NC}"
    exit 1
else
    echo -e "${GREEN}Lambda environment variables updated successfully${NC}"
fi

echo -e "\n${BLUE}=========================================================="
echo "  REGION CONFIGURATION FIXED"
echo -e "==========================================================${NC}"
echo -e "\nTo use these settings in your current shell, run:\n"
echo -e "${YELLOW}export AWS_DEFAULT_REGION=us-east-1${NC}"
echo -e "${YELLOW}export AWS_REGION=us-east-1${NC}"

echo -e "\nNext steps:"
echo -e "1. Create the customer_status schema"
echo -e "2. Create the customer status tables"
echo -e "3. Test the customer status API"
echo -e "4. Verify Langfuse integration"
