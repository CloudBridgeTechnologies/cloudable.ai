#!/bin/bash

# Script to test both the customer status API and Langfuse integration

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================="
echo "  TESTING FIXES FOR CLOUDABLE.AI"
echo -e "==========================================================${NC}"

# Set AWS region for this session
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1
echo -e "Using AWS Region: ${GREEN}$AWS_DEFAULT_REGION${NC}"

# Set the API Gateway URL directly with the default stage
API_URL="https://xn66ohjpw1.execute-api.us-east-1.amazonaws.com/dev"

if [ -z "$API_URL" ]; then
    echo -e "${RED}API Gateway URL not set. Please provide a valid API URL.${NC}"
    exit 1
fi

echo -e "API Gateway URL: ${GREEN}$API_URL${NC}"
echo -e "\n${YELLOW}========== 1. Testing Customer Status API ==========${NC}"

# Test customer status API for ACME tenant
echo -e "\n${YELLOW}Testing customer status for ACME tenant...${NC}"

RESPONSE=$(curl -s -X POST "$API_URL/api/customer-status" \
    -H "Content-Type: application/json" \
    -H "x-tenant-id: acme" \
    -H "x-user-id: user-admin-001" \
    -H "x-request-id: test-customer-status-1" \
    -d '{
        "tenant": "acme"
    }')

echo "Response for ACME tenant customer list:"
echo "$RESPONSE" | jq .

# Test customer status for a specific customer
echo -e "\n${YELLOW}Testing specific customer status for ACME tenant...${NC}"

RESPONSE=$(curl -s -X POST "$API_URL/api/customer-status" \
    -H "Content-Type: application/json" \
    -H "x-tenant-id: acme" \
    -H "x-user-id: user-admin-001" \
    -H "x-request-id: test-customer-status-2" \
    -d '{
        "tenant": "acme",
        "customer_id": "cust-001"
    }')

echo "Response for specific customer (cust-001):"
echo "$RESPONSE" | jq .

# Test customer status for Globex tenant
echo -e "\n${YELLOW}Testing customer status for Globex tenant...${NC}"

RESPONSE=$(curl -s -X POST "$API_URL/api/customer-status" \
    -H "Content-Type: application/json" \
    -H "x-tenant-id: globex" \
    -H "x-user-id: user-admin-002" \
    -H "x-request-id: test-customer-status-3" \
    -d '{
        "tenant": "globex"
    }')

echo "Response for Globex tenant customer list:"
echo "$RESPONSE" | jq .

# Check if any of the responses have an error field
if echo "$RESPONSE" | jq -e '.error' > /dev/null; then
    echo -e "\n${RED}Customer status API tests encountered errors${NC}"
else
    echo -e "\n${GREEN}Customer status API tests passed successfully${NC}"
fi

echo -e "\n${YELLOW}========== 2. Testing Langfuse Integration ==========${NC}"

# Test Langfuse integration with KB query
echo -e "\n${YELLOW}Testing Langfuse integration with KB query...${NC}"

KB_QUERY_RESPONSE=$(curl -s -X POST "$API_URL/api/kb/query" \
    -H "Content-Type: application/json" \
    -H "x-tenant-id: acme" \
    -H "x-user-id: user-admin-001" \
    -H "x-request-id: langfuse-test-1" \
    -d '{
        "tenant": "acme",
        "query": "What is the status of our implementation?",
        "max_results": 3
    }')

echo "KB Query response:"
echo "$KB_QUERY_RESPONSE" | jq .

# Test Langfuse integration with chat
echo -e "\n${YELLOW}Testing Langfuse integration with chat...${NC}"

CHAT_RESPONSE=$(curl -s -X POST "$API_URL/api/chat" \
    -H "Content-Type: application/json" \
    -H "x-tenant-id: acme" \
    -H "x-user-id: user-admin-001" \
    -H "x-request-id: langfuse-test-2" \
    -d '{
        "tenant": "acme",
        "message": "How is our Langfuse integration progressing?",
        "use_kb": true
    }')

echo "Chat response:"
echo "$CHAT_RESPONSE" | jq .

# Check Langfuse traces
echo -e "\n${YELLOW}Checking Langfuse traces (most recent 5)...${NC}"
echo -e "${BLUE}Note: It may take a few minutes for traces to appear in Langfuse${NC}"

# Use Basic Auth with Langfuse API keys
AUTH_HEADER="Basic $(echo -n pk-lf-dfa751eb-07c4-4f93-8edf-222e93e95466:sk-lf-35fe11d6-e8ad-4371-be13-b83a1dfec6bd | base64)"

LANGFUSE_RESPONSE=$(curl -s -X GET "https://eu.cloud.langfuse.com/api/public/traces?limit=5" \
    -H "Authorization: $AUTH_HEADER")

echo "Langfuse traces:"
echo "$LANGFUSE_RESPONSE" | jq .

echo -e "\n${BLUE}=========================================================="
echo "  TESTING COMPLETED"
echo -e "==========================================================${NC}"

echo -e "\nTo verify Langfuse integration, check the following:"
echo -e "1. Visit https://eu.cloud.langfuse.com and log in"
echo -e "2. Look for traces with IDs 'langfuse-test-1' and 'langfuse-test-2'"
echo -e "3. Check that the traces have spans for 'kb_query' and 'chat_response'"
