# AWS Serverless Document Summarization System

Complete serverless API for document upload, automatic summarization using Amazon Bedrock (Claude Sonnet), and summary retrieval.

## Architecture

- **API Gateway**: REST API with `/upload` and `/summary/{documentName}` endpoints
- **Lambda Functions**: 
  - `upload_handler`: Handles document uploads to S3
  - `summarizer`: Triggered by S3 events, processes documents with Bedrock
  - `summary_retriever`: Retrieves summaries by document name
- **S3 Bucket**: 
  - `uploads/` - Original documents
  - `summaries/` - Generated summaries
- **Amazon Bedrock**: Claude Sonnet 3 model for summarization

## Deployment

### Prerequisites
- AWS CLI configured
- Terraform >= 1.0.0
- Python 3.12
- Bedrock model access enabled in your AWS account

### Deploy
```bash
chmod +x deploy.sh
./deploy.sh
```

### Output
The deployment will output:
- API Endpoint URL
- S3 Bucket Name

## API Usage

### 1. Upload Document
```bash
curl -X POST https://<API_ENDPOINT>/upload \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "document.txt",
    "file_content": "<base64_encoded_content>"
  }'
```

Response:
```json
{
  "message": "Document uploaded successfully",
  "document_id": "uuid",
  "filename": "document.txt",
  "s3_key": "uploads/uuid_document.txt",
  "timestamp": "2024-01-01T00:00:00"
}
```

### 2. Retrieve Summary
```bash
curl -X GET https://<API_ENDPOINT>/summary/{documentName}
```

Response:
```json
{
  "original_document": "document.txt",
  "summary": "Summary text...",
  "timestamp": "2024-01-01T00:00:00",
  "processed_at": "2024-01-01 00:00:00 UTC"
}
```

## Testing

```bash
chmod +x test_api.sh
./test_api.sh <API_ENDPOINT>
```

## Supported Formats
- PDF (.pdf)
- Text (.txt)
- Word (.docx)

## Configuration

### Lambda Settings
- **Summarizer**: 512MB memory, 300s timeout, Python 3.12
- **Upload Handler**: 256MB memory, 30s timeout, Python 3.12
- **Summary Retriever**: 256MB memory, 30s timeout, Python 3.12

### Bedrock Model
- Model: `meta.llama3-8b-instruct-v1:0` (Llama 3 8B)
- Max tokens: 512
- Document limit: 2000 characters (optimized for smaller model)

## Cost Estimation

For 300 customers with moderate usage:
- Lambda: ~$10/month
- S3: ~$5/month
- API Gateway: ~$3/month
- Bedrock: Variable based on token usage (~$20-40/month with Llama 3 8B)

## Cleanup

```bash
cd terraform
terraform destroy -auto-approve
```
