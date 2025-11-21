#!/bin/bash

# Script to add a route for the customer status API

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================="
echo "  ADDING CUSTOMER STATUS API ROUTE"
echo -e "==========================================================${NC}"

# Set AWS region for this session
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1

# API ID
API_ID="xn66ohjpw1"

# Get the integration ID
echo -e "\n${YELLOW}Getting existing integration ID...${NC}"
INTEGRATION_ID=$(aws apigatewayv2 get-routes --api-id $API_ID --query "Items[0].Target" --output text | cut -d'/' -f2)

if [ -z "$INTEGRATION_ID" ] || [ "$INTEGRATION_ID" == "None" ]; then
    echo -e "${RED}Failed to get integration ID${NC}"
    exit 1
fi

echo -e "Integration ID: ${GREEN}$INTEGRATION_ID${NC}"

# Add the customer status route
echo -e "\n${YELLOW}Adding customer status route...${NC}"
aws apigatewayv2 create-route \
    --api-id $API_ID \
    --route-key "POST /api/customer-status" \
    --target "integrations/$INTEGRATION_ID"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to add customer status route${NC}"
    exit 1
else
    echo -e "${GREEN}Customer status route added successfully${NC}"
fi

# Deploy the API to apply changes
echo -e "\n${YELLOW}Deploying API changes...${NC}"
aws apigatewayv2 create-deployment \
    --api-id $API_ID \
    --stage-name dev

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to deploy API changes${NC}"
    exit 1
else
    echo -e "${GREEN}API changes deployed successfully${NC}"
fi

echo -e "\n${BLUE}=========================================================="
echo "  CUSTOMER STATUS ROUTE ADDED"
echo -e "==========================================================${NC}"
