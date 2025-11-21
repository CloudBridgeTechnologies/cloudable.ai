#!/bin/bash

# Script to deploy Terraform infrastructure

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================="
echo "  DEPLOYING CLOUDABLE.AI INFRASTRUCTURE"
echo -e "==========================================================${NC}"

# Set AWS region for this session
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1

# Check if Lambda package exists
if [ ! -f ../lambda/lambda_deployment_package.zip ]; then
    echo -e "${RED}Lambda deployment package not found. Please build it first.${NC}"
    exit 1
fi

# Initialize Terraform
echo -e "\n${YELLOW}Initializing Terraform...${NC}"
terraform init -reconfigure

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform initialization failed${NC}"
    exit 1
else
    echo -e "${GREEN}Terraform initialized successfully${NC}"
fi

# Check Terraform plan
echo -e "\n${YELLOW}Generating Terraform plan...${NC}"
terraform plan -out=tfplan

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform plan failed${NC}"
    exit 1
else
    echo -e "${GREEN}Terraform plan generated successfully${NC}"
fi

# Apply Terraform plan
echo -e "\n${YELLOW}Applying Terraform plan...${NC}"
terraform apply "tfplan"

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform apply failed${NC}"
    exit 1
else
    echo -e "${GREEN}Terraform apply completed successfully${NC}"
fi

# Get outputs
echo -e "\n${YELLOW}Getting deployment outputs...${NC}"
API_GATEWAY_URL=$(terraform output -raw api_gateway_url)
LAMBDA_FUNCTION_NAME=$(terraform output -raw lambda_function_name)
RDS_CLUSTER_ARN=$(terraform output -raw rds_cluster_arn)
RDS_SECRET_ARN=$(terraform output -raw rds_secret_arn)

echo -e "\n${GREEN}Deployment completed successfully!${NC}"
echo -e "API Gateway URL: ${YELLOW}${API_GATEWAY_URL}${NC}"
echo -e "Lambda Function: ${YELLOW}${LAMBDA_FUNCTION_NAME}${NC}"
echo -e "RDS Cluster ARN: ${YELLOW}${RDS_CLUSTER_ARN}${NC}"

echo -e "\n${BLUE}=========================================================="
echo "  INFRASTRUCTURE DEPLOYMENT COMPLETED"
echo -e "==========================================================${NC}"

# Output test instructions
echo -e "\n${BLUE}To test the API, run:${NC}"
echo -e "curl -X POST \"${API_GATEWAY_URL}/api/kb/query\" -H \"Content-Type: application/json\" -H \"x-tenant-id: acme\" -d '{\"tenant\": \"acme\", \"query\": \"What is our status?\"}'"
echo -e "curl -X POST \"${API_GATEWAY_URL}/api/customer-status\" -H \"Content-Type: application/json\" -H \"x-tenant-id: acme\" -d '{\"tenant\": \"acme\"}'"

echo -e "\n${BLUE}To check Langfuse traces, visit:${NC}"
echo -e "https://eu.cloud.langfuse.com"
