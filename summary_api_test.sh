#!/bin/bash
# Summary API endpoint test

API_ID="pdoq719mx2"  # REST API ID
REGION="us-east-1" 
API_KEY="sZI5RibzbE2WY1kRw4zcX1iSXhSnIqAoauc2XezS"
TENANT="acme"

echo "Sending API request to the summary endpoint..."

# Test with different document IDs
echo -e "\nTesting with document_id=test_document:"
curl -s -X GET \
  "https://${API_ID}.execute-api.${REGION}.amazonaws.com/dev/summary/${TENANT}/test_document" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" | jq .

echo -e "\nTesting with document_id=test_document_e2e:"
curl -s -X GET \
  "https://${API_ID}.execute-api.${REGION}.amazonaws.com/dev/summary/${TENANT}/test_document_e2e" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" | jq .

echo -e "\nTesting with document_id=test_document_processed_summary:"
curl -s -X GET \
  "https://${API_ID}.execute-api.${REGION}.amazonaws.com/dev/summary/${TENANT}/test_document_processed_summary" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" | jq .
