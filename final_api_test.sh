#!/bin/bash

# Set variables
TENANT="acme"
REGION="us-east-1"
SECURE_API_ID="pdoq719mx2"
CHAT_API_ID="2tol4asisa"
API_KEY="sZI5RibzbE2WY1kRw4zcX1iSXhSnIqAoauc2XezS"

# API endpoints
SECURE_API_URL="https://${SECURE_API_ID}.execute-api.${REGION}.amazonaws.com/dev"
CHAT_API_URL="https://${CHAT_API_ID}.execute-api.${REGION}.amazonaws.com/dev"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting Final API Testing in ${REGION}${NC}"

# Test endpoints from Secure API (REST)
echo -e "\n${YELLOW}Testing Secure API (REST) endpoints...${NC}"

# Test KB query endpoint with proper format
echo -e "\n${YELLOW}Testing KB query endpoint...${NC}"
echo -e "${YELLOW}Using endpoint:${NC} $SECURE_API_URL/kb/query"

cat << EOF > kb_query.json
{
  "tenant": "$TENANT",
  "query": "What are the key features of Cloudable.AI?",
  "filters": [],
  "limit": 3
}
EOF
echo -e "${YELLOW}Query payload:${NC}"
cat kb_query.json

KB_QUERY_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @kb_query.json \
  ${SECURE_API_URL}/kb/query || echo "Request failed")
echo "$KB_QUERY_RESPONSE"

# Test upload URL endpoint with proper format
echo -e "\n${YELLOW}Testing upload URL endpoint...${NC}"
echo -e "${YELLOW}Using endpoint:${NC} $SECURE_API_URL/kb/upload-url"

cat << EOF > upload_url.json
{
  "tenant": "$TENANT",
  "filename": "test_document.md",
  "content_type": "text/markdown"
}
EOF
echo -e "${YELLOW}Upload URL payload:${NC}"
cat upload_url.json

UPLOAD_URL_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @upload_url.json \
  ${SECURE_API_URL}/kb/upload-url || echo "Request failed")
echo "$UPLOAD_URL_RESPONSE"

# Test summary endpoint
echo -e "\n${YELLOW}Testing summary endpoint...${NC}"
echo -e "${YELLOW}Using endpoint:${NC} $SECURE_API_URL/summary/$TENANT/test_document"
SUMMARY_RESPONSE=$(curl -s -X GET \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  ${SECURE_API_URL}/summary/$TENANT/test_document || echo "Request failed")
echo "$SUMMARY_RESPONSE"

# Test Chat API (HTTP) with proper format
echo -e "\n${YELLOW}Testing Chat API (HTTP)...${NC}"
echo -e "${YELLOW}Using endpoint:${NC} $CHAT_API_URL/chat"

cat << EOF > chat_query.json
{
  "tenant": "$TENANT",
  "message": "What are the key features of Cloudable.AI?",
  "conversation_id": "test-conversation",
  "use_kb": true
}
EOF
echo -e "${YELLOW}Chat payload:${NC}"
cat chat_query.json

CHAT_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @chat_query.json \
  ${CHAT_API_URL}/chat || echo "Request failed")
echo "$CHAT_RESPONSE"

echo -e "\n${YELLOW}API Testing Complete${NC}"
