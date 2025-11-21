#!/bin/bash

# Script to test the API with Langfuse integration

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================="
echo "  TESTING LANGFUSE INTEGRATION"
echo -e "==========================================================${NC}"

# Set AWS region for this session
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1

# API Gateway URL
API_URL="https://xn66ohjpw1.execute-api.us-east-1.amazonaws.com/dev"
echo -e "API Gateway URL: ${GREEN}$API_URL${NC}"

# Generate unique request IDs for Langfuse tracing
KB_QUERY_REQUEST_ID="langfuse-test-kb-$(date +%s)"
CHAT_REQUEST_ID="langfuse-test-chat-$(date +%s)"

echo -e "\n${YELLOW}========== 1. Testing KB Query with Langfuse Tracing ==========${NC}"
echo -e "Using request ID: ${GREEN}$KB_QUERY_REQUEST_ID${NC}"

KB_QUERY_RESPONSE=$(curl -s -X POST "$API_URL/api/kb/query" \
    -H "Content-Type: application/json" \
    -H "x-tenant-id: acme" \
    -H "x-user-id: test-user" \
    -H "x-request-id: $KB_QUERY_REQUEST_ID" \
    -d '{
        "tenant": "acme",
        "query": "What is the status of our implementation?",
        "max_results": 3
    }')

echo -e "\nKB Query response:"
echo "$KB_QUERY_RESPONSE" | jq .

echo -e "\n${YELLOW}========== 2. Testing Chat with Langfuse Tracing ==========${NC}"
echo -e "Using request ID: ${GREEN}$CHAT_REQUEST_ID${NC}"

CHAT_RESPONSE=$(curl -s -X POST "$API_URL/api/chat" \
    -H "Content-Type: application/json" \
    -H "x-tenant-id: acme" \
    -H "x-user-id: test-user" \
    -H "x-request-id: $CHAT_REQUEST_ID" \
    -d '{
        "tenant": "acme",
        "message": "How is our Cloudable.AI project progressing?",
        "use_kb": true
    }')

echo -e "\nChat response:"
echo "$CHAT_RESPONSE" | jq .

echo -e "\n${YELLOW}========== 3. Verifying Langfuse API Access ==========${NC}"

# Use Langfuse API to check if traces exist
echo -e "Checking Langfuse API access..."
LANGFUSE_PUBLIC_KEY="pk-lf-dfa751eb-07c4-4f93-8edf-222e93e95466"
LANGFUSE_SECRET_KEY="sk-lf-35fe11d6-e8ad-4371-be13-b83a1dfec6bd"

# Encode API key for basic auth
AUTH_HEADER=$(echo -n "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" | base64)

# Make request to Langfuse API (we'll just fetch the most recent 5 traces)
LANGFUSE_RESPONSE=$(curl -s -X GET "https://eu.cloud.langfuse.com/api/public/traces?limit=5" \
    -H "Authorization: Basic $AUTH_HEADER")

echo -e "\nLangfuse API response (recent traces):"
echo "$LANGFUSE_RESPONSE" | jq .

echo -e "\n${BLUE}=========================================================="
echo "  TESTING COMPLETED"
echo -e "==========================================================${NC}"

echo -e "\n${YELLOW}Important Notes:${NC}"
echo -e "1. It may take a few minutes for traces to appear in the Langfuse dashboard"
echo -e "2. To check Langfuse traces, visit: ${GREEN}https://eu.cloud.langfuse.com${NC}"
echo -e "3. Look for traces with these request IDs:"
echo -e "   - KB Query: ${GREEN}$KB_QUERY_REQUEST_ID${NC}"
echo -e "   - Chat: ${GREEN}$CHAT_REQUEST_ID${NC}"