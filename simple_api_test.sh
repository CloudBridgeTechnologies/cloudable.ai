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

echo -e "${YELLOW}Starting Simple API Testing${NC}"

# Construct the API URLs
SECURE_API_URL="https://$SECURE_API_ID.execute-api.$REGION.amazonaws.com/dev"
CHAT_API_URL="https://$CHAT_API_ID.execute-api.$REGION.amazonaws.com/dev"

echo -e "\n${YELLOW}Testing Secure API (REST)${NC}"
echo -e "${YELLOW}URL:${NC} $SECURE_API_URL"

# Try basic HTTP GET request to secure API
echo -e "\n${YELLOW}Testing GET request...${NC}"
curl -s -o /dev/null -w "%{http_code}" $SECURE_API_URL

echo -e "\n\n${YELLOW}Testing Chat API (HTTP)${NC}"
echo -e "${YELLOW}URL:${NC} $CHAT_API_URL"

# Try basic HTTP GET request to chat API
echo -e "\n${YELLOW}Testing GET request...${NC}"
curl -s -o /dev/null -w "%{http_code}" $CHAT_API_URL

echo -e "\n\n${YELLOW}Simple API Testing Complete${NC}"
