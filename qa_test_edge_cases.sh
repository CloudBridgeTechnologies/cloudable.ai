#!/bin/bash
# QA Test for Edge Cases and Error Handling

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
REGION="us-east-1"
TENANT="t001"
CUSTOMER_ID="edge-test-$(date +%s)"
KB_MANAGER_FUNCTION="kb-manager-dev"
TIMESTAMP=$(date +%Y%m%d%H%M%S)

# Function to test a Lambda invocation and validate error handling
test_case() {
    local name=$1
    local path=$2
    local payload=$3
    local expected_code=$4
    local function_name=$5
    
    echo -e "\n${BLUE}TEST CASE: ${name}${NC}"
    echo -e "${YELLOW}Invoking Lambda with payload: ${payload}${NC}"
    
    # Create a temporary file for the response
    RESPONSE_FILE="/tmp/lambda_response_${TIMESTAMP}_${name// /_}.json"
    
    # Invoke the Lambda function
    aws lambda invoke \
      --function-name ${function_name} \
      --payload "{\"path\": \"${path}\", \"httpMethod\": \"POST\", \"body\": ${payload}}" \
      --cli-binary-format raw-in-base64-out \
      --region ${REGION} \
      ${RESPONSE_FILE} > /dev/null
    
    # Get the Lambda response
    RESPONSE=$(cat ${RESPONSE_FILE})
    STATUS_CODE=$(echo ${RESPONSE} | jq -r '.statusCode // 0')
    
    # Print response details
    echo -e "Response status code: ${STATUS_CODE}"
    echo -e "Response body: $(echo ${RESPONSE} | jq -r '.body')"
    
    # Check if the status code matches the expected code
    if [ "${STATUS_CODE}" -eq "${expected_code}" ]; then
        echo -e "${GREEN}✓ Test passed: Got expected status code ${expected_code}${NC}"
        return 0
    else
        echo -e "${RED}✗ Test failed: Expected status code ${expected_code}, got ${STATUS_CODE}${NC}"
        return 1
    fi
}

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}  CLOUDABLE.AI EDGE CASES & ERROR HANDLING TESTS  ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Initialize counters
PASSED=0
FAILED=0
TOTAL=0

# Test case 1: Missing tenant ID
echo -e "\n${YELLOW}1. Testing error handling for missing tenant ID...${NC}"
test_case "Missing tenant ID" "/kb/upload-url" "{\"filename\":\"test.md\"}" 400 ${KB_MANAGER_FUNCTION}
if [ $? -eq 0 ]; then
    ((PASSED++))
else
    ((FAILED++))
fi
((TOTAL++))

# Test case 2: Invalid tenant ID format
echo -e "\n${YELLOW}2. Testing error handling for invalid tenant ID format...${NC}"
test_case "Invalid tenant ID" "/kb/upload-url" "{\"tenant_id\":\"123-456-789!@#\",\"filename\":\"test.md\"}" 400 ${KB_MANAGER_FUNCTION}
if [ $? -eq 0 ]; then
    ((PASSED++))
else
    ((FAILED++))
fi
((TOTAL++))

# Test case 3: Missing filename
echo -e "\n${YELLOW}3. Testing error handling for missing filename...${NC}"
test_case "Missing filename" "/kb/upload-url" "{\"tenant_id\":\"${TENANT}\"}" 400 ${KB_MANAGER_FUNCTION}
if [ $? -eq 0 ]; then
    ((PASSED++))
else
    ((FAILED++))
fi
((TOTAL++))

# Test case 4: Invalid document key for sync
echo -e "\n${YELLOW}4. Testing error handling for invalid document key...${NC}"
test_case "Invalid document key" "/kb/sync" "{\"tenant_id\":\"${TENANT}\",\"document_key\":\"invalid/key\"}" 500 ${KB_MANAGER_FUNCTION}
if [ $? -eq 0 ]; then
    ((PASSED++))
else
    ((FAILED++))
fi
((TOTAL++))

# Test case 5: Empty query
echo -e "\n${YELLOW}5. Testing error handling for empty query...${NC}"
test_case "Empty query" "/kb/query" "{\"tenant_id\":\"${TENANT}\",\"customer_id\":\"${CUSTOMER_ID}\",\"query\":\"\"}" 400 ${KB_MANAGER_FUNCTION}
if [ $? -eq 0 ]; then
    ((PASSED++))
else
    ((FAILED++))
fi
((TOTAL++))

# Test case 6: Very long query
echo -e "\n${YELLOW}6. Testing error handling for very long query...${NC}"
LONG_QUERY=$(printf 'a%.0s' {1..2000})  # 2000 'a' characters
test_case "Very long query" "/kb/query" "{\"tenant_id\":\"${TENANT}\",\"customer_id\":\"${CUSTOMER_ID}\",\"query\":\"${LONG_QUERY}\"}" 400 ${KB_MANAGER_FUNCTION}
if [ $? -eq 0 ]; then
    ((PASSED++))
else
    ((FAILED++))
fi
((TOTAL++))

# Test case 7: Nonexistent endpoint
echo -e "\n${YELLOW}7. Testing error handling for nonexistent endpoint...${NC}"
test_case "Nonexistent endpoint" "/nonexistent" "{\"tenant_id\":\"${TENANT}\"}" 404 ${KB_MANAGER_FUNCTION}
if [ $? -eq 0 ]; then
    ((PASSED++))
else
    ((FAILED++))
fi
((TOTAL++))

# Test case 8: Malformed JSON
echo -e "\n${YELLOW}8. Testing error handling for malformed JSON...${NC}"
test_case "Malformed JSON" "/kb/upload-url" "{tenant_id:${TENANT},filename:test.md}" 400 ${KB_MANAGER_FUNCTION}
if [ $? -eq 0 ]; then
    ((PASSED++))
else
    ((FAILED++))
fi
((TOTAL++))

# Test case 9: Extremely short query
echo -e "\n${YELLOW}9. Testing error handling for extremely short query...${NC}"
test_case "Extremely short query" "/kb/query" "{\"tenant_id\":\"${TENANT}\",\"customer_id\":\"${CUSTOMER_ID}\",\"query\":\"a\"}" 400 ${KB_MANAGER_FUNCTION}
if [ $? -eq 0 ]; then
    ((PASSED++))
else
    ((FAILED++))
fi
((TOTAL++))

# Test case 10: Invalid customer ID
echo -e "\n${YELLOW}10. Testing error handling for invalid customer ID...${NC}"
test_case "Invalid customer ID" "/kb/query" "{\"tenant_id\":\"${TENANT}\",\"customer_id\":\"invalid!@#\",\"query\":\"test query\"}" 400 ${KB_MANAGER_FUNCTION}
if [ $? -eq 0 ]; then
    ((PASSED++))
else
    ((FAILED++))
fi
((TOTAL++))

# Clean up response files
rm -f /tmp/lambda_response_${TIMESTAMP}_*.json

# Print test summary
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${BLUE}                 TEST SUMMARY                     ${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "Total tests:   ${TOTAL}"
echo -e "${GREEN}Tests passed:  ${PASSED}${NC}"
if [ ${FAILED} -gt 0 ]; then
    echo -e "${RED}Tests failed:  ${FAILED}${NC}"
fi

SUCCESS_RATE=$((PASSED * 100 / TOTAL))
echo -e "Success rate:  ${SUCCESS_RATE}%"

if [ ${FAILED} -eq 0 ]; then
    echo -e "\n${GREEN}All error handling tests passed successfully!${NC}"
else
    echo -e "\n${RED}Some error handling tests failed. Review logs for details.${NC}"
fi

echo -e "${BLUE}==================================================${NC}"

# Exit with appropriate status code
if [ ${FAILED} -eq 0 ]; then
    exit 0
else
    exit 1
fi
