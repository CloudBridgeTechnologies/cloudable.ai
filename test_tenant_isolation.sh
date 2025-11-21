#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Set AWS region explicitly
export AWS_DEFAULT_REGION=eu-west-1
export AWS_REGION=eu-west-1

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI TENANT ISOLATION TEST            ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Get API Gateway endpoint from Terraform or use default
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/infras/core" 2>/dev/null
API_ENDPOINT=$(terraform output -raw api_endpoint 2>/dev/null || echo "")
cd "$SCRIPT_DIR"

if [ -z "$API_ENDPOINT" ]; then
    # Fallback to known endpoint
    API_ENDPOINT="https://uk9o6co5pd.execute-api.eu-west-1.amazonaws.com/dev"
fi

# Test scenarios
echo -e "\n${YELLOW}TEST 1: Valid Tenant Access${NC}"
echo -e "Tenant: acme (valid tenant)"

VALID_QUERY=$(curl -s -X POST \
  "${API_ENDPOINT}/api/kb/query" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: user-reader-001" \
  -d '{"tenant":"acme","query":"What is the current implementation status?","max_results":3}')

echo -e "Response: ${VALID_QUERY}"

if [[ "$VALID_QUERY" == *"Implementation"* ]]; then
  echo -e "${GREEN}✓ Success: Valid tenant received appropriate response${NC}"
else
  echo -e "${RED}✗ Failure: Valid tenant did not receive expected response${NC}"
fi

echo -e "\n${YELLOW}TEST 2: Invalid Tenant Access${NC}"
echo -e "Tenant: invalid_tenant (not in allowed list)"

INVALID_QUERY=$(curl -s -X POST \
  "${API_ENDPOINT}/api/kb/query" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: user-reader-001" \
  -d '{"tenant":"invalid_tenant","query":"What is the current implementation status?","max_results":3}')

echo -e "Response: ${INVALID_QUERY}"

if [[ "$INVALID_QUERY" == *"Unauthorized"* || "$INVALID_QUERY" == *"403"* ]]; then
  echo -e "${GREEN}✓ Success: Invalid tenant was properly rejected${NC}"
else
  echo -e "${RED}✗ Failure: Invalid tenant was not rejected as expected${NC}"
fi

echo -e "\n${YELLOW}TEST 3: Cross-Tenant Access Attempt${NC}"
echo -e "Tenant: acme trying to access globex's document"

CROSS_TENANT=$(curl -s -X POST \
  "${API_ENDPOINT}/api/kb/sync" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: user-admin-001" \
  -d '{"tenant":"acme","document_key":"documents/globex/confidential_document.md"}')

echo -e "Response: ${CROSS_TENANT}"

if [[ "$CROSS_TENANT" == *"does not belong to this tenant"* || "$CROSS_TENANT" == *"403"* ]]; then
  echo -e "${GREEN}✓ Success: Cross-tenant access was properly rejected${NC}"
else
  echo -e "${RED}✗ Failure: Cross-tenant access was not rejected as expected${NC}"
fi

echo -e "\n${YELLOW}TEST 4: Tenant Header-Based Access${NC}"
echo -e "Using x-tenant-id header instead of body parameter"

HEADER_TENANT=$(curl -s -X POST \
  "${API_ENDPOINT}/api/kb/query" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: user-reader-001" \
  -H "x-tenant-id: globex" \
  -d '{"tenant":"globex","query":"What is the current implementation status?","max_results":3}')

echo -e "Response: ${HEADER_TENANT}"

# Note: The current implementation might not support header-based tenant identification
# This test is to demonstrate how it would work in a production environment

echo -e "\n${YELLOW}TEST 5: Chat API Tenant Isolation${NC}"
echo -e "Testing that chat API properly isolates tenant data"

ACME_CHAT=$(curl -s -X POST \
  "${API_ENDPOINT}/api/chat" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: user-reader-001" \
  -d '{"tenant":"acme","message":"Tell me about our implementation status","use_kb":true}')

GLOBEX_CHAT=$(curl -s -X POST \
  "${API_ENDPOINT}/api/chat" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: user-reader-001" \
  -d '{"tenant":"globex","message":"Tell me about our implementation status","use_kb":true}')

echo -e "ACME Response: ${ACME_CHAT}"
echo -e "GLOBEX Response: ${GLOBEX_CHAT}"

if [[ "$ACME_CHAT" == *"ACME"* && "$GLOBEX_CHAT" == *"Globex"* && "$ACME_CHAT" != "$GLOBEX_CHAT" ]]; then
  echo -e "${GREEN}✓ Success: Chat API returns tenant-specific information${NC}"
else
  echo -e "${RED}✗ Failure: Chat API doesn't properly isolate tenant data${NC}"
fi

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}TENANT ISOLATION TESTING COMPLETED!${NC}"
echo -e "${BLUE}==================================================${NC}"

exit 0
