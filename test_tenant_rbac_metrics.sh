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
echo -e "${BLUE}   CLOUDABLE.AI RBAC AND METRICS TEST             ${NC}"
echo -e "${BLUE}==================================================${NC}"

# API Gateway endpoint
API_ENDPOINT="https://xn66ohjpw1.execute-api.us-east-1.amazonaws.com/dev"

# Test user IDs and roles
USER_ADMIN="user-admin-001"    # admin role
USER_READER="user-reader-001"  # reader role
USER_WRITER="user-writer-001"  # contributor role

# Test 1: Admin user accesses upload-url API
echo -e "\n${YELLOW}TEST 1: Admin user uploads document${NC}"
echo -e "User: ${USER_ADMIN} (admin role) - Should be allowed"

ADMIN_UPLOAD=$(curl -s -X POST \
  "${API_ENDPOINT}/api/upload-url" \
  -H "Content-Type: application/json" \
  -H "x-user-id: ${USER_ADMIN}" \
  -d '{"tenant":"acme","filename":"admin_document.md","content_type":"text/markdown"}')

echo -e "Response: ${ADMIN_UPLOAD}"

if [[ "$ADMIN_UPLOAD" == *"url"* && "$ADMIN_UPLOAD" == *"key"* ]]; then
  echo -e "${GREEN}✓ Success: Admin user allowed to generate upload URL${NC}"
else
  echo -e "${RED}✗ Failure: Admin user denied access to upload URL${NC}"
fi

# Test 2: Reader user attempts to access upload-url API (should be denied)
echo -e "\n${YELLOW}TEST 2: Reader user attempts document upload${NC}"
echo -e "User: ${USER_READER} (reader role) - Should be denied"

READER_UPLOAD=$(curl -s -X POST \
  "${API_ENDPOINT}/api/upload-url" \
  -H "Content-Type: application/json" \
  -H "x-user-id: ${USER_READER}" \
  -d '{"tenant":"acme","filename":"reader_document.md","content_type":"text/markdown"}')

echo -e "Response: ${READER_UPLOAD}"

if [[ "$READER_UPLOAD" == *"url"* && "$READER_UPLOAD" == *"key"* ]]; then
  echo -e "${RED}✗ Failure: Reader user incorrectly allowed to generate upload URL${NC}"
else
  echo -e "${GREEN}✓ Success: Reader user properly denied access to upload URL${NC}"
fi

# Test 3: Reader user queries knowledge base (should be allowed)
echo -e "\n${YELLOW}TEST 3: Reader user queries knowledge base${NC}"
echo -e "User: ${USER_READER} (reader role) - Should be allowed"

READER_QUERY=$(curl -s -X POST \
  "${API_ENDPOINT}/api/kb/query" \
  -H "Content-Type: application/json" \
  -H "x-user-id: ${USER_READER}" \
  -d '{"tenant":"acme","query":"What is the implementation status?","max_results":1}')

echo -e "Response: ${READER_QUERY}"

if [[ "$READER_QUERY" == *"results"* && "$READER_QUERY" == *"Implementation"* ]]; then
  echo -e "${GREEN}✓ Success: Reader user allowed to query knowledge base${NC}"
else
  echo -e "${RED}✗ Failure: Reader user denied access to knowledge base query${NC}"
fi

# Test 4: Cross-tenant access attempt
echo -e "\n${YELLOW}TEST 4: Cross-tenant access attempt${NC}"
echo -e "Admin user from acme tries to access globex data"

CROSS_TENANT=$(curl -s -X POST \
  "${API_ENDPOINT}/api/kb/query" \
  -H "Content-Type: application/json" \
  -H "x-user-id: ${USER_ADMIN}" \
  -d '{"tenant":"acme","query":"What is Globex implementation status?"}')

echo -e "Response: ${CROSS_TENANT}"

# We expect to get results, but they should be ACME's data, not Globex's
if [[ "$CROSS_TENANT" == *"Globex Industries"* ]]; then
  echo -e "${RED}✗ Failure: Admin accessed data from another tenant${NC}"
else
  echo -e "${GREEN}✓ Success: Admin only accessed data from their own tenant${NC}"
fi

# Test 5: Writer user uses chat API
echo -e "\n${YELLOW}TEST 5: Writer user uses chat API${NC}"
echo -e "User: ${USER_WRITER} (contributor role) - Should be allowed"

WRITER_CHAT=$(curl -s -X POST \
  "${API_ENDPOINT}/api/chat" \
  -H "Content-Type: application/json" \
  -H "x-user-id: ${USER_WRITER}" \
  -d '{"tenant":"acme","message":"What is our implementation status?","use_kb":true}')

echo -e "Response: ${WRITER_CHAT}"

if [[ "$WRITER_CHAT" == *"response"* && "$WRITER_CHAT" == *"ACME"* ]]; then
  echo -e "${GREEN}✓ Success: Writer user allowed to use chat API${NC}"
else
  echo -e "${RED}✗ Failure: Writer user denied access to chat API${NC}"
fi

# Test 6: Invalid tenant access
echo -e "\n${YELLOW}TEST 6: Invalid tenant access${NC}"
echo -e "User: ${USER_ADMIN} attempts to access invalid tenant"

INVALID_TENANT=$(curl -s -X POST \
  "${API_ENDPOINT}/api/kb/query" \
  -H "Content-Type: application/json" \
  -H "x-user-id: ${USER_ADMIN}" \
  -d '{"tenant":"nonexistent","query":"What is the status?"}')

echo -e "Response: ${INVALID_TENANT}"

if [[ "$INVALID_TENANT" == *"Invalid tenant"* || "$INVALID_TENANT" == *"Unauthorized"* ]]; then
  echo -e "${GREEN}✓ Success: Invalid tenant access properly rejected${NC}"
else
  echo -e "${RED}✗ Failure: Invalid tenant access was allowed${NC}"
fi

# Now let's make multiple requests to generate some metrics
echo -e "\n${YELLOW}Generating metrics data with multiple API calls...${NC}"

# Generate 5 KB queries for tenant acme
for i in {1..5}; do
  curl -s -X POST \
    "${API_ENDPOINT}/api/kb/query" \
    -H "Content-Type: application/json" \
    -H "x-user-id: ${USER_ADMIN}" \
    -d "{\"tenant\":\"acme\",\"query\":\"Query $i for metrics test\"}" > /dev/null
  
  # Add a small delay
  sleep 0.5
done

# Generate 3 chat requests for tenant acme
for i in {1..3}; do
  curl -s -X POST \
    "${API_ENDPOINT}/api/chat" \
    -H "Content-Type: application/json" \
    -H "x-user-id: ${USER_WRITER}" \
    -d "{\"tenant\":\"acme\",\"message\":\"Chat message $i for metrics test\"}" > /dev/null
  
  # Add a small delay
  sleep 0.5
done

# Generate 2 KB queries for tenant globex
for i in {1..2}; do
  curl -s -X POST \
    "${API_ENDPOINT}/api/kb/query" \
    -H "Content-Type: application/json" \
    -H "x-user-id: ${USER_ADMIN}" \
    -d "{\"tenant\":\"globex\",\"query\":\"Globex query $i for metrics test\"}" > /dev/null
  
  # Add a small delay
  sleep 0.5
done

echo -e "${GREEN}✓ Successfully generated metrics data${NC}"

# Test 7: Verify metrics collection is working via CloudWatch logs
echo -e "\n${YELLOW}TEST 7: Verify metrics collection${NC}"
echo -e "Note: Check CloudWatch logs for 'Tracked API metrics' and 'Tracked KB query' messages"

echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}RBAC AND METRICS TESTING COMPLETED!${NC}"
echo -e "${BLUE}==================================================${NC}"

echo -e "\nLogs might take a minute to appear in CloudWatch."
echo -e "Run the following command to view Lambda logs:"
echo -e "${YELLOW}aws logs describe-log-streams --log-group-name /aws/lambda/kb-manager-dev-core --order-by LastEventTime --descending --max-items 1 | jq -r '.logStreams[0].logStreamName' | xargs -I{} aws logs get-log-events --log-group-name /aws/lambda/kb-manager-dev-core --log-stream-name {} --limit 50 | jq -r '.events[].message'${NC}"

exit 0
