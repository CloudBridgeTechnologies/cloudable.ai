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
echo -e "${BLUE}   CLOUDABLE.AI CUSTOMER STATUS DEPLOYMENT        ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Create temp directory for packaging
TEMP_DIR=$(mktemp -d)
echo -e "${YELLOW}Created temporary directory: ${TEMP_DIR}${NC}"

# Copy all necessary files to the temp directory
echo -e "${YELLOW}Copying Lambda function files...${NC}"
cp lambda_function_simple.py "$TEMP_DIR/"
cp customer_status_handler.py "$TEMP_DIR/"
cp bedrock_utils.py "$TEMP_DIR/"
cp tenant_rbac.py "$TEMP_DIR/"
cp tenant_metrics.py "$TEMP_DIR/"
cp seed_rbac_roles.py "$TEMP_DIR/"

# Change to temp directory and create zip package
cd "$TEMP_DIR" || exit 1
echo -e "${YELLOW}Creating Lambda deployment package...${NC}"
zip -r lambda_package.zip ./*.py

# Deploy the Lambda function
echo -e "${YELLOW}Deploying Lambda function...${NC}"
cd - || exit 1

# Copy the zip file to the current directory
cp "$TEMP_DIR/lambda_package.zip" ./lambda_function_simple.zip

# Apply Terraform changes to update the Lambda function
terraform apply -auto-approve

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to apply Terraform changes${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Set up customer status tables in the database
echo -e "\n${YELLOW}Setting up customer status tables...${NC}"
./setup_customer_status.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to set up customer status tables${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Clean up
echo -e "${YELLOW}Cleaning up temporary files...${NC}"
rm -rf "$TEMP_DIR"

echo -e "\n${GREEN}Customer status deployment complete!${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}API endpoint: $(terraform output -raw api_endpoint)${NC}"
echo -e "${BLUE}==================================================${NC}"

exit 0
