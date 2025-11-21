#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI TERRAFORM DEPLOYMENT              ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Simply run Terraform commands
echo -e "\n${YELLOW}Initializing Terraform...${NC}"
terraform init

echo -e "\n${YELLOW}Planning Terraform changes...${NC}"
terraform plan -out=tfplan

echo -e "\n${YELLOW}Applying Terraform changes...${NC}"
terraform apply tfplan

echo -e "\n${YELLOW}Displaying outputs...${NC}"
terraform output

echo -e "\n${GREEN}Terraform deployment complete!${NC}"
