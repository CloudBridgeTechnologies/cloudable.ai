#!/bin/bash
# Test API endpoints for Cloudable.AI platform
# This script tests all API endpoints after deployment

set -e

# Color configuration
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Cloudable.AI API Testing ===${NC}"

# Load deployment outputs
if [ -f "deployment_outputs.json" ]; then
    API_ENDPOINT=$(jq -r '.api_endpoint' deployment_outputs.json)
    API_KEY=$(jq -r '.api_key' deployment_outputs.json)
    ENV=$(jq -r '.environment' deployment_outputs.json)
else
    echo -e "${YELLOW}No deployment_outputs.json found. Please enter API details manually:${NC}"
    read -p "API Endpoint (https://xxx.execute-api.region.amazonaws.com/stage): " API_ENDPOINT
    read -p "API Key: " API_KEY
    ENV="dev"
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed.${NC}"
    echo -e "Please install jq: https://stedolan.github.io/jq/download/"
    exit 1
fi

# Generate test parameters
TENANT_ID="t001"
CUSTOMER_ID="test_user_$(date +%s)"
SESSION_ID="test_session_$(date +%s)"
DOCUMENT_ID="test_doc_$(date +%s)"

echo -e "${BLUE}Testing API endpoints with:${NC}"
echo -e "  API Endpoint: ${GREEN}$API_ENDPOINT${NC}"
echo -e "  API Key: ${GREEN}${API_KEY:0:5}...${API_KEY:(-5)}${NC}"
echo -e "  Tenant ID: ${GREEN}$TENANT_ID${NC}"
echo -e "  Customer ID: ${GREEN}$CUSTOMER_ID${NC}"
echo -e "  Session ID: ${GREEN}$SESSION_ID${NC}"

# Function to test an API endpoint
test_endpoint() {
    local name=$1
    local url=$2
    local method=$3
    local payload=$4
    
    echo -e "\n${BLUE}Testing $name...${NC}"
    echo -e "URL: ${GREEN}$url${NC}"
    
    if [ "$method" == "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" -X GET "$url" \
            -H "Content-Type: application/json" \
            -H "x-api-key: $API_KEY")
    else
        echo -e "Payload: ${GREEN}$payload${NC}"
        response=$(curl -s -w "\n%{http_code}" -X POST "$url" \
            -H "Content-Type: application/json" \
            -H "x-api-key: $API_KEY" \
            -d "$payload")
    fi
    
    status_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [[ $status_code -ge 200 && $status_code -lt 300 ]]; then
        echo -e "${GREEN}Status: $status_code - Success!${NC}"
    else
        echo -e "${RED}Status: $status_code - Failed!${NC}"
    fi
    
    echo -e "Response: ${YELLOW}$body${NC}"
    
    return $([[ $status_code -ge 200 && $status_code -lt 300 ]])
}

# Initialize results array
declare -A results

# Test 1: Chat API
echo -e "\n${BLUE}=== Test 1: Chat API ===${NC}"
chat_url="$API_ENDPOINT/chat"
chat_payload="{\"tenant_id\":\"$TENANT_ID\",\"customer_id\":\"$CUSTOMER_ID\",\"message\":\"What is my journey status?\",\"session_id\":\"$SESSION_ID\"}"
test_endpoint "Chat API" "$chat_url" "POST" "$chat_payload"
results["chat"]=$?

# Test 2: KB Query API
echo -e "\n${BLUE}=== Test 2: KB Query API ===${NC}"
kb_query_url="$API_ENDPOINT/kb/query"
kb_query_payload="{\"tenant_id\":\"$TENANT_ID\",\"query\":\"What are the AI services offered by AWS?\",\"max_results\":3}"
test_endpoint "KB Query API" "$kb_query_url" "POST" "$kb_query_payload"
results["kb_query"]=$?

# Test 3: Upload URL API
echo -e "\n${BLUE}=== Test 3: Upload URL API ===${NC}"
upload_url="$API_ENDPOINT/kb/upload-url"
upload_payload="{\"tenant_id\":\"$TENANT_ID\",\"file_name\":\"test-document.pdf\"}"
test_endpoint "Upload URL API" "$upload_url" "POST" "$upload_payload"
results["upload_url"]=$?

# Test 4: KB Sync API
echo -e "\n${BLUE}=== Test 4: KB Sync API ===${NC}"
kb_sync_url="$API_ENDPOINT/kb/sync"
kb_sync_payload="{\"tenant_id\":\"$TENANT_ID\",\"document_id\":\"$DOCUMENT_ID\"}"
test_endpoint "KB Sync API" "$kb_sync_url" "POST" "$kb_sync_payload"
results["kb_sync"]=$?

# Test 5: Summary API (GET)
echo -e "\n${BLUE}=== Test 5: Summary API (GET) ===${NC}"
summary_url="$API_ENDPOINT/summary/$TENANT_ID/$DOCUMENT_ID"
test_endpoint "Summary API (GET)" "$summary_url" "GET"
results["summary_get"]=$?

# Test 6: Summary API (POST)
echo -e "\n${BLUE}=== Test 6: Summary API (POST) ===${NC}"
summary_post_url="$API_ENDPOINT/summary/$TENANT_ID/$DOCUMENT_ID"
summary_post_payload="{\"force_regenerate\":true}"
test_endpoint "Summary API (POST)" "$summary_post_url" "POST" "$summary_post_payload"
results["summary_post"]=$?

# Print summary
echo -e "\n${BLUE}=== Test Summary ===${NC}"
for api in "${!results[@]}"; do
    status=${results[$api]}
    if [ $status -eq 0 ]; then
        echo -e "${GREEN}✅ $api: PASS${NC}"
    else
        echo -e "${RED}❌ $api: FAIL${NC}"
    fi
done

# Save test results
{
    echo "{"
    echo "  \"test_time\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
    echo "  \"environment\": \"$ENV\","
    echo "  \"results\": {"
    
    # Add each test result
    first=true
    for api in "${!results[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        status=${results[$api]}
        success=$([[ $status -eq 0 ]] && echo "true" || echo "false")
        echo -n "    \"$api\": $success"
    done
    
    echo ""
    echo "  }"
    echo "}"
} > api_test_results.json

echo -e "${BLUE}Test results saved to api_test_results.json${NC}"
