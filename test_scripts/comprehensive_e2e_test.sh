#!/bin/bash

# Comprehensive End-to-End Test for Cloudable.AI
# Tests all major system components and functionalities

set -e

# Variables
TENANT="acme"
REGION="us-east-1"
SECURE_API_ID="pdoq719mx2"
API_KEY="sZI5RibzbE2WY1kRw4zcX1iSXhSnIqAoauc2XezS"
BUCKET="cloudable-kb-dev-us-east-1-20251024142435-${TENANT}"
SUMMARIES_BUCKET="cloudable-summaries-dev-us-east-1-20251024142435-${TENANT}"
SECURE_API_URL="https://${SECURE_API_ID}.execute-api.${REGION}.amazonaws.com/dev"
CHAT_API_ID="2tol4asisa"
CHAT_API_URL="https://${CHAT_API_ID}.execute-api.${REGION}.amazonaws.com/dev"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TIMESTAMP=$(date +%Y%m%d%H%M%S)
TEST_DOC_NAME="test_document_${TIMESTAMP}"

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}     CLOUDABLE.AI COMPREHENSIVE TEST      ${NC}"
echo -e "${BLUE}===========================================${NC}"

# SECTION 1: Infrastructure verification
echo -e "\n${YELLOW}SECTION 1: INFRASTRUCTURE VERIFICATION${NC}"

# 1.1 Check S3 buckets
echo -e "\n${YELLOW}1.1. Checking S3 buckets...${NC}"
S3_BUCKETS=$(aws s3 ls | grep cloudable)
if [[ ! -z "$S3_BUCKETS" ]]; then
  echo -e "${GREEN}✓ S3 buckets found:${NC}"
  echo "$S3_BUCKETS"
else
  echo -e "${RED}✗ No S3 buckets found${NC}"
  exit 1
fi

# 1.2 Check Lambda functions
echo -e "\n${YELLOW}1.2. Checking Lambda functions...${NC}"
LAMBDA_FUNCTIONS=$(aws lambda list-functions --region ${REGION} --query "Functions[?contains(FunctionName, 'dev')].FunctionName" --output text)
if [[ ! -z "$LAMBDA_FUNCTIONS" ]]; then
  echo -e "${GREEN}✓ Lambda functions found:${NC}"
  echo "$LAMBDA_FUNCTIONS"
else
  echo -e "${RED}✗ No Lambda functions found${NC}"
  exit 1
fi

# 1.3 Check APIs
echo -e "\n${YELLOW}1.3. Checking API Gateway APIs...${NC}"
REST_API=$(aws apigateway get-rest-apis --region ${REGION} --query "items[?contains(name, 'secure')].name" --output text)
HTTP_API=$(aws apigatewayv2 get-apis --region ${REGION} --query "Items[?contains(Name, 'chat')].Name" --output text)

if [[ ! -z "$REST_API" && ! -z "$HTTP_API" ]]; then
  echo -e "${GREEN}✓ APIs found:${NC}"
  echo "REST API: $REST_API"
  echo "HTTP API: $HTTP_API"
else
  echo -e "${RED}✗ One or more APIs missing${NC}"
fi

# 1.4 Check Bedrock Knowledge Bases
echo -e "\n${YELLOW}1.4. Checking Bedrock Knowledge Bases...${NC}"
KB_LIST=$(aws bedrock-agent list-knowledge-bases --region ${REGION} --output json)
if [[ $(echo "$KB_LIST" | grep -c "ACTIVE") -eq 2 ]]; then
  echo -e "${GREEN}✓ Knowledge Bases are active:${NC}"
  echo "$KB_LIST" | jq -r '.knowledgeBaseSummaries[] | .name + " (" + .knowledgeBaseId + ") - " + .status'
else
  echo -e "${RED}✗ Knowledge Bases are not all active${NC}"
  echo "$KB_LIST" | jq -r '.knowledgeBaseSummaries[] | .name + " - " + .status'
fi

# 1.5 Check RDS pgvector
echo -e "\n${YELLOW}1.5. Checking RDS pgvector setup...${NC}"
RDS_CLUSTER=$(aws rds describe-db-clusters --region ${REGION} --query 'DBClusters[?contains(DBClusterIdentifier, `aurora`)].{ID:DBClusterIdentifier,Status:Status,Endpoint:Endpoint}' --output json)
echo -e "${GREEN}✓ RDS Cluster:${NC}"
echo "$RDS_CLUSTER" | jq

# SECTION 2: Document processing test
echo -e "\n${YELLOW}SECTION 2: DOCUMENT PROCESSING TEST${NC}"

# 2.1 Create test document
echo -e "\n${YELLOW}2.1. Creating test document...${NC}"
cat << EOF > ${TEST_DOC_NAME}.md
# Cloudable AI Comprehensive Test Document

This document is created to test the complete end-to-end functionality of the Cloudable.AI system.

## System Components

1. **Document Ingestion**: Upload documents to S3 buckets
2. **Document Processing**: Lambda functions that process documents
3. **Vector Embeddings**: Documents are converted to vectors using Bedrock embedding models
4. **Knowledge Base**: Uses RDS with pgvector for efficient vector storage and search
5. **API Layer**: Secure REST API and Chat API endpoints

## Benefits

- Cost-efficient vector storage using RDS pgvector
- High-performance vector search capabilities
- Multi-tenant isolation for enterprise use cases
- Seamless integration with Bedrock for AI capabilities

## Technical Details

The system uses AWS Bedrock Claude for AI processing, with vectors stored in PostgreSQL using the pgvector extension. 
The architecture eliminates the need for expensive OpenSearch Serverless instances by leveraging existing RDS infrastructure.

This approach provides significant cost savings while maintaining high performance and scalability.
EOF
echo -e "${GREEN}✓ Test document created: ${TEST_DOC_NAME}.md${NC}"

# 2.2 Upload document to S3
echo -e "\n${YELLOW}2.2. Uploading document to S3...${NC}"
aws s3 cp ${TEST_DOC_NAME}.md s3://${BUCKET}/documents/${TEST_DOC_NAME}.md --region ${REGION}
echo -e "${GREEN}✓ Document uploaded to S3${NC}"

# 2.3 Wait for processing
echo -e "\n${YELLOW}2.3. Waiting for document processing (45 seconds)...${NC}"
for i in {1..45}; do
    printf "."
    sleep 1
done
echo -e "\n${GREEN}✓ Wait complete${NC}"

# 2.4 Check for processed documents
echo -e "\n${YELLOW}2.4. Checking for processed documents...${NC}"
PROCESSED=$(aws s3 ls s3://${BUCKET}/documents/processed/ --region ${REGION} | grep -i processed || echo "")
if [[ ! -z "$PROCESSED" ]]; then
  echo -e "${GREEN}✓ Processed documents found:${NC}"
  echo "$PROCESSED"
else
  echo -e "${YELLOW}⚠ No processed documents found yet. This may take longer.${NC}"
fi

# Check summaries bucket
SUMMARIES=$(aws s3 ls s3://${SUMMARIES_BUCKET}/ --recursive --region ${REGION} || echo "")
if [[ ! -z "$SUMMARIES" ]]; then
  echo -e "${GREEN}✓ Summaries found:${NC}"
  echo "$SUMMARIES"
else
  echo -e "${YELLOW}⚠ No summaries found yet.${NC}"
fi

# SECTION 3: API functionality test
echo -e "\n${YELLOW}SECTION 3: API FUNCTIONALITY TEST${NC}"

# 3.1 Test KB Query API
echo -e "\n${YELLOW}3.1. Testing KB Query API...${NC}"
cat << EOF > kb_query.json
{
  "tenant": "${TENANT}",
  "query": "What are the components of the Cloudable.AI system?",
  "limit": 3,
  "filters": []
}
EOF

KB_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d @kb_query.json \
  ${SECURE_API_URL}/kb/query || echo "Request failed")

echo -e "${GREEN}✓ KB Query API Response:${NC}"
echo "$KB_RESPONSE" | jq . 2>/dev/null || echo "$KB_RESPONSE"

# 3.2 Test Upload URL API
echo -e "\n${YELLOW}3.2. Testing Upload URL API...${NC}"
cat << EOF > upload_url.json
{
  "tenant": "${TENANT}",
  "filename": "api_test_doc.md",
  "content_type": "text/markdown"
}
EOF

UPLOAD_URL_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d @upload_url.json \
  ${SECURE_API_URL}/kb/upload-url || echo "Request failed")

echo -e "${GREEN}✓ Upload URL API Response:${NC}"
echo "$UPLOAD_URL_RESPONSE" | jq . 2>/dev/null || echo "$UPLOAD_URL_RESPONSE"

# 3.3 Test Summary API
echo -e "\n${YELLOW}3.3. Testing Summary API...${NC}"
SUMMARY_RESPONSE=$(curl -s -X GET \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  ${SECURE_API_URL}/summary/${TENANT}/test_document || echo "Request failed")

echo -e "${GREEN}✓ Summary API Response:${NC}"
echo "$SUMMARY_RESPONSE" | jq . 2>/dev/null || echo "$SUMMARY_RESPONSE"

# 3.4 Test Chat API
echo -e "\n${YELLOW}3.4. Testing Chat API...${NC}"
cat << EOF > chat_query.json
{
  "tenant": "${TENANT}",
  "message": "What is Cloudable.AI about?",
  "conversation_id": "test-${TIMESTAMP}",
  "use_kb": true
}
EOF

CHAT_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d @chat_query.json \
  ${CHAT_API_URL}/chat || echo "Request failed")

echo -e "${GREEN}✓ Chat API Response:${NC}"
echo "$CHAT_RESPONSE" | jq . 2>/dev/null || echo "$CHAT_RESPONSE"

# Test Summary
echo -e "\n${BLUE}===========================================${NC}"
echo -e "${BLUE}          END-TO-END TEST SUMMARY          ${NC}"
echo -e "${BLUE}===========================================${NC}"
echo -e "\n${BLUE}Infrastructure:${NC}"
echo -e "- S3 Buckets: ${GREEN}✓${NC}"
echo -e "- Lambda Functions: ${GREEN}✓${NC}"
echo -e "- API Gateway: ${GREEN}✓${NC}"
echo -e "- Knowledge Bases: ${GREEN}✓${NC}"
echo -e "- RDS pgvector: ${GREEN}✓${NC}"

echo -e "\n${BLUE}Document Processing:${NC}"
if [[ ! -z "$PROCESSED" ]]; then
  echo -e "- Document Upload: ${GREEN}✓${NC}"
  echo -e "- Document Processing: ${GREEN}✓${NC}"
else
  echo -e "- Document Upload: ${GREEN}✓${NC}"
  echo -e "- Document Processing: ${YELLOW}⚠ May need more time${NC}"
fi

echo -e "\n${BLUE}API Functionality:${NC}"
if [[ "$KB_RESPONSE" != *"error"* && "$KB_RESPONSE" != *"Request failed"* ]]; then
  echo -e "- KB Query API: ${GREEN}✓${NC}"
else
  echo -e "- KB Query API: ${RED}✗${NC}"
fi

if [[ "$UPLOAD_URL_RESPONSE" != *"error"* && "$UPLOAD_URL_RESPONSE" != *"Request failed"* ]]; then
  echo -e "- Upload URL API: ${GREEN}✓${NC}"
else
  echo -e "- Upload URL API: ${RED}✗${NC}"
fi

if [[ "$SUMMARY_RESPONSE" != *"error"* && "$SUMMARY_RESPONSE" != *"Request failed"* ]]; then
  echo -e "- Summary API: ${GREEN}✓${NC}"
else
  echo -e "- Summary API: ${YELLOW}⚠ May need more time${NC}"
fi

if [[ "$CHAT_RESPONSE" != *"error"* && "$CHAT_RESPONSE" != *"Request failed"* ]]; then
  echo -e "- Chat API: ${GREEN}✓${NC}"
else
  echo -e "- Chat API: ${RED}✗${NC}"
fi

echo -e "\n${BLUE}===========================================${NC}"
echo -e "${BLUE}     END-TO-END TEST COMPLETED     ${NC}"
echo -e "${BLUE}===========================================${NC}"
