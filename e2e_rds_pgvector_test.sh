#!/bin/bash
# End-to-End Test for RDS pgvector Integration

# Set up variables
REGION="us-east-1"
TENANT="t001"
CUSTOMER_ID="test-customer-$(date +%s)"
API_KEY="sZI5RibzbE2WY1kRw4zcX1iSXhSnIqAoauc2XezS"
API_ID="pdoq719mx2"   # REST API ID for most endpoints
CHAT_API_ID="2tol4asisa"  # HTTP API ID for chat endpoints
API_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/dev"
CHAT_API_URL="https://${CHAT_API_ID}.execute-api.${REGION}.amazonaws.com/dev"
TEST_FILE="test_document_e2e_$(date +%Y%m%d%H%M%S).md"
TIMESTAMP=$(date +%Y%m%d%H%M%S)

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
UPLOAD_URL_PAYLOAD="{\"tenant_id\":\"${TENANT}\",\"filename\":\"${TEST_FILE}\"}"

# Invoke Lambda directly instead of API Gateway
echo -e "Invoking Lambda with payload: ${UPLOAD_URL_PAYLOAD}"
aws lambda invoke \
  --function-name kb-manager-dev \
  --payload "{\"path\": \"/kb/upload-url\", \"httpMethod\": \"POST\", \"body\": ${UPLOAD_URL_PAYLOAD}}" \
  --cli-binary-format raw-in-base64-out \
  /tmp/upload_url_response.json \
  --region ${REGION}

LAMBDA_STATUS=$?
if [ $LAMBDA_STATUS -ne 0 ]; then
  echo -e "${RED}✗ Failed to invoke Lambda (status: $LAMBDA_STATUS)${NC}"
  exit 1
fi

# Read Lambda response
UPLOAD_URL_RESPONSE_RAW=$(cat /tmp/upload_url_response.json)
echo "Raw Lambda response:"
echo "$UPLOAD_URL_RESPONSE_RAW" | jq .

# Extract the response body
UPLOAD_URL_RESPONSE=$(echo "$UPLOAD_URL_RESPONSE_RAW" | jq -r '.body // ""')
if [ -z "$UPLOAD_URL_RESPONSE" ]; then
  echo -e "${RED}✗ Empty Lambda response body${NC}"
  exit 1
fi

# Parse the response body as JSON
UPLOAD_URL_RESPONSE_BODY=$(echo "$UPLOAD_URL_RESPONSE" | jq -r '.')
echo "Parsed response body:"
echo "$UPLOAD_URL_RESPONSE_BODY" | jq .

# Extract upload URL from the parsed response
UPLOAD_URL=$(echo "$UPLOAD_URL_RESPONSE_BODY" | jq -r '.presigned_url // empty')
DOCUMENT_KEY=$(echo "$UPLOAD_URL_RESPONSE_BODY" | jq -r '.document_key // empty')

if [ -z "$UPLOAD_URL" ]; then
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

# 4. Trigger document processing and KB sync directly with Lambda
echo -e "\n${YELLOW}4. Triggering KB sync for document...${NC}"
SYNC_PAYLOAD="{\"tenant_id\":\"${TENANT}\",\"document_key\":\"${DOCUMENT_KEY}\"}"

# Invoke Lambda directly
echo -e "Invoking Lambda for KB sync with payload: ${SYNC_PAYLOAD}"
aws lambda invoke \
  --function-name kb-manager-dev \
  --payload "{\"path\": \"/kb/sync\", \"httpMethod\": \"POST\", \"body\": ${SYNC_PAYLOAD}}" \
  --cli-binary-format raw-in-base64-out \
  /tmp/sync_response.json \
  --region ${REGION}

LAMBDA_STATUS=$?
if [ $LAMBDA_STATUS -ne 0 ]; then
  echo -e "${RED}✗ Failed to invoke Lambda for KB sync (status: $LAMBDA_STATUS)${NC}"
  exit 1
fi

# Read Lambda response
SYNC_RESPONSE_RAW=$(cat /tmp/sync_response.json)
echo "Raw Lambda response:"
echo "$SYNC_RESPONSE_RAW" | jq .

# Extract the response body
SYNC_RESPONSE=$(echo "$SYNC_RESPONSE_RAW" | jq -r '.body // ""')
if [ -z "$SYNC_RESPONSE" ]; then
  echo -e "${RED}✗ Empty Lambda response body${NC}"
  exit 1
fi

# Parse the response body as JSON
SYNC_RESPONSE_BODY=$(echo "$SYNC_RESPONSE" | jq -r '.')
echo "Parsed response body:"
echo "$SYNC_RESPONSE_BODY" | jq .

# Extract ingestion job ID
INGESTION_JOB_ID=$(echo "$SYNC_RESPONSE_BODY" | jq -r '.ingestion_job_id // empty')

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

# 6. Query the knowledge base directly with Lambda
echo -e "\n${YELLOW}6. Querying knowledge base...${NC}"
QUERY_PAYLOAD="{\"tenant_id\":\"${TENANT}\",\"customer_id\":\"${CUSTOMER_ID}\",\"query\":\"What are the key features of Cloudable.AI?\"}"

# Invoke Lambda directly
echo -e "Invoking Lambda for KB query with payload: ${QUERY_PAYLOAD}"
aws lambda invoke \
  --function-name kb-manager-dev \
  --payload "{\"path\": \"/kb/query\", \"httpMethod\": \"POST\", \"body\": ${QUERY_PAYLOAD}}" \
  --cli-binary-format raw-in-base64-out \
  /tmp/query_response.json \
  --region ${REGION}

LAMBDA_STATUS=$?
if [ $LAMBDA_STATUS -ne 0 ]; then
  echo -e "${RED}✗ Failed to invoke Lambda for KB query (status: $LAMBDA_STATUS)${NC}"
  exit 1
fi

# Read Lambda response
QUERY_RESPONSE_RAW=$(cat /tmp/query_response.json)
echo "Raw Lambda response:"
echo "$QUERY_RESPONSE_RAW" | jq .

# Extract the response body
QUERY_RESPONSE=$(echo "$QUERY_RESPONSE_RAW" | jq -r '.body // ""')
if [ -z "$QUERY_RESPONSE" ]; then
  echo -e "${RED}✗ Empty Lambda response body${NC}"
  exit 1
fi

# Parse the response body as JSON
QUERY_RESPONSE_BODY=$(echo "$QUERY_RESPONSE" | jq -r '.')
echo "Parsed response body:"
echo "$QUERY_RESPONSE_BODY" | jq .

# Extract answer
ANSWER=$(echo "$QUERY_RESPONSE_BODY" | jq -r '.answer // empty')

if [ -z "$ANSWER" ] || [ "$ANSWER" = "null" ]; then
  echo -e "${RED}✗ Failed to get meaningful answer${NC}"
else
  echo -e "${GREEN}✓ Received answer from knowledge base${NC}"
  echo -e "${BLUE}Answer: ${ANSWER}${NC}"
fi

# 7. Chat with agent using KB directly through Lambda
echo -e "\n${YELLOW}7. Testing chat with knowledge base integration...${NC}"
CHAT_PAYLOAD="{\"tenant_id\":\"${TENANT}\",\"customer_id\":\"${CUSTOMER_ID}\",\"message\":\"Tell me about the technical architecture of Cloudable.AI\",\"conversation_id\":\"test-${TIMESTAMP}\"}"

# Invoke Lambda directly
echo -e "Invoking Lambda for chat with payload: ${CHAT_PAYLOAD}"
aws lambda invoke \
  --function-name orchestrator-dev \
  --payload "{\"path\": \"/chat\", \"httpMethod\": \"POST\", \"body\": ${CHAT_PAYLOAD}}" \
  --cli-binary-format raw-in-base64-out \
  /tmp/chat_response.json \
  --region ${REGION}

LAMBDA_STATUS=$?
if [ $LAMBDA_STATUS -ne 0 ]; then
  echo -e "${RED}✗ Failed to invoke Lambda for chat (status: $LAMBDA_STATUS)${NC}"
  exit 1
fi

# Read Lambda response
CHAT_RESPONSE_RAW=$(cat /tmp/chat_response.json)
echo "Raw Lambda response:"
echo "$CHAT_RESPONSE_RAW" | jq .

# Extract the response body
CHAT_RESPONSE=$(echo "$CHAT_RESPONSE_RAW" | jq -r '.body // ""')
if [ -z "$CHAT_RESPONSE" ]; then
  echo -e "${RED}✗ Empty Lambda response body${NC}"
  exit 1
fi

# Parse the response body as JSON
CHAT_RESPONSE_BODY=$(echo "$CHAT_RESPONSE" | jq -r '.')
echo "Parsed response body:"
echo "$CHAT_RESPONSE_BODY" | jq .

# Extract answer
CHAT_ANSWER=$(echo "$CHAT_RESPONSE_BODY" | jq -r '.answer // empty')

if [ -z "$CHAT_ANSWER" ] || [ "$CHAT_ANSWER" = "null" ]; then
  echo -e "${RED}✗ Failed to get chat response${NC}"
else
  echo -e "${GREEN}✓ Received chat response${NC}"
  echo -e "${BLUE}Chat Answer: ${CHAT_ANSWER}${NC}"
fi

# Clean up
echo -e "\n${YELLOW}8. Cleaning up test files...${NC}"
rm -f ${TEST_FILE}
echo -e "${GREEN}✓ Test files removed${NC}"

echo -e "\n${BLUE}===========================================${NC}"
echo -e "${BLUE}    E2E TEST COMPLETED    ${NC}"
echo -e "${BLUE}===========================================${NC}"
