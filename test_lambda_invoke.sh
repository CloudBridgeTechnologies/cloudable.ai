#!/bin/bash
# Test script for Lambda invocation with proper JSON payload

REGION="us-east-1"
TENANT="t001"
TEST_FILE="test_document.md"

echo "Invoking Lambda with properly escaped JSON..."

# Create proper JSON payload
BODY=$(cat << EOF
{
  "tenant_id": "${TENANT}",
  "filename": "${TEST_FILE}"
}
EOF
)

ESCAPED_BODY=$(echo $BODY | jq -c -R '.')

PAYLOAD=$(cat << EOF
{
  "path": "/kb/upload-url",
  "httpMethod": "POST",
  "body": ${ESCAPED_BODY}
}
EOF
)

echo "Payload:"
echo "$PAYLOAD" | jq .

aws lambda invoke \
  --function-name kb-manager-dev \
  --payload "$PAYLOAD" \
  --cli-binary-format raw-in-base64-out \
  /tmp/lambda_response.json \
  --region ${REGION}

echo "Response:"
cat /tmp/lambda_response.json | jq .
