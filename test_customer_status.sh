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
echo -e "${BLUE}   CLOUDABLE.AI CUSTOMER STATUS TEST              ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Get the API Gateway endpoint from Terraform output
cd infras/core || exit 1
API_ENDPOINT=$(terraform output -raw api_endpoint)
cd - || exit 1

if [ -z "$API_ENDPOINT" ]; then
    echo -e "${RED}Failed to get API endpoint from Terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}Using API endpoint: ${API_ENDPOINT}${NC}"

# Test functions
test_tenant_customers() {
    local tenant=$1
    local user_id=$2
    
    echo -e "\n${YELLOW}Test: List all customers for tenant: ${tenant}${NC}"
    
    response=$(curl -s -X POST \
      "${API_ENDPOINT}/api/customer-status" \
      -H "Content-Type: application/json" \
      -H "x-user-id: ${user_id}" \
      -d "{\"tenant\":\"${tenant}\"}")
    
    echo -e "Response:"
    echo "$response" | jq '.' || echo "$response"
    
    # Check if the response contains customers array
    if echo "$response" | grep -q "customers"; then
        echo -e "${GREEN}✓ Success: Retrieved customer list for tenant ${tenant}${NC}"
    else
        echo -e "${RED}✗ Failed: Could not retrieve customer list${NC}"
    fi
}

test_customer_details() {
    local tenant=$1
    local user_id=$2
    
    # First, get customer IDs for this tenant
    local list_response=$(curl -s -X POST \
      "${API_ENDPOINT}/api/customer-status" \
      -H "Content-Type: application/json" \
      -d "{\"tenant\":\"${tenant}\"}")
    
    # Extract the first customer ID using jq
    local customer_id=$(echo "$list_response" | jq -r '.customers[0].customer_id')
    
    if [ "$customer_id" == "null" ] || [ -z "$customer_id" ]; then
        echo -e "${RED}No customers found for tenant: ${tenant}${NC}"
        return 1
    fi
    
    echo -e "\n${YELLOW}Test: Get details for customer: ${customer_id} in tenant: ${tenant}${NC}"
    
    local response=$(curl -s -X POST \
      "${API_ENDPOINT}/api/customer-status" \
      -H "Content-Type: application/json" \
      -H "x-user-id: ${user_id}" \
      -d "{\"tenant\":\"${tenant}\", \"customer_id\":\"${customer_id}\"}")
    
    echo -e "Response:"
    echo "$response" | jq '.' || echo "$response"
    
    # Check if the response contains customer data and milestones
    if echo "$response" | grep -q "customer" && echo "$response" | grep -q "milestones"; then
        echo -e "${GREEN}✓ Success: Retrieved customer details and milestones${NC}"
        
        # Check if summary is available (from Bedrock)
        if echo "$response" | grep -q "summary"; then
            echo -e "${GREEN}✓ Bedrock summarization is working${NC}"
            echo -e "Summary: $(echo "$response" | jq -r '.summary')"
        else
            echo -e "${YELLOW}⚠ Bedrock summarization not available${NC}"
        fi
    else
        echo -e "${RED}✗ Failed: Could not retrieve customer details${NC}"
    fi
}

test_cross_tenant_access() {
    echo -e "\n${YELLOW}Test: Cross-tenant access attempt${NC}"
    echo -e "Admin user from acme tries to access globex customer data"
    
    # First, get globex customer IDs
    local globex_list=$(curl -s -X POST \
      "${API_ENDPOINT}/api/customer-status" \
      -H "Content-Type: application/json" \
      -d "{\"tenant\":\"globex\"}")
    
    # Extract the first customer ID
    local globex_customer_id=$(echo "$globex_list" | jq -r '.customers[0].customer_id')
    
    if [ "$globex_customer_id" == "null" ] || [ -z "$globex_customer_id" ]; then
        echo -e "${RED}No globex customers found to test cross-tenant access${NC}"
        return 1
    fi
    
    # Now try to access this globex customer as acme tenant
    local response=$(curl -s -X POST \
      "${API_ENDPOINT}/api/customer-status" \
      -H "Content-Type: application/json" \
      -H "x-user-id: user-admin-001" \
      -d "{\"tenant\":\"acme\", \"customer_id\":\"${globex_customer_id}\"}")
    
    echo -e "Response:"
    echo "$response" | jq '.' || echo "$response"
    
    # Check if an empty or error response is returned
    if echo "$response" | grep -q "error" || echo "$response" | grep -q "Customer not found"; then
        echo -e "${GREEN}✓ Success: Cross-tenant access properly prevented${NC}"
    else
        echo -e "${RED}✗ Failure: Cross-tenant access might be allowed${NC}"
    fi
}

# Run tests for both tenants
echo -e "\n${BLUE}=== Testing ACME tenant ===${NC}"
test_tenant_customers "acme" "user-admin-001"
test_customer_details "acme" "user-admin-001"

echo -e "\n${BLUE}=== Testing Globex tenant ===${NC}"
test_tenant_customers "globex" "user-admin-001"
test_customer_details "globex" "user-admin-001"

echo -e "\n${BLUE}=== Testing tenant isolation ===${NC}"
test_cross_tenant_access

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}CUSTOMER STATUS TESTING COMPLETED!${NC}"
echo -e "${BLUE}==================================================${NC}"

exit 0
