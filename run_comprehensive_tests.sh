#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Set AWS region explicitly
export AWS_DEFAULT_REGION=us-east-1

# Test result tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run a test and track results
run_test() {
    local test_name=$1
    local command=$2
    
    echo -e "\n${BLUE}==================================================${NC}"
    echo -e "${CYAN}RUNNING TEST: ${test_name}${NC}"
    echo -e "${BLUE}==================================================${NC}"
    
    echo -e "${YELLOW}Command: ${command}${NC}"
    
    # Run the command
    eval $command
    local status=$?
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Check result
    if [ $status -eq 0 ]; then
        echo -e "\n${GREEN}✓ TEST PASSED: ${test_name}${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "\n${RED}✗ TEST FAILED: ${test_name}${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    return $status
}

# Main test execution
echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI COMPREHENSIVE TEST SUITE           ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Test tenant isolation
run_test "Tenant Isolation" "./test_tenant_isolation.sh"

# Test multi-tenant pipeline
run_test "Multi-tenant Pipeline" "./test_multi_tenant_pipeline.sh"

# Test customer status
run_test "Customer Status API" "./test_customer_status.sh"

# Test RBAC functionality
run_test "RBAC System" "./test_tenant_rbac_metrics.sh"

# Test knowledge base operations
run_test "Knowledge Base Operations" "cd /Users/adrian/Projects/Cloudable.AI && \
  curl -s -X POST \
  \"$(cd infras/core && terraform output -raw api_endpoint)/api/kb/query\" \
  -H \"Content-Type: application/json\" \
  -H \"x-user-id: user-admin-001\" \
  -d '{\"tenant\":\"acme\",\"query\":\"What is our implementation status?\",\"max_results\":3}' | \
  grep -q \"Implementation\""

# Test chat functionality
run_test "Chat API" "cd /Users/adrian/Projects/Cloudable.AI && \
  curl -s -X POST \
  \"$(cd infras/core && terraform output -raw api_endpoint)/api/chat\" \
  -H \"Content-Type: application/json\" \
  -H \"x-user-id: user-admin-001\" \
  -d '{\"tenant\":\"acme\",\"message\":\"What is our implementation status?\",\"use_kb\":true}' | \
  grep -q \"ACME Corporation\""

# Test document upload URL generation
run_test "Document Upload URL Generation" "cd /Users/adrian/Projects/Cloudable.AI && \
  curl -s -X POST \
  \"$(cd infras/core && terraform output -raw api_endpoint)/api/upload-url\" \
  -H \"Content-Type: application/json\" \
  -H \"x-user-id: user-admin-001\" \
  -d '{\"tenant\":\"acme\",\"filename\":\"test_doc.md\",\"content_type\":\"text/markdown\"}' | \
  grep -q \"url\""

# Test cross-tenant security
run_test "Cross-tenant Security" "cd /Users/adrian/Projects/Cloudable.AI && \
  response=\$(curl -s -X POST \
  \"$(cd infras/core && terraform output -raw api_endpoint)/api/kb/query\" \
  -H \"Content-Type: application/json\" \
  -H \"x-user-id: user-admin-001\" \
  -d '{\"tenant\":\"acme\",\"query\":\"Tell me about Globex implementation status\",\"max_results\":3}') && \
  echo \$response | grep -q \"Information about other organizations is not available\""

# Display test summary
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${BLUE}   TEST SUMMARY                                   ${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "Total tests:  $TOTAL_TESTS"
echo -e "${GREEN}Tests passed: $PASSED_TESTS${NC}"

if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Tests failed: $FAILED_TESTS${NC}"
    EXIT_CODE=1
else
    echo -e "Tests failed: $FAILED_TESTS"
    echo -e "\n${GREEN}✓ ALL TESTS PASSED${NC}"
    EXIT_CODE=0
fi

# Calculate success percentage
if [ $TOTAL_TESTS -gt 0 ]; then
    SUCCESS_PERCENT=$(( PASSED_TESTS * 100 / TOTAL_TESTS ))
    echo -e "Success rate: $SUCCESS_PERCENT%"
fi

echo -e "${BLUE}==================================================${NC}"

# Generate HTML report
cat > test_report.html << EOL
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cloudable.AI Comprehensive Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; color: #333; }
        .header { background-color: #0066cc; color: white; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; padding: 15px; background-color: #f0f0f0; border-radius: 5px; }
        .pass { color: #2e8b57; }
        .fail { color: #cc0000; }
        .test-list { margin: 20px 0; }
        .test-item { padding: 10px; border-bottom: 1px solid #ddd; }
        .test-name { font-weight: bold; }
        .progress-container { width: 100%; background-color: #e0e0e0; border-radius: 5px; }
        .progress-bar { height: 20px; border-radius: 5px; text-align: center; color: white; font-weight: bold; line-height: 20px; }
        footer { margin-top: 30px; text-align: center; font-size: 0.8em; color: #777; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Cloudable.AI Comprehensive Test Report</h1>
        <p>Generated on $(date)</p>
    </div>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <p><strong>Total Tests:</strong> $TOTAL_TESTS</p>
        <p><strong>Tests Passed:</strong> <span class="pass">$PASSED_TESTS</span></p>
        <p><strong>Tests Failed:</strong> <span class="fail">$FAILED_TESTS</span></p>
        
        <div class="progress-container">
            <div class="progress-bar" style="width: ${SUCCESS_PERCENT}%; background-color: $([ $FAILED_TESTS -gt 0 ] && echo '#cc0000' || echo '#2e8b57');">${SUCCESS_PERCENT}%</div>
        </div>
    </div>
    
    <div class="test-list">
        <h2>Test Details</h2>
        
        <div class="test-item">
            <p class="test-name">Tenant Isolation</p>
            <p>Verified that tenant data is properly isolated and secured</p>
        </div>
        
        <div class="test-item">
            <p class="test-name">Multi-tenant Pipeline</p>
            <p>Tested full document upload, processing, and querying pipeline with multi-tenant support</p>
        </div>
        
        <div class="test-item">
            <p class="test-name">Customer Status API</p>
            <p>Verified the new customer status tracking functionality with RDS integration and Bedrock summarization</p>
        </div>
        
        <div class="test-item">
            <p class="test-name">RBAC System</p>
            <p>Tested role-based access control with different user permissions</p>
        </div>
        
        <div class="test-item">
            <p class="test-name">Knowledge Base Operations</p>
            <p>Verified knowledge base querying functionality</p>
        </div>
        
        <div class="test-item">
            <p class="test-name">Chat API</p>
            <p>Tested chat functionality with knowledge base integration</p>
        </div>
        
        <div class="test-item">
            <p class="test-name">Document Upload URL Generation</p>
            <p>Verified secure presigned URL generation for document uploads</p>
        </div>
        
        <div class="test-item">
            <p class="test-name">Cross-tenant Security</p>
            <p>Tested that cross-tenant access attempts are properly blocked</p>
        </div>
    </div>
    
    <footer>
        <p>Cloudable.AI - Multi-tenant platform with vector search, customer status tracking, and AI-powered insights</p>
    </footer>
</body>
</html>
EOL

echo -e "${GREEN}Generated test report: $(pwd)/test_report.html${NC}"

exit $EXIT_CODE
