#!/bin/bash
# End-to-End Test for RDS pgvector Integration

set -e

# Set up variables
REGION="us-east-1"
TENANT="t001"
CUSTOMER_ID="test-customer-$(date +%s)"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
TEST_FILE="test_document_e2e_${TIMESTAMP}.md"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE} CLOUDABLE.AI RDS PGVECTOR E2E TEST ${NC}"
echo -e "${BLUE}===========================================${NC}"

# 1. Create test document
echo -e "\n${YELLOW}1. Creating test document...${NC}"
cat << EOF > ${TEST_FILE}
# Cloudable.AI Test Document

## Overview
Cloudable.AI is a cutting-edge platform for AI-powered knowledge management, designed for enterprise use.

## Key Features
- Multi-tenant knowledge bases powered by pgvector in RDS PostgreSQL
- Advanced vector search for semantic understanding of queries
- Document processing and summarization capabilities
- Chat interface with memory and knowledge integration
- Robust security and access controls

## Technical Architecture
The platform is built on AWS and includes:
- RDS PostgreSQL with pgvector for vector storage
- S3 buckets for document storage
- Lambda functions for serverless processing
- API Gateway for RESTful APIs
- Amazon Bedrock for AI/ML capabilities

## Benefits
- Cost-effective: Using existing RDS infrastructure instead of specialized vector databases
- Scalable: Handles thousands of documents and concurrent users
- Secure: Enterprise-grade security and compliance
- Intelligent: Advanced AI for accurate and relevant responses
EOF

echo -e "${GREEN}✓ Test document created: ${TEST_FILE}${NC}"

# 2. Generate pre-signed URL for document upload
echo -e "\n${YELLOW}2. Getting upload URL directly from Lambda...${NC}"

# Create proper JSON payload with escaping
UPLOAD_BODY=$(cat << EOF
{
  "tenant_id": "${TENANT}",
  "filename": "${TEST_FILE}"
}
EOF
)

ESCAPED_UPLOAD_BODY=$(echo $UPLOAD_BODY | jq -c -R '.')

UPLOAD_PAYLOAD=$(cat << EOF
{
  "path": "/kb/upload-url",
  "httpMethod": "POST",
  "body": ${ESCAPED_UPLOAD_BODY}
}
EOF
)

echo "Lambda payload:"
echo "$UPLOAD_PAYLOAD" | jq .

# Invoke Lambda directly
aws lambda invoke \
  --function-name kb-manager-dev \
  --payload "$UPLOAD_PAYLOAD" \
  --cli-binary-format raw-in-base64-out \
  /tmp/upload_url_response.json \
  --region ${REGION}

# Read Lambda response
UPLOAD_RESPONSE=$(cat /tmp/upload_url_response.json)
echo "Lambda response:"
echo "$UPLOAD_RESPONSE" | jq .

# Extract the upload URL and document key
UPLOAD_URL=$(echo "$UPLOAD_RESPONSE" | jq -r '.body' | jq -r '.presigned_url')
DOCUMENT_KEY=$(echo "$UPLOAD_RESPONSE" | jq -r '.body' | jq -r '.document_key')

if [ -z "$UPLOAD_URL" ] || [ "$UPLOAD_URL" = "null" ]; then
  echo -e "${RED}✗ Failed to get upload URL${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Got upload URL${NC}"
echo -e "${BLUE}Document key: ${DOCUMENT_KEY}${NC}"

# 3. Upload document to S3
echo -e "\n${YELLOW}3. Uploading document to S3...${NC}"
UPLOAD_RESULT=$(curl -s -X PUT \
  -H "Content-Type: text/markdown" \
  --upload-file ${TEST_FILE} \
  "${UPLOAD_URL}")

if [ $? -ne 0 ]; then
  echo -e "${RED}✗ Failed to upload document${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Document uploaded successfully${NC}"

# 4. Trigger document processing and KB sync
echo -e "\n${YELLOW}4. Triggering KB sync for document...${NC}"

# Create proper JSON payload with escaping
SYNC_BODY=$(cat << EOF
{
  "tenant_id": "${TENANT}",
  "document_key": "${DOCUMENT_KEY}"
}
EOF
)

ESCAPED_SYNC_BODY=$(echo $SYNC_BODY | jq -c -R '.')

SYNC_PAYLOAD=$(cat << EOF
{
  "path": "/kb/sync",
  "httpMethod": "POST",
  "body": ${ESCAPED_SYNC_BODY}
}
EOF
)

echo "Lambda payload:"
echo "$SYNC_PAYLOAD" | jq .

# Invoke Lambda directly
aws lambda invoke \
  --function-name kb-manager-dev \
  --payload "$SYNC_PAYLOAD" \
  --cli-binary-format raw-in-base64-out \
  /tmp/sync_response.json \
  --region ${REGION}

# Read Lambda response
SYNC_RESPONSE=$(cat /tmp/sync_response.json)
echo "Lambda response:"
echo "$SYNC_RESPONSE" | jq .

# Extract ingestion job ID
INGESTION_JOB_ID=$(echo "$SYNC_RESPONSE" | jq -r '.body' | jq -r '.ingestion_job_id // empty')

if [ -z "$INGESTION_JOB_ID" ]; then
  echo -e "${RED}✗ Failed to start KB sync${NC}"
else
  echo -e "${GREEN}✓ KB sync started with job ID: ${INGESTION_JOB_ID}${NC}"
fi

# 5. Give time for processing to complete
echo -e "\n${YELLOW}5. Waiting for document processing (30 seconds)...${NC}"
for i in {1..30}; do
  echo -n "."
  sleep 1
done
echo ""

# 6. Query the knowledge base
echo -e "\n${YELLOW}6. Querying knowledge base...${NC}"

# Create proper JSON payload with escaping
QUERY_BODY=$(cat << EOF
{
  "tenant_id": "${TENANT}",
  "customer_id": "${CUSTOMER_ID}",
  "query": "What are the key features of Cloudable.AI?"
}
EOF
)

ESCAPED_QUERY_BODY=$(echo $QUERY_BODY | jq -c -R '.')

QUERY_PAYLOAD=$(cat << EOF
{
  "path": "/kb/query",
  "httpMethod": "POST",
  "body": ${ESCAPED_QUERY_BODY}
}
EOF
)

echo "Lambda payload:"
echo "$QUERY_PAYLOAD" | jq .

# Invoke Lambda directly
aws lambda invoke \
  --function-name kb-manager-dev \
  --payload "$QUERY_PAYLOAD" \
  --cli-binary-format raw-in-base64-out \
  /tmp/query_response.json \
  --region ${REGION}

# Read Lambda response
QUERY_RESPONSE=$(cat /tmp/query_response.json)
echo "Lambda response:"
echo "$QUERY_RESPONSE" | jq .

# Extract answer
ANSWER=$(echo "$QUERY_RESPONSE" | jq -r '.body' | jq -r '.answer // empty')

if [ -z "$ANSWER" ] || [ "$ANSWER" = "null" ]; then
  echo -e "${RED}✗ Failed to get meaningful answer${NC}"
else
  echo -e "${GREEN}✓ Received answer from knowledge base${NC}"
  echo -e "${BLUE}Answer: ${ANSWER}${NC}"
fi

# 7. Chat with agent using KB
echo -e "\n${YELLOW}7. Testing chat with knowledge base integration...${NC}"

# Create proper JSON payload with escaping
CHAT_BODY=$(cat << EOF
{
  "tenant_id": "${TENANT}",
  "customer_id": "${CUSTOMER_ID}",
  "message": "Tell me about the technical architecture of Cloudable.AI",
  "conversation_id": "test-${TIMESTAMP}"
}
EOF
)

ESCAPED_CHAT_BODY=$(echo $CHAT_BODY | jq -c -R '.')

CHAT_PAYLOAD=$(cat << EOF
{
  "path": "/chat",
  "httpMethod": "POST",
  "body": ${ESCAPED_CHAT_BODY}
}
EOF
)

echo "Lambda payload:"
echo "$CHAT_PAYLOAD" | jq .

# Invoke Lambda directly
aws lambda invoke \
  --function-name orchestrator-dev \
  --payload "$CHAT_PAYLOAD" \
  --cli-binary-format raw-in-base64-out \
  /tmp/chat_response.json \
  --region ${REGION}

# Read Lambda response
CHAT_RESPONSE=$(cat /tmp/chat_response.json)
echo "Lambda response:"
echo "$CHAT_RESPONSE" | jq .

# Extract answer
CHAT_ANSWER=$(echo "$CHAT_RESPONSE" | jq -r '.body' | jq -r '.answer // empty')

if [ -z "$CHAT_ANSWER" ] || [ "$CHAT_ANSWER" = "null" ]; then
  echo -e "${RED}✗ Failed to get chat response${NC}"
else
  echo -e "${GREEN}✓ Received chat response${NC}"
  echo -e "${BLUE}Chat Answer: ${CHAT_ANSWER}${NC}"
fi

# 8. Clean up test files
echo -e "\n${YELLOW}8. Cleaning up test files...${NC}"
rm -f ${TEST_FILE}
echo -e "${GREEN}✓ Test files removed${NC}"

echo -e "\n${BLUE}===========================================${NC}"
echo -e "${BLUE}          E2E TEST COMPLETED          ${NC}"
echo -e "${BLUE}===========================================${NC}"
