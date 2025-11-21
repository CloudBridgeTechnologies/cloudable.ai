#!/bin/bash
# Simple test just for the Chat API

API_ID="2tol4asisa"
REGION="us-east-1" 
API_KEY="sZI5RibzbE2WY1kRw4zcX1iSXhSnIqAoauc2XezS"

# Create test payload
cat << EOF > test_chat.json
{
  "tenant": "acme",
  "message": "Hello",
  "conversation_id": "test-1",
  "use_kb": true
}
EOF

echo "Testing with NO stage name"
curl -v -X POST \
  "https://${API_ID}.execute-api.${REGION}.amazonaws.com/chat" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d @test_chat.json

echo -e "\n\nTesting with 'dev' stage name"
curl -v -X POST \
  "https://${API_ID}.execute-api.${REGION}.amazonaws.com/dev/chat" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d @test_chat.json

echo -e "\n\nTesting with '$default' stage name"
curl -v -X POST \
  "https://${API_ID}.execute-api.${REGION}.amazonaws.com/\$default/chat" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d @test_chat.json
