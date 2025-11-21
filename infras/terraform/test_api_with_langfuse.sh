#!/bin/bash

# Script to test the API with Langfuse integration

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================="
echo "  TESTING CLOUDABLE.AI API WITH LANGFUSE"
echo -e "==========================================================${NC}"

# Set AWS region for this session
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1

# Get API Gateway URL from Terraform output
API_URL=$(terraform output -raw api_gateway_url)

if [ -z "$API_URL" ]; then
    echo -e "${RED}API Gateway URL not found. Please deploy the infrastructure first.${NC}"
    exit 1
fi

echo -e "API Gateway URL: ${GREEN}$API_URL${NC}"

# Generate unique test IDs for tracing in Langfuse
TEST_ID_1=$(uuidgen)
TEST_ID_2=$(uuidgen)

echo -e "\n${YELLOW}========== 1. Testing KB Query with Langfuse Tracing ==========${NC}"

echo -e "Using trace ID: ${GREEN}$TEST_ID_1${NC}"

KB_QUERY_RESPONSE=$(curl -s -X POST "$API_URL/api/kb/query" \
    -H "Content-Type: application/json" \
    -H "x-tenant-id: acme" \
    -H "x-user-id: user-admin-001" \
    -H "x-request-id: $TEST_ID_1" \
    -d '{
        "tenant": "acme",
        "query": "What is the status of our implementation?",
        "max_results": 3
    }')

echo -e "\nKB Query response:"
echo "$KB_QUERY_RESPONSE" | jq .

echo -e "\n${YELLOW}========== 2. Testing Chat with Langfuse Tracing ==========${NC}"

echo -e "Using trace ID: ${GREEN}$TEST_ID_2${NC}"

CHAT_RESPONSE=$(curl -s -X POST "$API_URL/api/chat" \
    -H "Content-Type: application/json" \
    -H "x-tenant-id: acme" \
    -H "x-user-id: user-admin-001" \
    -H "x-request-id: $TEST_ID_2" \
    -d '{
        "tenant": "acme",
        "message": "How is our project progressing?",
        "use_kb": true
    }')

echo -e "\nChat response:"
echo "$CHAT_RESPONSE" | jq .

echo -e "\n${YELLOW}========== 3. Testing Customer Status API ==========${NC}"

CUSTOMER_STATUS_RESPONSE=$(curl -s -X POST "$API_URL/api/customer-status" \
    -H "Content-Type: application/json" \
    -H "x-tenant-id: acme" \
    -H "x-user-id: user-admin-001" \
    -d '{
        "tenant": "acme"
    }')

echo -e "\nCustomer Status response:"
echo "$CUSTOMER_STATUS_RESPONSE" | jq .

echo -e "\n${BLUE}=========================================================="
echo "  API TESTING COMPLETED"
echo -e "==========================================================${NC}"

echo -e "\nTo check Langfuse traces, visit: ${GREEN}https://eu.cloud.langfuse.com${NC}"
echo -e "Look for traces with these IDs:"
echo -e "- KB Query: ${GREEN}$TEST_ID_1${NC}"
echo -e "- Chat: ${GREEN}$TEST_ID_2${NC}"

echo -e "\nNote: It may take a few minutes for traces to appear in the Langfuse dashboard."
