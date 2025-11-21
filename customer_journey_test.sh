#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI CUSTOMER JOURNEY TEST            ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Configuration
API_ENDPOINT="https://xn66ohjpw1.execute-api.us-east-1.amazonaws.com/dev"
ACME_BUCKET="cloudable-kb-dev-us-east-1-acme-20251114095518"
GLOBEX_BUCKET="cloudable-kb-dev-us-east-1-globex-20251114095518"
ACME_DOC="${SCRIPT_DIR}/customer_journey_acme.md"
GLOBEX_DOC="${SCRIPT_DIR}/customer_journey_globex.md"

# Step 1: Upload documents to S3
echo -e "\n${YELLOW}Step 1: Uploading customer journey documents to S3...${NC}"

# Upload ACME document
ACME_KEY="customer_journeys/acme_$(date +%Y%m%d%H%M%S).md"
echo -e "Uploading ACME customer journey to s3://${ACME_BUCKET}/${ACME_KEY}"
aws s3 cp "${ACME_DOC}" "s3://${ACME_BUCKET}/${ACME_KEY}"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully uploaded ACME document${NC}"
else
    echo -e "${RED}Failed to upload ACME document${NC}"
    exit 1
fi

# Upload Globex document
GLOBEX_KEY="customer_journeys/globex_$(date +%Y%m%d%H%M%S).md"
echo -e "Uploading Globex customer journey to s3://${GLOBEX_BUCKET}/${GLOBEX_KEY}"
aws s3 cp "${GLOBEX_DOC}" "s3://${GLOBEX_BUCKET}/${GLOBEX_KEY}"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully uploaded Globex document${NC}"
else
    echo -e "${RED}Failed to upload Globex document${NC}"
    exit 1
fi

# Step 2: Trigger knowledge base synchronization
echo -e "\n${YELLOW}Step 2: Triggering knowledge base synchronization...${NC}"

# Sync ACME document
echo -e "Syncing ACME customer journey document..."
ACME_SYNC_PAYLOAD="{\"tenant\":\"acme\",\"document_key\":\"${ACME_KEY}\"}"
ACME_SYNC_RESPONSE=$(curl -s -X POST \
    "${API_ENDPOINT}/api/kb/sync" \
    -H "Content-Type: application/json" \
    -d "${ACME_SYNC_PAYLOAD}")

echo -e "Response: ${ACME_SYNC_RESPONSE}"

# Sync Globex document
echo -e "Syncing Globex customer journey document..."
GLOBEX_SYNC_PAYLOAD="{\"tenant\":\"globex\",\"document_key\":\"${GLOBEX_KEY}\"}"
GLOBEX_SYNC_RESPONSE=$(curl -s -X POST \
    "${API_ENDPOINT}/api/kb/sync" \
    -H "Content-Type: application/json" \
    -d "${GLOBEX_SYNC_PAYLOAD}")

echo -e "Response: ${GLOBEX_SYNC_RESPONSE}"

# Step 3: Wait for processing to complete
echo -e "\n${YELLOW}Step 3: Waiting for knowledge base processing to complete (30 seconds)...${NC}"
sleep 30

# Step 4: Query the knowledge base
echo -e "\n${YELLOW}Step 4: Querying the knowledge base...${NC}"

# ACME queries
echo -e "\n${BLUE}ACME Customer Journey Queries:${NC}"

# Query 1: Current status
echo -e "\n${YELLOW}Query: What is the current implementation status of ACME Corporation?${NC}"
QUERY1_PAYLOAD="{\"tenant\":\"acme\",\"query\":\"What is the current implementation status of ACME Corporation?\",\"max_results\":3}"
QUERY1_RESPONSE=$(curl -s -X POST \
    "${API_ENDPOINT}/api/kb/query" \
    -H "Content-Type: application/json" \
    -d "${QUERY1_PAYLOAD}")

echo -e "${GREEN}Response: ${QUERY1_RESPONSE}${NC}"

# Query 2: Success metrics
echo -e "\n${YELLOW}Query: What are the success metrics for ACME's implementation?${NC}"
QUERY2_PAYLOAD="{\"tenant\":\"acme\",\"query\":\"What are the success metrics for ACME's implementation?\",\"max_results\":3}"
QUERY2_RESPONSE=$(curl -s -X POST \
    "${API_ENDPOINT}/api/kb/query" \
    -H "Content-Type: application/json" \
    -d "${QUERY2_PAYLOAD}")

echo -e "${GREEN}Response: ${QUERY2_RESPONSE}${NC}"

# Query 3: Next steps
echo -e "\n${YELLOW}Query: What are the next steps for ACME Corporation?${NC}"
QUERY3_PAYLOAD="{\"tenant\":\"acme\",\"query\":\"What are the next steps for ACME Corporation?\",\"max_results\":3}"
QUERY3_RESPONSE=$(curl -s -X POST \
    "${API_ENDPOINT}/api/kb/query" \
    -H "Content-Type: application/json" \
    -d "${QUERY3_PAYLOAD}")

echo -e "${GREEN}Response: ${QUERY3_RESPONSE}${NC}"

# Globex queries
echo -e "\n${BLUE}Globex Customer Journey Queries:${NC}"

# Query 1: Current status
echo -e "\n${YELLOW}Query: What is the current implementation status of Globex Industries?${NC}"
QUERY4_PAYLOAD="{\"tenant\":\"globex\",\"query\":\"What is the current implementation status of Globex Industries?\",\"max_results\":3}"
QUERY4_RESPONSE=$(curl -s -X POST \
    "${API_ENDPOINT}/api/kb/query" \
    -H "Content-Type: application/json" \
    -d "${QUERY4_PAYLOAD}")

echo -e "${GREEN}Response: ${QUERY4_RESPONSE}${NC}"

# Query 2: Key stakeholders
echo -e "\n${YELLOW}Query: Who are the key stakeholders at Globex Industries?${NC}"
QUERY5_PAYLOAD="{\"tenant\":\"globex\",\"query\":\"Who are the key stakeholders at Globex Industries?\",\"max_results\":3}"
QUERY5_RESPONSE=$(curl -s -X POST \
    "${API_ENDPOINT}/api/kb/query" \
    -H "Content-Type: application/json" \
    -d "${QUERY5_PAYLOAD}")

echo -e "${GREEN}Response: ${QUERY5_RESPONSE}${NC}"

# Step 5: Test chat functionality
echo -e "\n${YELLOW}Step 5: Testing chat functionality...${NC}"

# ACME chat
echo -e "\n${BLUE}ACME Customer Journey Chat:${NC}"
ACME_CHAT_PAYLOAD="{\"tenant\":\"acme\",\"message\":\"Give me a summary of ACME's customer journey status and next steps\",\"use_kb\":true}"
ACME_CHAT_RESPONSE=$(curl -s -X POST \
    "${API_ENDPOINT}/api/chat" \
    -H "Content-Type: application/json" \
    -d "${ACME_CHAT_PAYLOAD}")

echo -e "${GREEN}Response: ${ACME_CHAT_RESPONSE}${NC}"

# Globex chat
echo -e "\n${BLUE}Globex Customer Journey Chat:${NC}"
GLOBEX_CHAT_PAYLOAD="{\"tenant\":\"globex\",\"message\":\"What are the implementation risks for Globex Industries?\",\"use_kb\":true}"
GLOBEX_CHAT_RESPONSE=$(curl -s -X POST \
    "${API_ENDPOINT}/api/chat" \
    -H "Content-Type: application/json" \
    -d "${GLOBEX_CHAT_PAYLOAD}")

echo -e "${GREEN}Response: ${GLOBEX_CHAT_RESPONSE}${NC}"

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}CUSTOMER JOURNEY TEST COMPLETED!${NC}"
echo -e "${BLUE}==================================================${NC}"

exit 0
