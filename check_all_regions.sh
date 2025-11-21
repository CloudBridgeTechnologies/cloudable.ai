#!/bin/bash

# Script to check Lambda functions and API Gateways in multiple regions

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================="
echo "  CHECKING AWS RESOURCES ACROSS REGIONS"
echo -e "==========================================================${NC}"

# Array of regions to check
regions=("us-east-1" "eu-west-1")

# Check Lambda functions
echo -e "\n${YELLOW}Checking Lambda functions across regions...${NC}"

for region in "${regions[@]}"
do
    echo -e "\n${BLUE}Region: $region${NC}"
    echo -e "${YELLOW}Lambda functions:${NC}"
    aws lambda list-functions --region $region --query "Functions[].FunctionName" --output table
done

# Check API Gateways (REST APIs)
echo -e "\n${YELLOW}Checking REST API Gateways across regions...${NC}"

for region in "${regions[@]}"
do
    echo -e "\n${BLUE}Region: $region${NC}"
    echo -e "${YELLOW}REST API Gateways:${NC}"
    aws apigateway get-rest-apis --region $region --query "items[].{Name:name,ID:id,URL:endpoint}" --output table
done

# Check API Gateways (HTTP APIs)
echo -e "\n${YELLOW}Checking HTTP API Gateways across regions...${NC}"

for region in "${regions[@]}"
do
    echo -e "\n${BLUE}Region: $region${NC}"
    echo -e "${YELLOW}HTTP API Gateways:${NC}"
    aws apigatewayv2 get-apis --region $region --query "Items[].{Name:Name,ID:ApiId,URL:ApiEndpoint}" --output table
done

echo -e "\n${BLUE}=========================================================="
echo "  CHECKING COMPLETED"
echo -e "==========================================================${NC}"
