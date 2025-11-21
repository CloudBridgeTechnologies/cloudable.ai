#!/bin/bash
# KB Query endpoint test with proper payload format

API_ID="2tol4asisa"
REGION="us-east-1" 
API_KEY="sZI5RibzbE2WY1kRw4zcX1iSXhSnIqAoauc2XezS"

# Create test payload with tenant_id and customer_id
cat << EOF > kb_query_payload.json
{
  "tenant_id": "acme",
  "customer_id": "test-customer",
  "query": "What are the key features of Cloudable.AI?"
}
EOF

echo "Sending API request to the /dev/kb/query endpoint..."
echo "Request payload:"
cat kb_query_payload.json

echo -e "\nResponse:"
curl -s -X POST \
  "https://${API_ID}.execute-api.${REGION}.amazonaws.com/dev/kb/query" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d @kb_query_payload.json | jq .