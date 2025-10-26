# Cloudable.AI Testing Guide

This guide provides comprehensive instructions for testing the dual-path document processing system locally.

## Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **Terraform applied** with all resources deployed
3. **Python 3.8+** installed
4. **Postman** (optional, for GUI testing)

## Quick Start Testing

### Step 1: Get API Configuration

```bash
cd /Users/adrian/Projects/Cloudable.AI/infras/envs/us-east-1/test/
chmod +x get_api_config.sh
./get_api_config.sh
```

This will:
- Extract API endpoint and key from Terraform
- Update Postman environment file
- Create a quick test script

### Step 2: Run Quick API Tests

```bash
./quick_test.sh
```

This tests:
- Chat API with authentication
- Knowledge Base Query API
- Authentication failure (without API key)

### Step 3: Run Comprehensive Tests

```bash
chmod +x comprehensive_local_test.sh
./comprehensive_local_test.sh
```

## Testing with Your Bedrock PDF

### Method 1: Direct Upload Script

1. **Place your PDF** in the resources directory:
   ```bash
   cp your-bedrock-pdf.pdf /Users/adrian/Projects/Cloudable.AI/infras/envs/us-east-1/resources/
   ```

2. **Modify the upload script** to use your PDF:
   ```bash
   cd /Users/adrian/Projects/Cloudable.AI/infras/envs/us-east-1/tools/upload/
   # Edit direct_upload_with_metadata.py and change POLICY_FILE to your PDF
   ```

3. **Run the upload script**:
   ```bash
   python3 direct_upload_with_metadata.py
   ```

### Method 2: Using API Upload Form

1. **Get upload form**:
   ```bash
   curl -X POST "$API_ENDPOINT/kb/upload-form" \
     -H "Content-Type: application/json" \
     -H "x-api-key: $API_KEY" \
     -d '{"tenant_id":"acme","filename":"bedrock-pdf.pdf","content_type":"application/pdf"}'
   ```

2. **Use the presigned URL** from the response to upload your PDF

3. **Sync the document**:
   ```bash
   curl -X POST "$API_ENDPOINT/kb/sync" \
     -H "Content-Type: application/json" \
     -H "x-api-key: $API_KEY" \
     -d '{"tenant_id":"acme","document_key":"documents/bedrock-pdf.pdf"}'
   ```

## Postman Testing

### Import Collection and Environment

1. **Open Postman**
2. **Import Collection**: File → Import → Select `postman_collection.json`
3. **Import Environment**: File → Import → Select `environment.json`
4. **Select Environment**: Use the dropdown in the top right

### Test Scenarios

#### 1. Authentication Tests
- **Chat API (With Auth)**: Should return 200
- **Chat API (Without Auth)**: Should return 403

#### 2. Knowledge Base Tests
- **KB Query**: Test various queries about your PDF content
- **KB Upload Form**: Get presigned URL for upload
- **KB Sync**: Trigger document processing
- **KB Ingestion Status**: Check processing status

#### 3. Summary API Tests
- **Get Document Summary**: Retrieve pre-generated summaries

#### 4. Error Handling Tests
- **Invalid Payload**: Should return 400
- **Missing Fields**: Should return 400

## Document Processing Workflow Testing

### 1. Upload Document
```bash
# Using direct upload
cd /Users/adrian/Projects/Cloudable.AI/infras/envs/us-east-1/tools/upload/
python3 direct_upload_with_metadata.py
```

### 2. Monitor Processing
```bash
# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/s3-helper"
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/document-summarizer"
```

### 3. Test Knowledge Base
```bash
cd /Users/adrian/Projects/Cloudable.AI/infras/envs/us-east-1/tools/kb/
python3 kb_query_wrapper.py "What is in the Bedrock PDF?"
```

### 4. Test Summary Retrieval
```bash
# Get document ID from upload response
curl -X GET "$API_ENDPOINT/summary/acme/DOCUMENT_ID" \
  -H "x-api-key: $API_KEY"
```

## Expected Results

### Successful Document Processing
1. **S3 Helper Lambda** processes the document
2. **Document Summarizer Lambda** generates a summary
3. **Knowledge Base** ingests the document
4. **API endpoints** return relevant content

### API Response Examples

#### Chat API Response
```json
{
  "response": "Based on the company policies, new employees receive 15 days of paid vacation annually...",
  "sources": ["documents/policy-document.pdf"],
  "confidence": 0.95
}
```

#### KB Query Response
```json
{
  "results": [
    {
      "content": "New employees: 15 days paid vacation annually",
      "score": 0.89,
      "source": "documents/policy-document.pdf"
    }
  ]
}
```

#### Summary Response
```json
{
  "document_id": "12345",
  "summary": "Executive Overview: This document outlines company policies...",
  "metadata": {
    "title": "Company Policies",
    "generated_at": "2024-01-01T00:00:00Z"
  }
}
```

## Troubleshooting

### Common Issues

1. **API Key Issues**
   - Verify API key is correct
   - Check API key is included in headers

2. **Document Processing Failures**
   - Check CloudWatch logs
   - Verify S3 bucket permissions
   - Check Lambda function logs

3. **Knowledge Base Issues**
   - Verify document ingestion status
   - Check OpenSearch configuration
   - Review Bedrock Knowledge Base status

### Debug Commands

```bash
# Check API Gateway logs
aws logs describe-log-groups --log-group-name-prefix "/aws/apigateway"

# Check Lambda function status
aws lambda list-functions --query 'Functions[?contains(FunctionName, `cloudable`)].{Name:FunctionName,State:State}'

# Check S3 bucket contents
aws s3 ls s3://your-tenant-bucket/documents/
aws s3 ls s3://your-summaries-bucket/summaries/
```

## Performance Testing

### Load Testing with curl

```bash
# Test multiple concurrent requests
for i in {1..10}; do
  curl -X POST "$API_ENDPOINT/chat" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $API_KEY" \
    -d '{"tenant_id":"acme","customer_id":"c001","message":"Test message '$i'"}' &
done
wait
```

### Monitoring

- **CloudWatch Metrics**: Monitor Lambda invocations, errors, duration
- **API Gateway Metrics**: Monitor request count, latency, error rates
- **S3 Metrics**: Monitor storage usage, request patterns

## Security Testing

### Authentication Tests
- Test with valid API key ✓
- Test without API key (should fail) ✓
- Test with invalid API key (should fail) ✓

### Authorization Tests
- Test cross-tenant access (should be blocked)
- Test with different customer IDs
- Verify tenant isolation

### Input Validation Tests
- Test with malformed JSON
- Test with oversized payloads
- Test with special characters
- Test SQL injection attempts

## Next Steps

After successful testing:

1. **Deploy to Production**: Use the same testing procedures
2. **Set up Monitoring**: Configure CloudWatch alarms
3. **Performance Optimization**: Based on test results
4. **Security Hardening**: Address any security findings
5. **Documentation**: Update API documentation with test results
