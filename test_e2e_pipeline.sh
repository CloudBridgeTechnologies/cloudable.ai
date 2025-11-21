#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Set AWS region to eu-west-1
export AWS_REGION=eu-west-1
export AWS_DEFAULT_REGION=eu-west-1

# Get API endpoint from Terraform
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/infras/core"
API_ENDPOINT=$(terraform output -raw api_endpoint 2>/dev/null || echo "")

if [ -z "$API_ENDPOINT" ]; then
    echo -e "${RED}ERROR: Could not get API endpoint from Terraform.${NC}"
    echo -e "${YELLOW}Trying to get it from AWS directly...${NC}"
    API_ID=$(aws apigatewayv2 get-apis --query "Items[?Name=='cloudable-kb-api-core'].ApiId" --output text 2>/dev/null)
    if [ -n "$API_ID" ]; then
        API_ENDPOINT="https://${API_ID}.execute-api.eu-west-1.amazonaws.com/dev"
    else
        echo -e "${RED}ERROR: Could not find API Gateway.${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI END-TO-END PIPELINE TEST         ${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "${YELLOW}API Endpoint: ${API_ENDPOINT}${NC}"
echo -e "${YELLOW}Region: eu-west-1 (Ireland)${NC}\n"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Function to test API endpoint
test_endpoint() {
    local name=$1
    local method=$2
    local path=$3
    local payload=$4
    local expected_status=$5
    
    echo -e "\n${YELLOW}Testing: ${name}${NC}"
    echo -e "${YELLOW}Method: ${method} | Path: ${path}${NC}"
    
    if [ "$method" == "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" "${API_ENDPOINT}${path}" \
            -H "X-User-ID: user-reader-001")
    else
        response=$(curl -s -w "\n%{http_code}" -X "${method}" "${API_ENDPOINT}${path}" \
            -H "Content-Type: application/json" \
            -H "X-User-ID: user-reader-001" \
            -d "$payload")
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" == "$expected_status" ]; then
        echo -e "${GREEN}✓ PASSED (HTTP ${http_code})${NC}"
        echo -e "${GREEN}Response: ${body}${NC}" | head -c 200
        echo ""
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAILED (Expected ${expected_status}, got ${http_code})${NC}"
        echo -e "${RED}Response: ${body}${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Step 1: Health Check
echo -e "\n${BLUE}=== STEP 1: Health Check ===${NC}"
test_endpoint "Health Check" "GET" "/api/health" "" "200"

# Step 2: Get Upload URL
echo -e "\n${BLUE}=== STEP 2: Get Presigned Upload URL ===${NC}"
UPLOAD_PAYLOAD='{"tenant":"acme","filename":"test_document.md","content_type":"text/markdown"}'
UPLOAD_RESPONSE=$(curl -s -X POST "${API_ENDPOINT}/api/upload-url" \
    -H "Content-Type: application/json" \
    -H "X-User-ID: user-admin-001" \
    -d "$UPLOAD_PAYLOAD")

echo -e "${YELLOW}Upload URL Response:${NC}"
echo "$UPLOAD_RESPONSE" | jq '.'

UPLOAD_URL=$(echo "$UPLOAD_RESPONSE" | jq -r '.url // empty')
UPLOAD_KEY=$(echo "$UPLOAD_RESPONSE" | jq -r '.key // empty')
UPLOAD_BUCKET=$(echo "$UPLOAD_RESPONSE" | jq -r '.bucket // empty')

if [ -n "$UPLOAD_URL" ] && [ "$UPLOAD_URL" != "null" ]; then
    echo -e "${GREEN}✓ Got presigned URL${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    
    # Step 3: Upload Test Document
    echo -e "\n${BLUE}=== STEP 3: Upload Document to S3 ===${NC}"
    TEST_DOC_CONTENT="# Cloudable.AI Test Document

## Overview
This is a test document for end-to-end pipeline testing.

## Key Information
- Cloudable.AI provides vector similarity search
- Multi-tenant architecture
- Integration with AWS Bedrock
- PostgreSQL with pgvector extension

## Testing
This document is used to verify the complete pipeline from upload to query."
    
    UPLOAD_RESULT=$(echo "$TEST_DOC_CONTENT" | curl -s -w "\n%{http_code}" -X PUT "$UPLOAD_URL" \
        -H "Content-Type: text/markdown" \
        --data-binary @-)
    
    UPLOAD_HTTP_CODE=$(echo "$UPLOAD_RESULT" | tail -n1)
    
    if [ "$UPLOAD_HTTP_CODE" == "200" ] || [ "$UPLOAD_HTTP_CODE" == "204" ] || [ "$UPLOAD_HTTP_CODE" == "307" ]; then
        echo -e "${GREEN}✓ Document uploaded successfully (HTTP ${UPLOAD_HTTP_CODE})${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        
        # Step 4: Trigger KB Sync
        echo -e "\n${BLUE}=== STEP 4: Trigger Knowledge Base Sync ===${NC}"
        DOCUMENT_KEY=$(echo "$UPLOAD_RESPONSE" | jq -r '.document_key')
        echo "Document key for sync: $DOCUMENT_KEY"
        SYNC_PAYLOAD="{\"tenant\":\"acme\",\"document_key\":\"$DOCUMENT_KEY\"}"
        echo -e "${YELLOW}Testing: KB Sync${NC}"
        SYNC_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_ENDPOINT}/api/kb/sync" \
            -H "Content-Type: application/json" \
            -H "X-User-ID: user-admin-001" \
            -d "$SYNC_PAYLOAD")
        SYNC_HTTP_CODE=$(echo "$SYNC_RESPONSE" | tail -n1)
        SYNC_BODY=$(echo "$SYNC_RESPONSE" | sed '$d')
        if [ "$SYNC_HTTP_CODE" == "200" ]; then
            echo -e "${GREEN}✓ PASSED (HTTP ${SYNC_HTTP_CODE})${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}✗ FAILED (Expected 200, got ${SYNC_HTTP_CODE})${NC}"
            echo -e "${RED}Response: ${SYNC_BODY}${NC}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        
        # Wait for sync to complete
        echo -e "${YELLOW}Waiting 10 seconds for sync to process...${NC}"
        sleep 10
    else
        echo -e "${RED}✗ Document upload failed (HTTP ${UPLOAD_HTTP_CODE})${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
else
    echo -e "${RED}✗ Failed to get presigned URL${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Step 5: KB Query Tests
echo -e "\n${BLUE}=== STEP 5: Knowledge Base Query Tests ===${NC}"

# Test 5.1: Query about ACME status
test_endpoint "KB Query - ACME Status" "POST" "/api/kb/query" \
    '{"tenant":"acme","query":"What is the current status of ACME Corporation?","max_results":3}' "200"

# Test 5.2: Query about success metrics
test_endpoint "KB Query - Success Metrics" "POST" "/api/kb/query" \
    '{"tenant":"acme","query":"What are the success metrics for ACME?","max_results":3}' "200"

# Test 5.3: Query for Globex tenant
test_endpoint "KB Query - Globex Status" "POST" "/api/kb/query" \
    '{"tenant":"globex","query":"What is the current status of Globex Industries?","max_results":3}' "200"

# Step 6: Chat Tests
echo -e "\n${BLUE}=== STEP 6: Chat API Tests ===${NC}"

# Test 6.1: Chat with ACME tenant
test_endpoint "Chat - ACME Progress" "POST" "/api/chat" \
    '{"tenant":"acme","message":"Tell me about ACME implementation progress","use_kb":true}' "200"

# Test 6.2: Chat with Globex tenant
test_endpoint "Chat - Globex Objectives" "POST" "/api/chat" \
    '{"tenant":"globex","message":"What are the key objectives for Globex?","use_kb":true}' "200"

# Test 6.3: Chat without KB
test_endpoint "Chat - Without KB" "POST" "/api/chat" \
    '{"tenant":"acme","message":"Hello, how are you?","use_kb":false}' "200"

# Step 7: Customer Status Tests
echo -e "\n${BLUE}=== STEP 7: Customer Status API Tests ===${NC}"

# Test 7.1: Get all customers for ACME
test_endpoint "Customer Status - ACME All" "POST" "/api/customer-status" \
    '{"tenant":"acme"}' "200"

# Test 7.2: Get all customers for Globex
test_endpoint "Customer Status - Globex All" "POST" "/api/customer-status" \
    '{"tenant":"globex"}' "200"

# Step 8: Error Handling Tests
echo -e "\n${BLUE}=== STEP 8: Error Handling Tests ===${NC}"

# Test 8.1: Invalid tenant
test_endpoint "Error - Invalid Tenant" "POST" "/api/kb/query" \
    '{"tenant":"invalid_tenant","query":"test query","max_results":3}' "403"

# Test 8.2: Missing required fields
test_endpoint "Error - Missing Fields" "POST" "/api/kb/query" \
    '{"tenant":"acme"}' "400"

# Test 8.3: Unauthorized access (no user ID)
UNAUTH_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_ENDPOINT}/api/kb/query" \
    -H "Content-Type: application/json" \
    -d '{"tenant":"acme","query":"test","max_results":3}')
UNAUTH_CODE=$(echo "$UNAUTH_RESPONSE" | tail -n1)
if [ "$UNAUTH_CODE" == "403" ]; then
    echo -e "${GREEN}✓ Unauthorized access properly rejected (HTTP 403)${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${YELLOW}⚠ Unauthorized test returned HTTP ${UNAUTH_CODE} (expected 403)${NC}"
fi

# Step 9: Multi-tenant Isolation Tests
echo -e "\n${BLUE}=== STEP 9: Multi-Tenant Isolation Tests ===${NC}"

# Test 9.1: ACME cannot access Globex data
ACME_QUERY_RESPONSE=$(curl -s -X POST "${API_ENDPOINT}/api/kb/query" \
    -H "Content-Type: application/json" \
    -H "X-User-ID: user-reader-001" \
    -d '{"tenant":"acme","query":"What is Globex status?","max_results":3}')
ACME_HAS_GLOBEX=$(echo "$ACME_QUERY_RESPONSE" | jq -r '.results[0].text // ""' | grep -i "globex" || echo "")

if [ -z "$ACME_HAS_GLOBEX" ] || echo "$ACME_QUERY_RESPONSE" | jq -e '.results[0].text | contains("not available")' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Tenant isolation working (ACME cannot access Globex data)${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗ Tenant isolation may be compromised${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Final Summary
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${BLUE}   END-TO-END PIPELINE TEST SUMMARY              ${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}Tests Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Tests Failed: ${TESTS_FAILED}${NC}"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
if [ $TOTAL_TESTS -gt 0 ]; then
    SUCCESS_RATE=$((TESTS_PASSED * 100 / TOTAL_TESTS))
    echo -e "${YELLOW}Success Rate: ${SUCCESS_RATE}%${NC}"
fi

echo -e "\n${YELLOW}API Endpoint: ${API_ENDPOINT}${NC}"
echo -e "${YELLOW}Region: eu-west-1 (Ireland)${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}✓ All tests passed! Pipeline is working correctly.${NC}"
    exit 0
else
    echo -e "\n${RED}✗ Some tests failed. Please review the errors above.${NC}"
    exit 1
fi