#!/bin/bash

# Corrected API Test Script for Cloudable.AI
# Tests all APIs with correct request formats and correct API endpoints

set -e

# Variables
TENANT="acme"
CUSTOMER_ID="test-customer"
REGION="us-east-1"
SECURE_API_ID="pdoq719mx2"  # REST API ID
API_KEY="sZI5RibzbE2WY1kRw4zcX1iSXhSnIqAoauc2XezS"
REST_API_URL="https://${SECURE_API_ID}.execute-api.${REGION}.amazonaws.com/dev"  # REST API
CHAT_API_ID="2tol4asisa"  # HTTP API ID
HTTP_API_URL="https://${CHAT_API_ID}.execute-api.${REGION}.amazonaws.com/dev"  # HTTP API (with /dev stage)
TIMESTAMP=$(date +%Y%m%d%H%M%S)

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}     CLOUDABLE.AI API TESTING SCRIPT      ${NC}"
echo -e "${BLUE}===========================================${NC}"

# 1. KB Query API Test (HTTP API)
echo -e "\n${YELLOW}1. Testing KB Query API (HTTP API)...${NC}"
# Based on the code, it requires tenant_id, customer_id, and query
cat << EOF > kb_query.json
{
  "tenant_id": "${TENANT}",
  "customer_id": "${CUSTOMER_ID}",
  "query": "What are the key features of Cloudable.AI?"
}
EOF

echo -e "${YELLOW}Request payload:${NC}"
cat kb_query.json

KB_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d @kb_query.json \
  ${HTTP_API_URL}/kb/query || echo "Request failed")

echo -e "${GREEN}✓ KB Query API Response:${NC}"
echo "$KB_RESPONSE" | jq . 2>/dev/null || echo "$KB_RESPONSE"

# 2. Upload URL API Test (HTTP API)
echo -e "\n${YELLOW}2. Testing Upload URL API (HTTP API)...${NC}"
# Based on the code, it requires tenant_id and filename
cat << EOF > upload_url.json
{
  "tenant_id": "${TENANT}",
  "filename": "api_test_doc_${TIMESTAMP}.md"
}
EOF

echo -e "${YELLOW}Request payload:${NC}"
cat upload_url.json

UPLOAD_URL_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d @upload_url.json \
  ${HTTP_API_URL}/kb/upload-url || echo "Request failed")

echo -e "${GREEN}✓ Upload URL API Response:${NC}"
echo "$UPLOAD_URL_RESPONSE" | jq . 2>/dev/null || echo "$UPLOAD_URL_RESPONSE"

# 3. KB Sync API Test (HTTP API)
echo -e "\n${YELLOW}3. Testing KB Sync API (HTTP API)...${NC}"
# Based on the code, it requires tenant_id and document_key
cat << EOF > kb_sync.json
{
  "tenant_id": "${TENANT}",
  "document_key": "documents/test_document.md"
}
EOF

echo -e "${YELLOW}Request payload:${NC}"
cat kb_sync.json

SYNC_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d @kb_sync.json \
  ${HTTP_API_URL}/kb/sync || echo "Request failed")

echo -e "${GREEN}✓ KB Sync API Response:${NC}"
echo "$SYNC_RESPONSE" | jq . 2>/dev/null || echo "$SYNC_RESPONSE"

# 4. KB Ingestion Status API Test (HTTP API)
echo -e "\n${YELLOW}4. Testing KB Ingestion Status API (HTTP API)...${NC}"
# Based on the code, it requires tenant_id and ingestion_job_id
cat << EOF > ingestion_status.json
{
  "tenant_id": "${TENANT}",
  "ingestion_job_id": "test-job-id"
}
EOF

echo -e "${YELLOW}Request payload:${NC}"
cat ingestion_status.json

STATUS_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d @ingestion_status.json \
  ${HTTP_API_URL}/kb/ingestion-status || echo "Request failed")

echo -e "${GREEN}✓ KB Ingestion Status API Response:${NC}"
echo "$STATUS_RESPONSE" | jq . 2>/dev/null || echo "$STATUS_RESPONSE"

# 5. Chat API Test (HTTP API)
echo -e "\n${YELLOW}5. Testing Chat API (HTTP API)...${NC}"
# The chat API likely requires a different format
cat << EOF > chat_query.json
{
  "tenant_id": "${TENANT}",
  "customer_id": "${CUSTOMER_ID}",
  "message": "What is Cloudable.AI about?",
  "conversation_id": "test-${TIMESTAMP}"
}
EOF

echo -e "${YELLOW}Request payload:${NC}"
cat chat_query.json

CHAT_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d @chat_query.json \
  ${HTTP_API_URL}/chat || echo "Request failed")

echo -e "${GREEN}✓ Chat API Response:${NC}"
echo "$CHAT_RESPONSE" | jq . 2>/dev/null || echo "$CHAT_RESPONSE"

# 6. Summary API Test (REST API)
echo -e "\n${YELLOW}6. Testing Summary API (REST API)...${NC}"
SUMMARY_RESPONSE=$(curl -s -X GET \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  ${REST_API_URL}/summary/${TENANT}/test_document || echo "Request failed")

echo -e "${GREEN}✓ Summary API Response:${NC}"
echo "$SUMMARY_RESPONSE" | jq . 2>/dev/null || echo "$SUMMARY_RESPONSE"

echo -e "\n${BLUE}===========================================${NC}"
echo -e "${BLUE}         API TESTING COMPLETED            ${NC}"
echo -e "${BLUE}===========================================${NC}"
