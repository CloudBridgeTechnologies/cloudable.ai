#!/bin/bash
# Test script just for the upload URL endpoint

API_ID="pdoq719mx2"
REGION="us-east-1"
API_KEY="sZI5RibzbE2WY1kRw4zcX1iSXhSnIqAoauc2XezS"
API_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/dev"

echo "Testing upload URL endpoint with verbose output..."

# Create test payload
cat << EOF > upload_url_payload.json
{
  "tenant_id": "acme",
  "filename": "test_document.md"
}
EOF

echo "Request payload:"
cat upload_url_payload.json

# Send the request with verbose output
curl -v -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d @upload_url_payload.json \
  ${API_URL}/kb/upload-url

echo -e "\n\nDone."
