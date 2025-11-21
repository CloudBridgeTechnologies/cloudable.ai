#!/bin/bash

# Set variables
TENANT="acme"
REGION="us-east-1"
SECURE_API_ID="pdoq719mx2"
CHAT_API_ID="2tol4asisa"

# API endpoints
SECURE_API_URL="https://${SECURE_API_ID}.execute-api.${REGION}.amazonaws.com/dev"
CHAT_API_URL="https://${CHAT_API_ID}.execute-api.${REGION}.amazonaws.com/dev"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting API Testing in ${REGION}${NC}"

# 1. Test the secure API (REST)
echo -e "\n${YELLOW}Testing Secure API (REST)...${NC}"
echo -e "${YELLOW}API URL:${NC} $SECURE_API_URL"

# List available resources for the REST API
echo -e "\n${YELLOW}Listing API resources...${NC}"
RESOURCES=$(aws apigateway get-resources --rest-api-id $SECURE_API_ID --region $REGION)
echo "$RESOURCES"

# 2. Test the chat API (HTTP)
echo -e "\n${YELLOW}Testing Chat API (HTTP)...${NC}"
echo -e "${YELLOW}API URL:${NC} $CHAT_API_URL"

# List routes for the HTTP API
echo -e "\n${YELLOW}Listing API routes...${NC}"
ROUTES=$(aws apigatewayv2 get-routes --api-id $CHAT_API_ID --region $REGION)
echo "$ROUTES"

# Create query payload for knowledge base search
echo -e "\n${YELLOW}Creating knowledge base query payload...${NC}"
cat << EOF > kb_query.json
{
  "tenant": "$TENANT",
  "query": "What are the key features of Cloudable.AI?",
  "max_results": 3
}
EOF
echo -e "${YELLOW}Query payload:${NC}"
cat kb_query.json

# Test secure API endpoint
echo -e "\n${YELLOW}Testing secure API endpoint...${NC}"
echo -e "${YELLOW}Using endpoint:${NC} $SECURE_API_URL/search"
SECURE_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d @kb_query.json \
  ${SECURE_API_URL}/search || echo "Request failed")
echo "$SECURE_RESPONSE"

# Test chat API endpoint
echo -e "\n${YELLOW}Testing chat API endpoint...${NC}"
echo -e "${YELLOW}Using endpoint:${NC} $CHAT_API_URL/chat"
CHAT_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d @kb_query.json \
  ${CHAT_API_URL}/chat || echo "Request failed")
echo "$CHAT_RESPONSE"

echo -e "\n${YELLOW}API Testing Complete${NC}"
