#!/bin/bash
# Test script just for the upload URL endpoint with correct tenant ID

API_ID="pdoq719mx2"
REGION="us-east-1"
API_KEY="sZI5RibzbE2WY1kRw4zcX1iSXhSnIqAoauc2XezS"
API_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/dev"

echo "Testing upload URL endpoint directly with Lambda..."

# Invoke Lambda directly
aws lambda invoke \
  --function-name kb-manager-dev \
  --payload '{"path": "/kb/upload-url", "httpMethod": "POST", "body": "{\"tenant_id\":\"t001\",\"filename\":\"test_document.md\"}"}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/upload_url_response.json \
  --region us-east-1

echo "Lambda response:"
cat /tmp/upload_url_response.json | jq .

echo -e "\nTesting other tenant:"
aws lambda invoke \
  --function-name kb-manager-dev \
  --payload '{"path": "/kb/upload-url", "httpMethod": "POST", "body": "{\"tenant_id\":\"t002\",\"filename\":\"test_document.md\"}"}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/upload_url_response2.json \
  --region us-east-1

echo "Lambda response for t002:"
cat /tmp/upload_url_response2.json | jq .

echo -e "\nDone."
