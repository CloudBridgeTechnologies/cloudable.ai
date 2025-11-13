# Cloudable.AI API Testing Guide

This guide explains how to test the Cloudable.AI APIs to ensure proper functionality.

## API Overview

Cloudable.AI exposes several API endpoints for different purposes:

1. **Knowledge Base (KB) Query API** - Query the knowledge base with natural language questions
2. **Chat API** - Interact with the agent using conversational interfaces
3. **Summary API** - Retrieve or generate document summaries
4. **Upload URL API** - Get presigned URLs for document uploads
5. **KB Sync API** - Trigger synchronization of documents with the knowledge base

## Prerequisites

- AWS CLI configured with appropriate permissions
- API Gateway endpoint and stage information
- API key for authentication
- Tenant ID for multi-tenant isolation
- A customer ID for Chat API tests

## Testing with the Test Script

We've created a convenient script to test all the API endpoints:

```bash
./test_api_endpoints.sh
```

Before running the script, make sure to update the following variables in the script:

```bash
API_GATEWAY_ID="4momcmaa07"  # Replace with your actual API Gateway ID
API_GATEWAY_STAGE="dev"
REGION="us-east-1"
API_KEY="REPLACE_WITH_ACTUAL_API_KEY"  # Replace with your actual API Key
TENANT_ID="t001"
CUSTOMER_ID="user123"
DOCUMENT_ID="test-doc-123"
```

### Getting Your API Key

To retrieve your API key from AWS:

```bash
aws apigateway get-api-keys --query "items[?name=='cloudable-api-key-dev'].id" --output text
aws apigateway get-api-key --api-key <key-id> --include-value --query "value" --output text
```

Replace `<key-id>` with the ID from the first command.

## Manual Testing with Curl

You can also manually test each endpoint with curl:

### 1. Knowledge Base Query API

```bash
curl -X POST \
  https://{API_GATEWAY_ID}.execute-api.{REGION}.amazonaws.com/{STAGE}/kb/query \
  -H "Content-Type: application/json" \
  -H "x-api-key: {API_KEY}" \
  -d '{
    "tenant_id": "t001",
    "query": "What are the AI services offered by AWS?",
    "max_results": 3
  }'
```

### 2. Chat API

```bash
curl -X POST \
  https://{API_GATEWAY_ID}.execute-api.{REGION}.amazonaws.com/{STAGE}/chat \
  -H "Content-Type: application/json" \
  -H "x-api-key: {API_KEY}" \
  -d '{
    "tenant_id": "t001",
    "customer_id": "user123",
    "message": "What is the status of my journey?",
    "session_id": "test-session-123"
  }'
```

### 3. Summary API (GET)

```bash
curl -X GET \
  https://{API_GATEWAY_ID}.execute-api.{REGION}.amazonaws.com/{STAGE}/summary/t001/test-doc-123 \
  -H "Content-Type: application/json" \
  -H "x-api-key: {API_KEY}"
```

### 4. Summary API (POST)

```bash
curl -X POST \
  https://{API_GATEWAY_ID}.execute-api.{REGION}.amazonaws.com/{STAGE}/summary/t001/test-doc-123 \
  -H "Content-Type: application/json" \
  -H "x-api-key: {API_KEY}"
```

### 5. Upload URL API

```bash
curl -X POST \
  https://{API_GATEWAY_ID}.execute-api.{REGION}.amazonaws.com/{STAGE}/kb/upload-url \
  -H "Content-Type: application/json" \
  -H "x-api-key: {API_KEY}" \
  -d '{
    "tenant_id": "t001",
    "file_name": "test-document.pdf"
  }'
```

### 6. KB Sync API

```bash
curl -X POST \
  https://{API_GATEWAY_ID}.execute-api.{REGION}.amazonaws.com/{STAGE}/kb/sync \
  -H "Content-Type: application/json" \
  -H "x-api-key: {API_KEY}" \
  -d '{
    "tenant_id": "t001",
    "document_id": "test-doc-123"
  }'
```

## Testing with Postman

For a more user-friendly testing experience, you can import the Postman collection:

1. Import the `cloudable_api_collection.json` file into Postman
2. Set up an environment with the following variables:
   - `api_gateway_id`: Your API Gateway ID
   - `api_gateway_stage`: Your API stage (e.g., "dev")
   - `region`: Your AWS region (e.g., "us-east-1")
   - `api_key`: Your API key
   - `tenant_id`: Your tenant ID (e.g., "t001")
   - `customer_id`: A test customer ID (e.g., "user123")
   - `document_id`: A test document ID (e.g., "test-doc-123")

## Troubleshooting

### Common Issues

1. **API Key Missing or Invalid**:
   - Error: "Forbidden" or status code 403
   - Solution: Ensure the API key is correct and included in the "x-api-key" header

2. **Invalid Tenant ID**:
   - Error: "Invalid tenant ID" or "Tenant not found"
   - Solution: Verify the tenant ID exists and you have permission to access it

3. **Missing Required Fields**:
   - Error: "Missing required parameters"
   - Solution: Check that all required fields are included in the request body

4. **Lambda Timeouts**:
   - Error: "Task timed out after X seconds"
   - Solution: For operations like summarization that may take longer, increase Lambda timeout settings

5. **CORS Issues**:
   - Error: Cross-Origin Request Blocked
   - Solution: Ensure CORS is properly configured on the API Gateway

### Checking Logs

To check CloudWatch logs for troubleshooting:

```bash
aws logs get-log-events \
  --log-group-name "/aws/lambda/orchestrator-dev" \
  --log-stream-name "<log-stream-name>"
```

Replace `<log-stream-name>` with the specific log stream name from the CloudWatch console.

This guide explains how to test the Cloudable.AI APIs to ensure proper functionality.

## API Overview

Cloudable.AI exposes several API endpoints for different purposes:

1. **Knowledge Base (KB) Query API** - Query the knowledge base with natural language questions
2. **Chat API** - Interact with the agent using conversational interfaces
3. **Summary API** - Retrieve or generate document summaries
4. **Upload URL API** - Get presigned URLs for document uploads
5. **KB Sync API** - Trigger synchronization of documents with the knowledge base

## Prerequisites

- AWS CLI configured with appropriate permissions
- API Gateway endpoint and stage information
- API key for authentication
- Tenant ID for multi-tenant isolation
- A customer ID for Chat API tests

## Testing with the Test Script

We've created a convenient script to test all the API endpoints:

```bash
./test_api_endpoints.sh
```

Before running the script, make sure to update the following variables in the script:

```bash
API_GATEWAY_ID="4momcmaa07"  # Replace with your actual API Gateway ID
API_GATEWAY_STAGE="dev"
REGION="us-east-1"
API_KEY="REPLACE_WITH_ACTUAL_API_KEY"  # Replace with your actual API Key
TENANT_ID="t001"
CUSTOMER_ID="user123"
DOCUMENT_ID="test-doc-123"
```

### Getting Your API Key

To retrieve your API key from AWS:

```bash
aws apigateway get-api-keys --query "items[?name=='cloudable-api-key-dev'].id" --output text
aws apigateway get-api-key --api-key <key-id> --include-value --query "value" --output text
```

Replace `<key-id>` with the ID from the first command.

## Manual Testing with Curl

You can also manually test each endpoint with curl:

### 1. Knowledge Base Query API

```bash
curl -X POST \
  https://{API_GATEWAY_ID}.execute-api.{REGION}.amazonaws.com/{STAGE}/kb/query \
  -H "Content-Type: application/json" \
  -H "x-api-key: {API_KEY}" \
  -d '{
    "tenant_id": "t001",
    "query": "What are the AI services offered by AWS?",
    "max_results": 3
  }'
```

### 2. Chat API

```bash
curl -X POST \
  https://{API_GATEWAY_ID}.execute-api.{REGION}.amazonaws.com/{STAGE}/chat \
  -H "Content-Type: application/json" \
  -H "x-api-key: {API_KEY}" \
  -d '{
    "tenant_id": "t001",
    "customer_id": "user123",
    "message": "What is the status of my journey?",
    "session_id": "test-session-123"
  }'
```

### 3. Summary API (GET)

```bash
curl -X GET \
  https://{API_GATEWAY_ID}.execute-api.{REGION}.amazonaws.com/{STAGE}/summary/t001/test-doc-123 \
  -H "Content-Type: application/json" \
  -H "x-api-key: {API_KEY}"
```

### 4. Summary API (POST)

```bash
curl -X POST \
  https://{API_GATEWAY_ID}.execute-api.{REGION}.amazonaws.com/{STAGE}/summary/t001/test-doc-123 \
  -H "Content-Type: application/json" \
  -H "x-api-key: {API_KEY}"
```

### 5. Upload URL API

```bash
curl -X POST \
  https://{API_GATEWAY_ID}.execute-api.{REGION}.amazonaws.com/{STAGE}/kb/upload-url \
  -H "Content-Type: application/json" \
  -H "x-api-key: {API_KEY}" \
  -d '{
    "tenant_id": "t001",
    "file_name": "test-document.pdf"
  }'
```

### 6. KB Sync API

```bash
curl -X POST \
  https://{API_GATEWAY_ID}.execute-api.{REGION}.amazonaws.com/{STAGE}/kb/sync \
  -H "Content-Type: application/json" \
  -H "x-api-key: {API_KEY}" \
  -d '{
    "tenant_id": "t001",
    "document_id": "test-doc-123"
  }'
```

## Testing with Postman

For a more user-friendly testing experience, you can import the Postman collection:

1. Import the `cloudable_api_collection.json` file into Postman
2. Set up an environment with the following variables:
   - `api_gateway_id`: Your API Gateway ID
   - `api_gateway_stage`: Your API stage (e.g., "dev")
   - `region`: Your AWS region (e.g., "us-east-1")
   - `api_key`: Your API key
   - `tenant_id`: Your tenant ID (e.g., "t001")
   - `customer_id`: A test customer ID (e.g., "user123")
   - `document_id`: A test document ID (e.g., "test-doc-123")

## Troubleshooting

### Common Issues

1. **API Key Missing or Invalid**:
   - Error: "Forbidden" or status code 403
   - Solution: Ensure the API key is correct and included in the "x-api-key" header

2. **Invalid Tenant ID**:
   - Error: "Invalid tenant ID" or "Tenant not found"
   - Solution: Verify the tenant ID exists and you have permission to access it

3. **Missing Required Fields**:
   - Error: "Missing required parameters"
   - Solution: Check that all required fields are included in the request body

4. **Lambda Timeouts**:
   - Error: "Task timed out after X seconds"
   - Solution: For operations like summarization that may take longer, increase Lambda timeout settings

5. **CORS Issues**:
   - Error: Cross-Origin Request Blocked
   - Solution: Ensure CORS is properly configured on the API Gateway

### Checking Logs

To check CloudWatch logs for troubleshooting:

```bash
aws logs get-log-events \
  --log-group-name "/aws/lambda/orchestrator-dev" \
  --log-stream-name "<log-stream-name>"
```

Replace `<log-stream-name>` with the specific log stream name from the CloudWatch console.
