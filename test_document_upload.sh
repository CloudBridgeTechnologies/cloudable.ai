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
echo -e "${BLUE}   CLOUDABLE.AI DOCUMENT UPLOAD TEST              ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Get API Gateway endpoint from Terraform or use default
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/infras/core" 2>/dev/null
API_ENDPOINT=$(terraform output -raw api_endpoint 2>/dev/null || echo "")
cd "$SCRIPT_DIR"

if [ -z "$API_ENDPOINT" ]; then
    # Fallback to known endpoint
    API_ENDPOINT="https://uk9o6co5pd.execute-api.eu-west-1.amazonaws.com/dev"
fi

# Test for both tenants
TENANTS=("acme" "globex")
S3_BUCKETS=(
  "cloudable-kb-dev-eu-west-1-acme-20251114095518"
  "cloudable-kb-dev-eu-west-1-globex-20251114095518"
)

# Documents
ACME_DOC="customer_journey_acme.md"
GLOBEX_DOC="customer_journey_globex.md"
DOCS=("$ACME_DOC" "$GLOBEX_DOC")

# Step 1: Get presigned URLs for uploads
echo -e "\n${YELLOW}Step 1: Getting presigned URLs for document uploads...${NC}"

for i in "${!TENANTS[@]}"; do
  TENANT=${TENANTS[$i]}
  DOC=${DOCS[$i]}
  BUCKET=${S3_BUCKETS[$i]}
  
  echo -e "\nGetting presigned URL for tenant: ${TENANT}, document: ${DOC}"
  
  # Request presigned URL
  URL_REQUEST_PAYLOAD="{\"tenant\":\"${TENANT}\",\"filename\":\"${DOC}\",\"content_type\":\"text/markdown\"}"
  URL_RESPONSE=$(curl -s -X POST \
    "${API_ENDPOINT}/api/upload-url" \
    -H "Content-Type: application/json" \
    -H "X-User-ID: user-admin-001" \
    -d "${URL_REQUEST_PAYLOAD}")
  
  echo -e "Response: ${URL_RESPONSE}"
  
  # Extract URL from response (simplified - in real world would use jq)
  UPLOAD_URL=$(echo $URL_RESPONSE | grep -o '"url":"[^"]*' | sed 's/"url":"//')
  DOCUMENT_KEY=$(echo $URL_RESPONSE | grep -o '"key":"[^"]*' | sed 's/"key":"//')
  
  if [[ -z "$UPLOAD_URL" ]]; then
    echo -e "${RED}Failed to get presigned URL for ${TENANT}.${NC}"
    continue
  fi
  
  echo -e "${GREEN}Got presigned URL for ${TENANT}.${NC}"
  echo -e "Document key: ${DOCUMENT_KEY}"
  
  # Step 2: Upload documents to S3
  echo -e "\n${YELLOW}Step 2: Uploading documents to S3...${NC}"
  
  # For testing purposes, direct S3 upload
  echo -e "Uploading ${DOC} to bucket ${BUCKET}"
  aws s3 cp "${DOC}" "s3://${BUCKET}/documents/${DOC}"
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully uploaded ${DOC} to S3${NC}"
  else
    echo -e "${RED}Failed to upload ${DOC} to S3${NC}"
    continue
  fi
  
  # Step 3: Trigger KB sync for the uploaded document
  echo -e "\n${YELLOW}Step 3: Triggering KB sync for ${TENANT}...${NC}"
  
  SYNC_PAYLOAD="{\"tenant\":\"${TENANT}\",\"document_key\":\"documents/${DOC}\"}"
  SYNC_RESPONSE=$(curl -s -X POST \
    "${API_ENDPOINT}/api/kb/sync" \
    -H "Content-Type: application/json" \
    -H "X-User-ID: user-admin-001" \
    -d "${SYNC_PAYLOAD}")
  
  echo -e "KB Sync Response: ${SYNC_RESPONSE}"
  
  # Wait a moment for processing
  echo -e "Waiting for document processing to complete..."
  sleep 5
done

# Step 4: Test KB Query with customer journey questions
echo -e "\n${YELLOW}Step 4: Testing KB queries...${NC}"

# ACME Queries
echo -e "\n${BLUE}Testing ACME customer journey queries:${NC}"

# Query 1: Current Status
echo -e "\n${YELLOW}Query: What is the current implementation status of ACME?${NC}"
QUERY1_PAYLOAD="{\"tenant\":\"acme\",\"query\":\"What is the current implementation status of ACME?\",\"max_results\":3}"
QUERY1_RESPONSE=$(curl -s -X POST \
  "${API_ENDPOINT}/api/kb/query" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: user-reader-001" \
  -d "${QUERY1_PAYLOAD}")

echo -e "Response: ${QUERY1_RESPONSE}"

# Query 2: Success Metrics
echo -e "\n${YELLOW}Query: What are ACME's success metrics?${NC}"
QUERY2_PAYLOAD="{\"tenant\":\"acme\",\"query\":\"What are ACME's success metrics?\",\"max_results\":3}"
QUERY2_RESPONSE=$(curl -s -X POST \
  "${API_ENDPOINT}/api/kb/query" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: user-reader-001" \
  -d "${QUERY2_PAYLOAD}")

echo -e "Response: ${QUERY2_RESPONSE}"

# Globex Queries
echo -e "\n${BLUE}Testing Globex customer journey queries:${NC}"

# Query 1: Current Status
echo -e "\n${YELLOW}Query: What is the current status of Globex Industries?${NC}"
QUERY3_PAYLOAD="{\"tenant\":\"globex\",\"query\":\"What is the current status of Globex Industries?\",\"max_results\":3}"
QUERY3_RESPONSE=$(curl -s -X POST \
  "${API_ENDPOINT}/api/kb/query" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: user-reader-001" \
  -d "${QUERY3_PAYLOAD}")

echo -e "Response: ${QUERY3_RESPONSE}"

# Query 2: Key Stakeholders
echo -e "\n${YELLOW}Query: Who are the key stakeholders at Globex?${NC}"
QUERY4_PAYLOAD="{\"tenant\":\"globex\",\"query\":\"Who are the key stakeholders at Globex?\",\"max_results\":3}"
QUERY4_RESPONSE=$(curl -s -X POST \
  "${API_ENDPOINT}/api/kb/query" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: user-reader-001" \
  -d "${QUERY4_PAYLOAD}")

echo -e "Response: ${QUERY4_RESPONSE}"

# Step 5: Test Chat API with customer journey questions
echo -e "\n${YELLOW}Step 5: Testing Chat API...${NC}"

# ACME Chat
echo -e "\n${BLUE}Testing ACME customer journey chat:${NC}"
ACME_CHAT_PAYLOAD="{\"tenant\":\"acme\",\"message\":\"Give me a summary of ACME's customer journey status and next steps\",\"use_kb\":true}"
ACME_CHAT_RESPONSE=$(curl -s -X POST \
  "${API_ENDPOINT}/api/chat" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: user-reader-001" \
  -d "${ACME_CHAT_PAYLOAD}")

echo -e "Response: ${ACME_CHAT_RESPONSE}"

# Globex Chat
echo -e "\n${BLUE}Testing Globex customer journey chat:${NC}"
GLOBEX_CHAT_PAYLOAD="{\"tenant\":\"globex\",\"message\":\"What are the implementation risks for Globex Industries?\",\"use_kb\":true}"
GLOBEX_CHAT_RESPONSE=$(curl -s -X POST \
  "${API_ENDPOINT}/api/chat" \
  -H "Content-Type: application/json" \
  -H "X-User-ID: user-reader-001" \
  -d "${GLOBEX_CHAT_PAYLOAD}")

echo -e "Response: ${GLOBEX_CHAT_RESPONSE}"

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}DOCUMENT UPLOAD AND KB QUERY TEST COMPLETED!${NC}"
echo -e "${BLUE}==================================================${NC}"

exit 0
