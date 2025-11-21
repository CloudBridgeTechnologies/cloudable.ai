#!/bin/bash
# Corrected Chat API test with proper payload format

API_ID="2tol4asisa"
REGION="us-east-1" 
API_KEY="sZI5RibzbE2WY1kRw4zcX1iSXhSnIqAoauc2XezS"

# Create test payload with tenant_id and customer_id
cat << EOF > chat_payload.json
{
  "tenant_id": "acme",
  "customer_id": "test-customer",
  "message": "What are the key features of Cloudable.AI?",
  "conversation_id": "test-chat-1"
}
EOF

echo "Sending API request to the /dev/chat endpoint..."
echo "Request payload:"
cat chat_payload.json

echo -e "\nResponse:"
curl -s -X POST \
  "https://${API_ID}.execute-api.${REGION}.amazonaws.com/dev/chat" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d @chat_payload.json | jq .
