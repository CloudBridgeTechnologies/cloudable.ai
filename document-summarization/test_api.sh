#!/bin/bash

API_ENDPOINT=$1

if [ -z "$API_ENDPOINT" ]; then
    echo "Usage: ./test_api.sh <API_ENDPOINT>"
    exit 1
fi

echo "Testing Document Summarization API..."
echo "======================================"

echo -e "\n1. Testing document upload..."
UPLOAD_RESPONSE=$(curl -s -X POST "${API_ENDPOINT}/upload" \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "test_document.txt",
    "file_content": "'$(echo "This is a test document about AWS serverless architecture. AWS Lambda is a serverless compute service. Amazon S3 provides object storage. Amazon Bedrock offers AI capabilities." | base64)'"
  }')

echo "Upload Response: $UPLOAD_RESPONSE"

DOCUMENT_ID=$(echo $UPLOAD_RESPONSE | grep -o '"document_id":"[^"]*"' | cut -d'"' -f4)
echo "Document ID: $DOCUMENT_ID"

echo -e "\n2. Waiting for summarization to complete (30 seconds)..."
sleep 30

echo -e "\n3. Retrieving summary..."
SUMMARY_RESPONSE=$(curl -s -X GET "${API_ENDPOINT}/summary/${DOCUMENT_ID}_test_document")

echo "Summary Response: $SUMMARY_RESPONSE"

echo -e "\n4. Testing non-existent document..."
NOT_FOUND_RESPONSE=$(curl -s -X GET "${API_ENDPOINT}/summary/nonexistent")
echo "Not Found Response: $NOT_FOUND_RESPONSE"

echo -e "\nTest completed!"
