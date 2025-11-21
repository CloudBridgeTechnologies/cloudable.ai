#!/bin/bash

# Set variables
TENANT="acme"
SECURE_API_ID="pdoq719mx2"
CHAT_API_ID="2toI4asIsa"
REGION="us-east-1"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting API Testing${NC}"

# 1. Test the secure API (REST)
echo -e "\n${YELLOW}Testing Secure API (REST)...${NC}"
echo -e "${YELLOW}API ID:${NC} $SECURE_API_ID"

# List available resources for the REST API
echo -e "\n${YELLOW}Listing API resources...${NC}"
RESOURCES=$(aws apigateway get-resources --rest-api-id $SECURE_API_ID)
echo "$RESOURCES"

# List available API keys
echo -e "\n${YELLOW}Listing API keys...${NC}"
API_KEYS=$(aws apigateway get-api-keys --include-values)
echo "$API_KEYS"

# 2. Test the chat API (HTTP)
echo -e "\n${YELLOW}Testing Chat API (HTTP)...${NC}"
echo -e "${YELLOW}API ID:${NC} $CHAT_API_ID"

# List routes for the HTTP API
echo -e "\n${YELLOW}Listing API routes...${NC}"
ROUTES=$(aws apigatewayv2 get-routes --api-id $CHAT_API_ID)
echo "$ROUTES"

# Simple query test - adjust payload based on actual API structure
echo -e "\n${YELLOW}Testing knowledge base query...${NC}"

# Construct simple query payload
cat << EOF > query_payload.json
{
  "tenant": "$TENANT",
  "query": "What are the key features of Cloudable.AI?",
  "max_results": 3
}
EOF

# Display the query payload
echo -e "${YELLOW}Query payload:${NC}"
cat query_payload.json

echo -e "\n${YELLOW}API Testing Complete${NC}"
