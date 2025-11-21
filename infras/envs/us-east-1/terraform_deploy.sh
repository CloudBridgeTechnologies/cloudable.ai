#!/bin/bash
# Deploy Lambda function update using Terraform

set -e

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE} TERRAFORM LAMBDA PGVECTOR UPDATE DEPLOYMENT ${NC}"
echo -e "${BLUE}==============================================${NC}"

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
  echo -e "${RED}Terraform is not installed. Please install it before running this script.${NC}"
  echo -e "Visit: https://developer.hashicorp.com/terraform/install"
  exit 1
fi

# Load AWS environment variables if available
if [ -f "../../set_aws_env.sh" ]; then
  echo -e "\n${YELLOW}Loading AWS environment variables...${NC}"
  source ../../set_aws_env.sh
fi

# Check AWS credentials
echo -e "\n${YELLOW}Verifying AWS credentials...${NC}"
AWS_IDENTITY=$(aws sts get-caller-identity 2>/dev/null)
if [ $? -ne 0 ]; then
  echo -e "${RED}AWS authentication failed. Please check your credentials.${NC}"
  exit 1
fi
echo -e "${GREEN}AWS credentials verified successfully!${NC}"

# Initialize Terraform
echo -e "\n${YELLOW}Initializing Terraform...${NC}"
terraform init
if [ $? -ne 0 ]; then
  echo -e "${RED}Terraform initialization failed.${NC}"
  exit 1
fi

# Validate Terraform configuration
echo -e "\n${YELLOW}Validating Terraform configuration...${NC}"
terraform validate
if [ $? -ne 0 ]; then
  echo -e "${RED}Terraform validation failed. Please fix the errors before continuing.${NC}"
  exit 1
fi

# Show Terraform plan
echo -e "\n${YELLOW}Generating Terraform plan...${NC}"
terraform plan -out=lambda_update.tfplan
if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to generate Terraform plan.${NC}"
  exit 1
fi

# Confirm before applying
echo -e "\n${YELLOW}Ready to apply the Terraform plan.${NC}"
read -p "Do you want to proceed with the deployment? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo -e "${BLUE}Deployment cancelled.${NC}"
  exit 0
fi

# Apply Terraform plan
echo -e "\n${YELLOW}Applying Terraform plan...${NC}"
terraform apply lambda_update.tfplan
if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to apply Terraform plan.${NC}"
  exit 1
fi

echo -e "\n${GREEN}==============================================${NC}"
echo -e "${GREEN} TERRAFORM DEPLOYMENT COMPLETED SUCCESSFULLY ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "\nYou can now test the Lambda functions with the end-to-end test script:"
echo -e "${BLUE}  ./e2e_rds_pgvector_test.sh${NC}"

# Clean up plan file
rm -f lambda_update.tfplan
