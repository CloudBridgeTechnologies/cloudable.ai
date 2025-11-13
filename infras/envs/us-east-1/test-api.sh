#!/bin/bash

# Extract API endpoint and key from Terraform
API_ENDPOINT=$(terraform output -raw secure_api_endpoint)
API_KEY=$(terraform output -raw secure_api_key)

echo "=== RUNNING API SECURITY TESTS ==="
echo "Starting API Security Tests"
echo "API Endpoint: $API_ENDPOINT"
echo "API Key: ${API_KEY:0:7}...${API_KEY: -5} (truncated for security)"

echo -e "\n===== Testing Chat API with API Key ====="
curl -X POST "$API_ENDPOINT/chat" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{"tenant_id":"t001","customer_id":"c001","message":"What is the company policy?"}'

echo -e "\n\n===== Testing Chat API without API Key (should fail) ====="
curl -X POST "$API_ENDPOINT/chat" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id":"t001","customer_id":"c001","message":"What is the company policy?"}'

echo -e "\n\n===== Testing Summary Endpoint with API Key ====="
curl -X GET "$API_ENDPOINT/summary/t001/doc123" \
  -H "x-api-key: $API_KEY"

echo -e "\n\n===== Testing Summary Endpoint without API Key (should fail) ====="
curl -X GET "$API_ENDPOINT/summary/t001/doc123"

echo -e "\n\n===== Test Complete ====="
