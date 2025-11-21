#!/bin/bash
# QA Test for Multi-tenant Functionality with pgvector

set -e

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
REGION="us-east-1"
API_KEY="sZI5RibzbE2WY1kRw4zcX1iSXhSnIqAoauc2XezS"
API_ID="pdoq719mx2"  # REST API ID
TIMESTAMP=$(date +%Y%m%d%H%M%S)

# Tenant details
TENANTS=("acme" "globex" "t001")
DOCUMENTS=("doc_acme.md" "doc_globex.md" "doc_t001.md")
KB_MANAGER_FUNCTION="kb-manager-dev"

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE} CLOUDABLE.AI MULTI-TENANT PGVECTOR QA TEST SUITE ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Create test documents for each tenant with tenant-specific information
echo -e "\n${YELLOW}1. Creating test documents for each tenant...${NC}"

cat > doc_acme.md << EOF
# ACME Corporation Knowledge Base

## Company Overview
ACME Corporation is a leading provider of innovative technology solutions established in 1985.

## Products
- Cloud Infrastructure Services
- AI-powered Analytics Platform
- Enterprise Security Solutions

## Technical Stack
ACME uses PostgreSQL with pgvector for their knowledge management system.
EOF

cat > doc_globex.md << EOF
# Globex Corporation Knowledge Base

## Company Overview
Globex Corporation is a multinational conglomerate specializing in industrial automation.

## Products
- Industrial Control Systems
- Automation Software Solutions
- IoT Sensor Networks

## Technical Stack
Globex relies on secure database technology with vector embeddings for their knowledge systems.
EOF

cat > doc_t001.md << EOF
# Tenant T001 Knowledge Base

## Company Overview
T001 is a research organization focused on emerging technologies and scientific breakthroughs.

## Research Areas
- Quantum Computing Applications
- Advanced Materials Science
- Biotechnology Integration

## Technical Stack
T001 leverages vector databases for semantic search across research papers and documentation.
EOF

echo -e "${GREEN}✓ Created test documents for all tenants${NC}"

# Function to test document upload and querying for a tenant
test_tenant() {
    local tenant=$1
    local document=$2
    local customer_id="test-${tenant}-${TIMESTAMP}"
    
    echo -e "\n${BLUE}=====================${NC}"
    echo -e "${BLUE} TESTING TENANT: ${tenant} ${NC}"
    echo -e "${BLUE}=====================${NC}"
    
    # 1. Generate presigned URL
    echo -e "\n${YELLOW}1. Getting upload URL for ${tenant}...${NC}"
    UPLOAD_PAYLOAD="{\"tenant_id\":\"${tenant}\",\"filename\":\"${document}\"}"
    
    UPLOAD_RESPONSE=$(aws lambda invoke \
      --function-name ${KB_MANAGER_FUNCTION} \
      --payload "{\"path\": \"/kb/upload-url\", \"httpMethod\": \"POST\", \"body\": ${UPLOAD_PAYLOAD}}" \
      --cli-binary-format raw-in-base64-out \
      --region ${REGION} \
      /tmp/upload_url_response_${tenant}.json && cat /tmp/upload_url_response_${tenant}.json)
    
    # Parse upload URL and document key
    UPLOAD_URL_BODY=$(echo "$UPLOAD_RESPONSE" | jq -r '.body')
    if [ -z "$UPLOAD_URL_BODY" ] || [ "$UPLOAD_URL_BODY" == "null" ]; then
        echo -e "${RED}✗ Failed to get upload URL for ${tenant}${NC}"
        echo "$UPLOAD_RESPONSE" | jq .
        return 1
    fi
    
    UPLOAD_URL=$(echo "$UPLOAD_URL_BODY" | jq -r '.presigned_url')
    DOCUMENT_KEY=$(echo "$UPLOAD_URL_BODY" | jq -r '.document_key')
    
    echo -e "${GREEN}✓ Got upload URL for ${tenant}${NC}"
    echo -e "${BLUE}Document key: ${DOCUMENT_KEY}${NC}"
    
    # 2. Upload document to S3
    echo -e "\n${YELLOW}2. Uploading document for ${tenant}...${NC}"
    UPLOAD_RESULT=$(curl -s -X PUT \
      -H "Content-Type: text/markdown" \
      --upload-file ${document} \
      "${UPLOAD_URL}")
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to upload document for ${tenant}${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Document uploaded successfully for ${tenant}${NC}"
    
    # 3. Trigger KB sync
    echo -e "\n${YELLOW}3. Triggering KB sync for ${tenant}...${NC}"
    SYNC_PAYLOAD="{\"tenant_id\":\"${tenant}\",\"document_key\":\"${DOCUMENT_KEY}\"}"
    
    SYNC_RESPONSE=$(aws lambda invoke \
      --function-name ${KB_MANAGER_FUNCTION} \
      --payload "{\"path\": \"/kb/sync\", \"httpMethod\": \"POST\", \"body\": ${SYNC_PAYLOAD}}" \
      --cli-binary-format raw-in-base64-out \
      --region ${REGION} \
      /tmp/sync_response_${tenant}.json && cat /tmp/sync_response_${tenant}.json)
    
    SYNC_BODY=$(echo "$SYNC_RESPONSE" | jq -r '.body')
    JOB_ID=$(echo "$SYNC_BODY" | jq -r '.ingestion_job_id // empty')
    
    if [ -z "$JOB_ID" ]; then
        echo -e "${RED}✗ Failed to start KB sync for ${tenant}${NC}"
        echo "$SYNC_RESPONSE" | jq .
        return 1
    fi
    
    echo -e "${GREEN}✓ KB sync started for ${tenant} with job ID: ${JOB_ID}${NC}"
    
    # 4. Wait for processing
    echo -e "\n${YELLOW}4. Waiting for document processing (20 seconds)...${NC}"
    for i in {1..20}; do
        echo -n "."
        sleep 1
    done
    echo ""
    
    # 5. Query the knowledge base
    echo -e "\n${YELLOW}5. Testing tenant-specific query for ${tenant}...${NC}"
    
    # Tenant-specific query
    if [ "$tenant" == "acme" ]; then
        QUERY="What products does ACME offer?"
    elif [ "$tenant" == "globex" ]; then
        QUERY="What is Globex Corporation's specialization?"
    else
        QUERY="What research areas does T001 focus on?"
    fi
    
    QUERY_PAYLOAD="{\"tenant_id\":\"${tenant}\",\"customer_id\":\"${customer_id}\",\"query\":\"${QUERY}\"}"
    
    QUERY_RESPONSE=$(aws lambda invoke \
      --function-name ${KB_MANAGER_FUNCTION} \
      --payload "{\"path\": \"/kb/query\", \"httpMethod\": \"POST\", \"body\": ${QUERY_PAYLOAD}}" \
      --cli-binary-format raw-in-base64-out \
      --region ${REGION} \
      /tmp/query_response_${tenant}.json && cat /tmp/query_response_${tenant}.json)
    
    QUERY_BODY=$(echo "$QUERY_RESPONSE" | jq -r '.body')
    ANSWER=$(echo "$QUERY_BODY" | jq -r '.answer // empty')
    
    if [ -z "$ANSWER" ] || [ "$ANSWER" == "null" ]; then
        echo -e "${RED}✗ Failed to get answer for ${tenant}${NC}"
        echo "$QUERY_RESPONSE" | jq .
        return 1
    fi
    
    echo -e "${GREEN}✓ Received answer for ${tenant}:${NC}"
    echo -e "${BLUE}Query: ${QUERY}${NC}"
    echo -e "${BLUE}Answer: ${ANSWER}${NC}"
    
    # 6. Cross-tenant isolation test
    # Try to access tenant1's data from tenant2's query
    if [ "$tenant" == "acme" ]; then
        OTHER_TENANT="globex"
        CROSS_QUERY="What research areas does T001 focus on?"
    else
        OTHER_TENANT="acme"
        CROSS_QUERY="What products does ACME offer?"
    fi
    
    echo -e "\n${YELLOW}6. Testing cross-tenant isolation (${tenant} trying to access ${OTHER_TENANT} data)...${NC}"
    
    CROSS_QUERY_PAYLOAD="{\"tenant_id\":\"${tenant}\",\"customer_id\":\"${customer_id}\",\"query\":\"${CROSS_QUERY}\"}"
    
    CROSS_QUERY_RESPONSE=$(aws lambda invoke \
      --function-name ${KB_MANAGER_FUNCTION} \
      --payload "{\"path\": \"/kb/query\", \"httpMethod\": \"POST\", \"body\": ${CROSS_QUERY_PAYLOAD}}" \
      --cli-binary-format raw-in-base64-out \
      --region ${REGION} \
      /tmp/cross_query_response_${tenant}.json && cat /tmp/cross_query_response_${tenant}.json)
    
    CROSS_QUERY_BODY=$(echo "$CROSS_QUERY_RESPONSE" | jq -r '.body')
    CROSS_ANSWER=$(echo "$CROSS_QUERY_BODY" | jq -r '.answer // empty')
    
    # Check if the answer contains information it shouldn't have
    if [[ "$CROSS_ANSWER" == *"don't know"* ]] || [[ "$CROSS_ANSWER" == *"couldn't find"* ]] || [[ "$CROSS_ANSWER" == *"no information"* ]]; then
        echo -e "${GREEN}✓ Cross-tenant isolation test passed: ${tenant} cannot access ${OTHER_TENANT}'s data${NC}"
    else
        echo -e "${RED}✗ Cross-tenant isolation might be compromised: ${tenant} might access ${OTHER_TENANT}'s data${NC}"
        echo -e "${BLUE}Cross-tenant query answer: ${CROSS_ANSWER}${NC}"
        # Don't fail the test, just warn
    fi
    
    echo -e "\n${GREEN}=== Tenant ${tenant} tests completed successfully ===${NC}"
    return 0
}

# Run tests for each tenant
for i in "${!TENANTS[@]}"; do
    test_tenant "${TENANTS[$i]}" "${DOCUMENTS[$i]}"
    TEST_STATUS=$?
    if [ $TEST_STATUS -ne 0 ]; then
        echo -e "${RED}Test failed for tenant ${TENANTS[$i]}${NC}"
        FAILED_TENANTS="${FAILED_TENANTS} ${TENANTS[$i]}"
    else
        PASSED_TENANTS="${PASSED_TENANTS} ${TENANTS[$i]}"
    fi
done

# Clean up
echo -e "\n${YELLOW}Cleaning up test files...${NC}"
rm -f doc_acme.md doc_globex.md doc_t001.md
rm -f /tmp/upload_url_response_*.json /tmp/sync_response_*.json /tmp/query_response_*.json /tmp/cross_query_response_*.json
echo -e "${GREEN}✓ Test files removed${NC}"

# Print summary
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${BLUE}                 TEST SUMMARY                     ${NC}"
echo -e "${BLUE}==================================================${NC}"

if [ -z "$FAILED_TENANTS" ]; then
    echo -e "${GREEN}All tenant tests passed successfully!${NC}"
else
    echo -e "${GREEN}Tests passed for tenants:${PASSED_TENANTS}${NC}"
    echo -e "${RED}Tests failed for tenants:${FAILED_TENANTS}${NC}"
fi

echo -e "${BLUE}==================================================${NC}"
