#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Set AWS region
export AWS_DEFAULT_REGION=us-east-1

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI CUSTOMER STATUS SETUP             ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Get RDS cluster ARN
RDS_CLUSTER_ARN=$(terraform output -json | jq -r '.rds_cluster_arn.value')
if [ -z "$RDS_CLUSTER_ARN" ]; then
    echo -e "${RED}Failed to get RDS cluster ARN from Terraform output${NC}"
    exit 1
fi

# Get RDS secret ARN from the Lambda environment variables
RDS_SECRET_ARN=$(aws lambda get-function-configuration --function-name kb-manager-dev-core --query 'Environment.Variables.RDS_SECRET_ARN' --output text)
if [ -z "$RDS_SECRET_ARN" ]; then
    echo -e "${RED}Failed to get RDS secret ARN from Lambda environment variables${NC}"
    exit 1
fi

# Get RDS database name from the Lambda environment variables
RDS_DATABASE=$(aws lambda get-function-configuration --function-name kb-manager-dev-core --query 'Environment.Variables.RDS_DATABASE' --output text)
if [ -z "$RDS_DATABASE" ]; then
    echo -e "${RED}Failed to get RDS database name from Lambda environment variables${NC}"
    exit 1
fi

echo -e "${GREEN}Got RDS cluster ARN: ${RDS_CLUSTER_ARN}${NC}"
echo -e "${GREEN}Got RDS secret ARN: ${RDS_SECRET_ARN}${NC}"
echo -e "${GREEN}Got RDS database name: ${RDS_DATABASE}${NC}"

# Ensure setup scripts are available
if [ ! -f "setup_customer_status_tables.sql" ]; then
    echo -e "${RED}setup_customer_status_tables.sql not found${NC}"
    exit 1
fi

if [ ! -f "setup_customer_status.py" ]; then
    echo -e "${RED}setup_customer_status.py not found${NC}"
    exit 1
fi

# Make the Python script executable
chmod +x setup_customer_status.py

echo -e "\n${YELLOW}Setting up customer status tables for tenants...${NC}"

# Run the setup script
python3 setup_customer_status.py \
    --cluster-arn "$RDS_CLUSTER_ARN" \
    --secret-arn "$RDS_SECRET_ARN" \
    --database "$RDS_DATABASE" \
    --tenants "acme,globex" \
    --sql-file "setup_customer_status_tables.sql"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to set up customer status tables${NC}"
    exit 1
fi

echo -e "\n${GREEN}Customer status setup complete!${NC}"
echo -e "${BLUE}==================================================${NC}"

exit 0
