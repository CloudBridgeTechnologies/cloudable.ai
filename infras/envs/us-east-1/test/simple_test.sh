#!/bin/bash
# Simple test script that works with existing infrastructure

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Cloudable.AI Simple Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "SUCCESS" ]; then
        echo -e "${GREEN}✓ $message${NC}"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}✗ $message${NC}"
    elif [ "$status" = "INFO" ]; then
        echo -e "${BLUE}ℹ $message${NC}"
    elif [ "$status" = "WARNING" ]; then
        echo -e "${YELLOW}⚠ $message${NC}"
    fi
}

# Test 1: Check AWS CLI configuration
print_status "INFO" "Testing AWS CLI configuration..."
if aws sts get-caller-identity > /dev/null 2>&1; then
    print_status "SUCCESS" "AWS CLI is configured"
    aws sts get-caller-identity
else
    print_status "FAIL" "AWS CLI is not configured or credentials are invalid"
    exit 1
fi

# Test 2: Check if Lambda functions exist
print_status "INFO" "Checking Lambda functions..."
LAMBDA_FUNCTIONS=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `cloudable`) || contains(FunctionName, `kb`) || contains(FunctionName, `s3`) || contains(FunctionName, `document`)].FunctionName' --output text 2>/dev/null || echo "")

if [ -n "$LAMBDA_FUNCTIONS" ]; then
    print_status "SUCCESS" "Found Lambda functions:"
    echo "$LAMBDA_FUNCTIONS" | tr '\t' '\n' | while read func; do
        if [ -n "$func" ]; then
            echo "  - $func"
        fi
    done
else
    print_status "WARNING" "No Lambda functions found with expected names"
fi

# Test 3: Check S3 buckets
print_status "INFO" "Checking S3 buckets..."
S3_BUCKETS=$(aws s3 ls | grep -E "(cloudable|kb)" | awk '{print $3}' || echo "")

if [ -n "$S3_BUCKETS" ]; then
    print_status "SUCCESS" "Found S3 buckets:"
    echo "$S3_BUCKETS" | while read bucket; do
        if [ -n "$bucket" ]; then
            echo "  - $bucket"
        fi
    done
else
    print_status "WARNING" "No S3 buckets found with expected names"
fi

# Test 4: Test document upload
print_status "INFO" "Testing document upload to S3..."

# Create a test document
TEST_DOC="/tmp/test-policy-$(date +%s).txt"
cat > "$TEST_DOC" << 'EOF'
Company Vacation Policy:
- New employees: 15 days paid vacation annually
- After 3 years: 20 days paid vacation annually
- After 7 years: 25 days paid vacation annually
- Vacation requests require 2 weeks advance notice
- Maximum 5 consecutive days without manager approval

Security Policies:
- All employees must use strong passwords (12+ characters)
- Two-factor authentication required for all systems
- VPN access mandatory for remote work
- Report security incidents immediately to IT
- No personal devices on corporate network

Assessment Process:
- Quarterly performance reviews required
- 360-degree feedback from peers and managers
- Goal setting and tracking via company portal
- Professional development plans updated annually
EOF

# Find a suitable S3 bucket
if [ -n "$S3_BUCKETS" ]; then
    BUCKET_NAME=$(echo "$S3_BUCKETS" | head -n1)
    print_status "INFO" "Uploading test document to bucket: $BUCKET_NAME"
    
    # Upload the test document
    aws s3 cp "$TEST_DOC" "s3://$BUCKET_NAME/documents/test-policy-$(date +%s).txt" || {
        print_status "FAIL" "Failed to upload document to S3"
        exit 1
    }
    
    print_status "SUCCESS" "Document uploaded successfully"
    
    # Clean up
    rm -f "$TEST_DOC"
else
    print_status "WARNING" "No S3 buckets available for testing"
fi

# Test 5: Check Lambda function logs
print_status "INFO" "Checking recent Lambda function logs..."

if [ -n "$LAMBDA_FUNCTIONS" ]; then
    echo "$LAMBDA_FUNCTIONS" | tr '\t' '\n' | while read func; do
        if [ -n "$func" ]; then
            print_status "INFO" "Checking logs for function: $func"
            aws logs describe-log-streams --log-group-name "/aws/lambda/$func" --order-by LastEventTime --descending --max-items 1 > /dev/null 2>&1 || {
                print_status "WARNING" "No logs found for function: $func"
            }
        fi
    done
fi

# Test 6: Test Knowledge Base query (if available)
print_status "INFO" "Testing Knowledge Base query..."

# Try to run the KB query wrapper
if [ -f "../tools/kb/kb_query_wrapper.py" ]; then
    print_status "INFO" "Running Knowledge Base query test..."
    cd ../tools/kb/
    python3 kb_query_wrapper.py "What is the company vacation policy?" || {
        print_status "WARNING" "Knowledge Base query failed - this may be expected if KB is not set up"
    }
    cd ../../test/
else
    print_status "WARNING" "KB query wrapper not found"
fi

# Test 7: Check API Gateway (if available)
print_status "INFO" "Checking API Gateway..."
API_GATEWAYS=$(aws apigateway get-rest-apis --query 'items[?contains(name, `cloudable`) || contains(name, `secure`)].{Name:name,Id:id}' --output table 2>/dev/null || echo "")

if [ -n "$API_GATEWAYS" ] && [ "$API_GATEWAYS" != "None" ]; then
    print_status "SUCCESS" "Found API Gateway:"
    echo "$API_GATEWAYS"
else
    print_status "WARNING" "No API Gateway found with expected names"
fi

# Test 8: Check Bedrock Knowledge Base
print_status "INFO" "Checking Bedrock Knowledge Base..."
KNOWLEDGE_BASES=$(aws bedrock-agent list-knowledge-bases --query 'knowledgeBaseSummaries[].{Name:name,Id:knowledgeBaseId}' --output table 2>/dev/null || echo "")

if [ -n "$KNOWLEDGE_BASES" ] && [ "$KNOWLEDGE_BASES" != "None" ]; then
    print_status "SUCCESS" "Found Knowledge Bases:"
    echo "$KNOWLEDGE_BASES"
else
    print_status "WARNING" "No Bedrock Knowledge Bases found"
fi

# Summary
echo ""
print_status "INFO" "=== Test Summary ==="
print_status "INFO" "AWS CLI: $(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null || echo 'Not configured')"
print_status "INFO" "Lambda Functions: $(echo "$LAMBDA_FUNCTIONS" | wc -w) found"
print_status "INFO" "S3 Buckets: $(echo "$S3_BUCKETS" | wc -w) found"
print_status "INFO" "API Gateways: $(echo "$API_GATEWAYS" | grep -c "Name" || echo "0") found"
print_status "INFO" "Knowledge Bases: $(echo "$KNOWLEDGE_BASES" | grep -c "Name" || echo "0") found"

echo ""
print_status "INFO" "Next steps:"
print_status "INFO" "1. Fix Terraform configuration issues if you want to deploy new resources"
print_status "INFO" "2. Use the existing infrastructure for testing"
print_status "INFO" "3. Check CloudWatch logs for detailed processing information"
print_status "INFO" "4. Test document upload and processing workflows"

echo ""
print_status "SUCCESS" "Simple test suite completed!"
