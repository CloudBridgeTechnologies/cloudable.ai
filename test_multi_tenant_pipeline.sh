#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Set AWS region explicitly
export AWS_DEFAULT_REGION=us-east-1

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI MULTI-TENANT PIPELINE TEST        ${NC}"
echo -e "${BLUE}==================================================${NC}"

# API Gateway endpoint
API_ENDPOINT="https://xn66ohjpw1.execute-api.us-east-1.amazonaws.com/dev"

# Tenants to test
TENANTS=("acme" "globex")

# Test users with different roles
USER_ADMIN="user-admin-001"    # admin role
USER_READER="user-reader-001"  # reader role
USER_WRITER="user-writer-001"  # contributor role

# Create temporary test directory
TEST_DIR=$(mktemp -d)
echo -e "${YELLOW}Created temporary directory: ${TEST_DIR}${NC}"

# Function to test the full pipeline for a tenant
test_tenant_pipeline() {
    local tenant=$1
    local user_id=$2
    
    echo -e "\n${BLUE}==================================================${NC}"
    echo -e "${BLUE}   TESTING PIPELINE FOR TENANT: ${tenant}       ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    
    # 1. Create a test document with some tenant-specific content
    echo -e "\n${YELLOW}Step 1: Creating test document for ${tenant}${NC}"
    local timestamp=$(date +"%Y%m%d%H%M%S")
    local doc_name="${tenant}_test_document_${timestamp}.md"
    local doc_path="${TEST_DIR}/${doc_name}"
    
    # Create content based on tenant
    if [ "$tenant" = "acme" ]; then
        cat > "$doc_path" << EOF
# ACME Corporation Customer Journey

## Current Status
ACME Corporation is currently in the Implementation stage (phase 3 of 5), with a projected completion date of December 10, 2025.

## Completed Milestones
- Cloud-based ERP system integration
- Customer data platform with AI-powered analytics
- Automated order processing workflow

## Next Steps
- Complete supply chain module by November 30
- Schedule field service training for December
- Prepare final phase deployment plan by November 25

## Success Metrics
Success metrics include 30% reduction in order processing time (currently at 18%), 25% improvement in inventory accuracy (currently at 20%), and 15% increase in customer satisfaction (currently at 8%).
EOF
    else
        cat > "$doc_path" << EOF
# Globex Industries Customer Journey

## Current Status
Globex Industries is currently in the Onboarding stage (phase 1 of 4), with implementation having started on October 2, 2025 and expected completion by June 15, 2026.

## Key Stakeholders
Key stakeholders at Globex include Thomas Wong (CTO), Aisha Patel (CDO), Robert Martinez (Customer Experience), and Jennifer Lee (Compliance Director).

## Risk Factors
Implementation risks for Globex include multiple legacy systems requiring complex integration, strict regulatory requirements in financial services, and cross-departmental coordination challenges.

## Company Profile
Globex Industries is a large financial services provider with 2,000+ employees across multiple regions. They're in the early onboarding phase of their digital transformation, focused on customer experience and operational efficiency.
EOF
    fi
    
    echo -e "${GREEN}Created test document: ${doc_path}${NC}"
    echo -e "${GREEN}Content preview:${NC}"
    head -n 3 "$doc_path"
    echo "..."

    # 2. Get presigned URL for document upload
    echo -e "\n${YELLOW}Step 2: Getting presigned URL for document upload${NC}"
    UPLOAD_RESPONSE=$(curl -s -X POST \
      "${API_ENDPOINT}/api/upload-url" \
      -H "Content-Type: application/json" \
      -H "x-user-id: ${user_id}" \
      -d "{\"tenant\":\"${tenant}\",\"filename\":\"${doc_name}\",\"content_type\":\"text/markdown\"}")
    
    echo -e "Upload URL Response: ${UPLOAD_RESPONSE}"
    
    # Parse the response
    UPLOAD_URL=$(echo $UPLOAD_RESPONSE | grep -o '"url": *"[^"]*"' | grep -o 'https://[^"]*')
    S3_KEY=$(echo $UPLOAD_RESPONSE | grep -o '"key": *"[^"]*"' | grep -o '"key": *"[^"]*"' | cut -d'"' -f4)
    S3_BUCKET=$(echo $UPLOAD_RESPONSE | grep -o '"bucket": *"[^"]*"' | grep -o '"bucket": *"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$UPLOAD_URL" ] || [ -z "$S3_KEY" ] || [ -z "$S3_BUCKET" ]; then
        echo -e "${RED}Failed to get presigned URL. Aborting pipeline test for ${tenant}.${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Successfully obtained presigned URL${NC}"
    
    # 3. Upload the document to S3
    echo -e "\n${YELLOW}Step 3: Uploading document to S3${NC}"
    UPLOAD_RESULT=$(curl -s -X PUT -H "Content-Type: text/markdown" --upload-file "$doc_path" "$UPLOAD_URL")
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to upload document to S3. Aborting pipeline test for ${tenant}.${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Successfully uploaded document to S3${NC}"
    echo -e "Document key: ${S3_KEY}"
    echo -e "S3 bucket: ${S3_BUCKET}"
    
    # 4. Trigger KB sync
    echo -e "\n${YELLOW}Step 4: Triggering knowledge base sync${NC}"
    SYNC_RESPONSE=$(curl -s -X POST \
      "${API_ENDPOINT}/api/kb/sync" \
      -H "Content-Type: application/json" \
      -H "x-user-id: ${user_id}" \
      -d "{\"tenant\":\"${tenant}\",\"document_key\":\"${S3_KEY}\"}")
    
    echo -e "KB Sync Response: ${SYNC_RESPONSE}"
    
    if [[ ! "$SYNC_RESPONSE" == *"processing"* ]]; then
        echo -e "${RED}KB sync may have failed. Continuing anyway...${NC}"
    else
        echo -e "${GREEN}✓ KB sync initiated successfully${NC}"
    fi
    
    # Sleep to allow processing time
    echo -e "Waiting 5 seconds for processing..."
    sleep 5
    
    # 5. Query the knowledge base
    echo -e "\n${YELLOW}Step 5: Querying the knowledge base${NC}"
    
    # Pick a tenant-specific query
    local query=""
    if [ "$tenant" = "acme" ]; then
        query="What is ACME's current status and next steps?"
    else
        query="Who are the key stakeholders at Globex?"
    fi
    
    QUERY_RESPONSE=$(curl -s -X POST \
      "${API_ENDPOINT}/api/kb/query" \
      -H "Content-Type: application/json" \
      -H "x-user-id: ${user_id}" \
      -d "{\"tenant\":\"${tenant}\",\"query\":\"${query}\",\"max_results\":3}")
    
    echo -e "KB Query Response:"
    echo -e "${QUERY_RESPONSE}" | grep -v "^\s*$" | head -n 15
    echo "..."
    
    if [[ ! "$QUERY_RESPONSE" == *"results"* ]]; then
        echo -e "${RED}KB query may have failed. Continuing anyway...${NC}"
    else
        echo -e "${GREEN}✓ KB query completed successfully${NC}"
    fi
    
    # 6. Use the chat endpoint with knowledge base integration
    echo -e "\n${YELLOW}Step 6: Testing chat with knowledge base integration${NC}"
    
    # Pick a tenant-specific chat message
    local chat_message=""
    if [ "$tenant" = "acme" ]; then
        chat_message="What success metrics has ACME defined?"
    else
        chat_message="What are the risks for Globex implementation?"
    fi
    
    CHAT_RESPONSE=$(curl -s -X POST \
      "${API_ENDPOINT}/api/chat" \
      -H "Content-Type: application/json" \
      -H "x-user-id: ${user_id}" \
      -d "{\"tenant\":\"${tenant}\",\"message\":\"${chat_message}\",\"use_kb\":true}")
    
    echo -e "Chat Response:"
    echo -e "${CHAT_RESPONSE}" | grep -v "^\s*$" | head -n 15
    echo "..."
    
    if [[ ! "$CHAT_RESPONSE" == *"response"* ]]; then
        echo -e "${RED}Chat query may have failed.${NC}"
    else
        echo -e "${GREEN}✓ Chat query completed successfully${NC}"
    fi
    
    # 7. Cross-tenant test - Try to access other tenant's data
    echo -e "\n${YELLOW}Step 7: Testing tenant isolation (cross-tenant test)${NC}"
    local other_tenant=""
    if [ "$tenant" = "acme" ]; then
        other_tenant="globex"
    else
        other_tenant="acme"
    fi
    
    local cross_query="Tell me about ${other_tenant}'s implementation status"
    
    CROSS_RESPONSE=$(curl -s -X POST \
      "${API_ENDPOINT}/api/kb/query" \
      -H "Content-Type: application/json" \
      -H "x-user-id: ${user_id}" \
      -d "{\"tenant\":\"${tenant}\",\"query\":\"${cross_query}\",\"max_results\":3}")
    
    echo -e "Cross-tenant Query Response:"
    echo -e "${CROSS_RESPONSE}" | grep -v "^\s*$" | head -n 15
    
    # Check if the response contains actual data about the other tenant or the privacy message
    if [[ "$CROSS_RESPONSE" == *"Privacy Policy"* && "$CROSS_RESPONSE" == *"Information about other organizations is not available"* ]]; then
        echo -e "${GREEN}✓ Tenant isolation passed. Access to ${other_tenant}'s data was properly blocked.${NC}"
    elif [[ "$CROSS_RESPONSE" == *"$other_tenant"* && "$CROSS_RESPONSE" != *"Information about other organizations is not available"* ]]; then
        echo -e "${RED}✗ Tenant isolation failed! Found information about ${other_tenant} while querying as ${tenant}.${NC}"
    else
        echo -e "${YELLOW}? Unexpected response in cross-tenant test.${NC}"
    fi
    
    echo -e "\n${GREEN}Pipeline test completed for tenant: ${tenant}${NC}"
}

# Test pipelines for both tenants using different user roles
test_tenant_pipeline "acme" "$USER_ADMIN"
test_tenant_pipeline "globex" "$USER_WRITER"

# Cleanup
echo -e "\n${YELLOW}Cleaning up temporary files...${NC}"
rm -rf "$TEST_DIR"
echo -e "${GREEN}Cleanup complete.${NC}"

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}MULTI-TENANT PIPELINE TEST COMPLETED!${NC}"
echo -e "${BLUE}==================================================${NC}"

exit 0
