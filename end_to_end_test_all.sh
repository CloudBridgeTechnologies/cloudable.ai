#!/bin/bash

# End-to-End Test Script for Cloudable.AI
# Tests all functionality including KB queries, chat, and customer status

set -e

# Configuration
API_ENDPOINT="https://xn66ohjpw1.execute-api.us-east-1.amazonaws.com/dev"
AWS_DEFAULT_REGION=us-east-1
USER_ID="user-admin-001"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TOTAL=0
PASSED=0
FAILED=0

# Print header
print_header() {
    echo -e "\n${BLUE}=========================================================="
    echo "  $1"
    echo -e "==========================================================${NC}"
}

# Print step header
print_step() {
    echo -e "\n${YELLOW}>>> $1${NC}"
}

# Print success message
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
    PASSED=$((PASSED + 1))
    TOTAL=$((TOTAL + 1))
}

# Print failure message
print_failure() {
    echo -e "${RED}❌ $1${NC}"
    FAILED=$((FAILED + 1))
    TOTAL=$((TOTAL + 1))
}

# Test KB Query
test_kb_query() {
    local tenant=$1
    local query=$2
    local description=$3
    
    print_step "Testing KB Query: $description (Tenant: $tenant)"
    echo "Query: \"$query\""
    
    response=$(curl -s -X POST "$API_ENDPOINT/api/kb/query" \
        -H "Content-Type: application/json" \
        -H "x-tenant-id: $tenant" \
        -H "x-user-id: $USER_ID" \
        -d "{
            \"tenant\": \"$tenant\",
            \"query\": \"$query\",
            \"max_results\": 3
        }")
    
    # Check response
    if echo "$response" | grep -q "results"; then
        result_text=$(echo "$response" | jq -r '.results[0].text' 2>/dev/null)
        echo "Response: \"${result_text:0:100}...\""
        print_success "KB query successful"
    else
        echo "Response: $response"
        print_failure "KB query failed"
    fi
}

# Test Chat
test_chat() {
    local tenant=$1
    local message=$2
    local description=$3
    
    print_step "Testing Chat: $description (Tenant: $tenant)"
    echo "Message: \"$message\""
    
    response=$(curl -s -X POST "$API_ENDPOINT/api/chat" \
        -H "Content-Type: application/json" \
        -H "x-tenant-id: $tenant" \
        -H "x-user-id: $USER_ID" \
        -d "{
            \"tenant\": \"$tenant\",
            \"message\": \"$message\",
            \"use_kb\": true
        }")
    
    # Check response
    if echo "$response" | grep -q "response"; then
        response_text=$(echo "$response" | jq -r '.response' 2>/dev/null)
        echo "Response: \"${response_text:0:100}...\""
        print_success "Chat successful"
    else
        echo "Response: $response"
        print_failure "Chat failed"
    fi
}

# Test Customer Status
test_customer_status() {
    local tenant=$1
    local customer_id=$2
    local description=$3
    
    print_step "Testing Customer Status: $description (Tenant: $tenant)"
    
    payload="{\"tenant\": \"$tenant\"}"
    if [[ -n "$customer_id" ]]; then
        echo "Customer ID: $customer_id"
        payload="{\"tenant\": \"$tenant\", \"customer_id\": \"$customer_id\"}"
    else
        echo "Getting all customers"
    fi
    
    response=$(curl -s -X POST "$API_ENDPOINT/api/customer-status" \
        -H "Content-Type: application/json" \
        -H "x-tenant-id: $tenant" \
        -H "x-user-id: $USER_ID" \
        -d "$payload")
    
    # Check response
    if echo "$response" | grep -q -E "customer|customers"; then
        echo "Response contains customer data"
        print_success "Customer status query successful"
    else
        echo "Response: $response"
        print_failure "Customer status query failed"
        
        # Debug info for customer status
        echo "Debugging customer status endpoint..."
        
        # Try to check if the endpoint exists
        health_check=$(curl -s -X GET "$API_ENDPOINT/api/health")
        echo "Health check response: $health_check"
        
        # Check Lambda environment variables
        echo "Note: The customer status endpoint might not be properly configured."
        echo "Make sure your Lambda has the following environment variables:"
        echo "- CUSTOMER_STATUS_ENABLED=true"
        echo "- RDS_CLUSTER_ARN, RDS_SECRET_ARN, RDS_DATABASE set correctly"
        echo "- Tables need to be initialized with the setup_customer_status.py script"
    fi
}

# Test cross-tenant isolation
test_cross_tenant() {
    local tenant=$1
    local other_tenant=$2
    local query=$3
    
    print_step "Testing Cross-tenant Isolation: $tenant querying about $other_tenant"
    echo "Query: \"$query\""
    
    response=$(curl -s -X POST "$API_ENDPOINT/api/kb/query" \
        -H "Content-Type: application/json" \
        -H "x-tenant-id: $tenant" \
        -H "x-user-id: $USER_ID" \
        -d "{
            \"tenant\": \"$tenant\",
            \"query\": \"$query\",
            \"max_results\": 3
        }")
    
    # Check for privacy message
    if echo "$response" | grep -q "not available"; then
        result_text=$(echo "$response" | jq -r '.results[0].text' 2>/dev/null)
        echo "Response: \"$result_text\""
        print_success "Cross-tenant isolation working correctly"
    else
        echo "Response: $response"
        print_failure "Cross-tenant isolation failed"
    fi
}

# Test health endpoint
test_health() {
    print_step "Testing Health Endpoint"
    
    response=$(curl -s -X GET "$API_ENDPOINT/api/health")
    
    # Check response
    if echo "$response" | grep -q "operational"; then
        echo "Response: $response"
        print_success "Health check successful"
    else
        echo "Response: $response"
        print_failure "Health check failed"
    fi
}

# ============================================================
# Main Test Execution
# ============================================================

print_header "STARTING END-TO-END TESTS: $(date)"

# Test health endpoint
test_health

# Test ACME tenant
print_header "TESTING ACME TENANT"

test_kb_query "acme" "What is our current implementation status?" "Implementation Status"
test_kb_query "acme" "What are the key success metrics for our project?" "Success Metrics"
test_kb_query "acme" "What are the next steps in our implementation plan?" "Next Steps"
test_kb_query "acme" "What is the timeline for our implementation?" "Timeline"

test_chat "acme" "How is our implementation progressing?" "Implementation Progress"
test_chat "acme" "What success metrics are we tracking?" "Success Metrics"
test_chat "acme" "What are the key challenges we're facing?" "Challenges"

test_customer_status "acme" "" "All Customers"
test_customer_status "acme" "cust-001" "Specific Customer"

# Test GLOBEX tenant
print_header "TESTING GLOBEX TENANT"

test_kb_query "globex" "What is our current implementation status?" "Implementation Status"
test_kb_query "globex" "Who are the key stakeholders for our project?" "Stakeholders"
test_kb_query "globex" "What risks have been identified for our implementation?" "Risks"
test_kb_query "globex" "What is the timeline for our implementation?" "Timeline"

test_chat "globex" "What stage are we in our implementation journey?" "Implementation Stage"
test_chat "globex" "Who are our key stakeholders and what are their roles?" "Stakeholders"
test_chat "globex" "Tell me about the main objectives of our digital transformation" "Objectives"

test_customer_status "globex" "" "All Customers"
test_customer_status "globex" "cust-101" "Specific Customer"

# Test cross-tenant isolation
print_header "TESTING CROSS-TENANT ISOLATION"

test_cross_tenant "acme" "globex" "Tell me about Globex Industries implementation status"
test_cross_tenant "globex" "acme" "What is ACME Corporation's implementation status?"

# Print summary
print_header "TEST SUMMARY: $(date)"
echo "Total tests: $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed!${NC}"
    exit 1
fi
