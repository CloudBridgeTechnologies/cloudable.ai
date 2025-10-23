#!/bin/bash
# Script to test the API endpoints

set -e

# Color configuration
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
API_GATEWAY_ID="4momcmaa07"  # Replace with your actual API Gateway ID
API_GATEWAY_STAGE="dev"
REGION="us-east-1"
API_KEY="REPLACE_WITH_ACTUAL_API_KEY"  # Replace with your actual API Key
TENANT_ID="t001"
CUSTOMER_ID="user123"
DOCUMENT_ID="test-doc-123"
SESSION_ID="test-session-$(date +%s)" # Generate a unique session ID

BASE_URL="https://${API_GATEWAY_ID}.execute-api.${REGION}.amazonaws.com/${API_GATEWAY_STAGE}"

echo -e "${BLUE}=== Cloudable.AI API Testing Script ===${NC}"
echo -e "API Endpoint: ${GREEN}${BASE_URL}${NC}"
echo -e "Using API Key: ${YELLOW}${API_KEY:0:4}...${API_KEY: -4}${NC}"
echo -e "Tenant ID: ${GREEN}${TENANT_ID}${NC}\n"

# Function to test API endpoints
test_endpoint() {
    METHOD=$1
    ENDPOINT=$2
    NAME=$3
    PAYLOAD=$4
    
    echo -e "${BLUE}=== Testing ${NAME} ===${NC}"
    echo -e "URL: ${GREEN}${ENDPOINT}${NC}"
    
    if [ "$METHOD" == "POST" ]; then
        echo -e "Payload: ${YELLOW}${PAYLOAD}${NC}"
        RESPONSE=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -H "x-api-key: ${API_KEY}" \
            -d "${PAYLOAD}" \
            "${ENDPOINT}")
    else
        RESPONSE=$(curl -s -X GET \
            -H "Content-Type: application/json" \
            -H "x-api-key: ${API_KEY}" \
            "${ENDPOINT}")
    fi
    
    echo -e "Response: ${GREEN}${RESPONSE}${NC}\n"
    echo "$RESPONSE" | grep -q "error" && return 1 || return 0
}

# Test KB Query API
KB_QUERY_URL="${BASE_URL}/kb/query"
KB_QUERY_PAYLOAD="{\"tenant_id\":\"${TENANT_ID}\",\"query\":\"What are the AI services offered by AWS?\",\"max_results\":3}"
echo -e "\n${YELLOW}1. Testing Knowledge Base Query API${NC}"
if test_endpoint "POST" "$KB_QUERY_URL" "KB Query API" "$KB_QUERY_PAYLOAD"; then
    echo -e "${GREEN}✓ KB Query API test passed${NC}"
else
    echo -e "${RED}✗ KB Query API test failed${NC}"
fi

# Test Chat API
CHAT_URL="${BASE_URL}/chat"
CHAT_PAYLOAD="{\"tenant_id\":\"${TENANT_ID}\",\"customer_id\":\"${CUSTOMER_ID}\",\"message\":\"What is the status of my journey?\",\"session_id\":\"${SESSION_ID}\"}"
echo -e "\n${YELLOW}2. Testing Chat API${NC}"
if test_endpoint "POST" "$CHAT_URL" "Chat API" "$CHAT_PAYLOAD"; then
    echo -e "${GREEN}✓ Chat API test passed${NC}"
else
    echo -e "${RED}✗ Chat API test failed${NC}"
fi

# Test Summary API (GET)
SUMMARY_URL="${BASE_URL}/summary/${TENANT_ID}/${DOCUMENT_ID}"
echo -e "\n${YELLOW}3. Testing Summary Retrieval API${NC}"
if test_endpoint "GET" "$SUMMARY_URL" "Summary API"; then
    echo -e "${GREEN}✓ Summary API test passed${NC}"
else
    echo -e "${RED}✗ Summary API test failed${NC}"
fi

# Test Upload URL API
UPLOAD_URL="${BASE_URL}/kb/upload-url"
UPLOAD_PAYLOAD="{\"tenant_id\":\"${TENANT_ID}\",\"file_name\":\"test-document.pdf\"}"
echo -e "\n${YELLOW}4. Testing Upload URL API${NC}"
if test_endpoint "POST" "$UPLOAD_URL" "Upload URL API" "$UPLOAD_PAYLOAD"; then
    echo -e "${GREEN}✓ Upload URL API test passed${NC}"
else
    echo -e "${RED}✗ Upload URL API test failed${NC}"
fi

# Test KB Sync API
KB_SYNC_URL="${BASE_URL}/kb/sync"
KB_SYNC_PAYLOAD="{\"tenant_id\":\"${TENANT_ID}\",\"document_id\":\"${DOCUMENT_ID}\"}"
echo -e "\n${YELLOW}5. Testing KB Sync API${NC}"
if test_endpoint "POST" "$KB_SYNC_URL" "KB Sync API" "$KB_SYNC_PAYLOAD"; then
    echo -e "${GREEN}✓ KB Sync API test passed${NC}"
else
    echo -e "${RED}✗ KB Sync API test failed${NC}"
fi

echo -e "\n${BLUE}=== API Testing Complete ===${NC}"