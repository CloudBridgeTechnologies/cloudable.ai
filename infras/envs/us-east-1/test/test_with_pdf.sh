#!/bin/bash
# Script to test the system with a specific PDF document

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Testing with PDF Document${NC}"
echo -e "${BLUE}========================================${NC}"

# Check if PDF path is provided
if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage: $0 <path-to-pdf-file>${NC}"
    echo "Example: $0 /path/to/your/bedrock-pdf.pdf"
    exit 1
fi

PDF_PATH="$1"

# Check if file exists
if [ ! -f "$PDF_PATH" ]; then
    echo -e "${RED}Error: PDF file not found at $PDF_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}PDF file found: $PDF_PATH${NC}"

# Get API configuration
cd /Users/adrian/Projects/Cloudable.AI/infras/envs/us-east-1/

API_ENDPOINT=$(terraform output -raw secure_api_endpoint 2>/dev/null || echo "")
API_KEY=$(terraform output -raw secure_api_key 2>/dev/null || echo "")

if [ -z "$API_ENDPOINT" ] || [ -z "$API_KEY" ]; then
    echo -e "${RED}Error: Could not get API configuration from Terraform${NC}"
    echo "Please ensure Terraform is applied and outputs are available"
    exit 1
fi

echo -e "${GREEN}API Endpoint: $API_ENDPOINT${NC}"

# Copy PDF to resources directory
echo -e "${BLUE}Copying PDF to resources directory...${NC}"
cp "$PDF_PATH" /Users/adrian/Projects/Cloudable.AI/infras/envs/us-east-1/resources/bedrock-test.pdf

# Create a modified upload script for the PDF
echo -e "${BLUE}Creating PDF upload script...${NC}"
cat > /Users/adrian/Projects/Cloudable.AI/infras/envs/us-east-1/tools/upload/upload_pdf_test.py << 'EOF'
#!/usr/bin/env python3
import boto3
import json
import uuid
import time
from datetime import datetime

# Configure AWS clients
s3_client = boto3.client('s3', region_name='us-east-1')
bedrock_agent = boto3.client('bedrock-agent', region_name='us-east-1')
bedrock_runtime = boto3.client('bedrock-agent-runtime', region_name='us-east-1')

# Configuration
BUCKET_NAME = 'cloudable-kb-dev-us-east-1-acme'
KNOWLEDGE_BASE_ID = 'D225WCEF2H'
DATA_SOURCE_ID = 'GHEBQFMETM'
PDF_FILE = '/Users/adrian/Projects/Cloudable.AI/infras/envs/us-east-1/resources/bedrock-test.pdf'

def upload_pdf_with_metadata():
    """Upload the PDF file with proper metadata structure"""
    timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
    file_id = uuid.uuid4().hex[:8]
    
    metadata = {
        "source": f"pdf-test-upload/{timestamp}",
        "title": "Bedrock Test PDF",
        "content_type": "application/pdf",
        "document_type": "pdf",
        "upload_timestamp": timestamp,
        "processing_timestamp": datetime.utcnow().isoformat(),
        "tenant": "acme",
        "version": "1.0",
        "uuid": str(uuid.uuid4())
    }
    
    with open(PDF_FILE, 'rb') as f:
        content = f.read()
    
    key = f"documents/pdf_test_{timestamp}_{file_id}_bedrock.pdf"
    
    print(f"Uploading PDF to {BUCKET_NAME}/{key}")
    print(f"File size: {len(content)} bytes")
    print(f"Metadata: {json.dumps(metadata, indent=2)}")
    
    s3_client.put_object(
        Bucket=BUCKET_NAME,
        Key=key,
        Body=content,
        ContentType="application/pdf",
        Metadata={
            "kb_metadata": json.dumps(metadata)
        },
        ServerSideEncryption="aws:kms",
        SSEKMSKeyId="arn:aws:kms:us-east-1:951296734820:key/782066fb-7441-40ce-88be-66f2812a93f3"
    )
    
    print(f"PDF uploaded successfully to {key}")
    return key

def trigger_ingestion(document_key):
    """Trigger an ingestion job for the uploaded document"""
    try:
        response = bedrock_agent.list_ingestion_jobs(
            knowledgeBaseId=KNOWLEDGE_BASE_ID,
            dataSourceId=DATA_SOURCE_ID,
            maxResults=5
        )
        
        jobs = response.get('ingestionJobSummaries', [])
        if jobs:
            latest_job = jobs[0]
            if latest_job['status'] in ['IN_PROGRESS', 'STARTING']:
                print(f"Existing ingestion job in progress: {latest_job['ingestionJobId']}")
                return latest_job['ingestionJobId']
        
        print(f"Starting ingestion job for PDF: {document_key}")
        response = bedrock_agent.start_ingestion_job(
            knowledgeBaseId=KNOWLEDGE_BASE_ID,
            dataSourceId=DATA_SOURCE_ID,
            description=f"PDF test ingestion for {document_key}",
            clientToken=str(uuid.uuid4())
        )
        
        job_id = response['ingestionJob']['ingestionJobId']
        print(f"Ingestion job started with ID: {job_id}")
        return job_id
        
    except Exception as e:
        print(f"Failed to start ingestion job: {str(e)}")
        return None

def test_queries():
    """Test various queries against the knowledge base"""
    queries = [
        "What is in this PDF document?",
        "What are the main topics covered?",
        "What are the key points?",
        "What is the document about?"
    ]
    
    for query in queries:
        try:
            print(f"\nTesting query: '{query}'")
            response = bedrock_runtime.retrieve(
                knowledgeBaseId=KNOWLEDGE_BASE_ID,
                retrievalQuery={'text': query},
                retrievalConfiguration={
                    'vectorSearchConfiguration': {
                        'numberOfResults': 3,
                        'overrideSearchType': 'HYBRID'
                    }
                }
            )
            
            results = response.get('retrievalResults', [])
            if results:
                print(f"Found {len(results)} results:")
                for i, result in enumerate(results):
                    score = result.get('score', 0)
                    content = result.get('content', {}).get('text', 'No content')
                    print(f"  Result {i+1} (Score: {score}): {content[:100]}...")
            else:
                print("No results found")
                
        except Exception as e:
            print(f"Error querying knowledge base: {str(e)}")

def main():
    print("=== Starting PDF Upload and Test ===")
    
    # Upload PDF
    document_key = upload_pdf_with_metadata()
    
    # Wait for S3 to process
    print("Waiting for S3 to process...")
    time.sleep(5)
    
    # Trigger ingestion
    job_id = trigger_ingestion(document_key)
    
    if job_id:
        print("Waiting for ingestion to complete...")
        time.sleep(60)  # Wait 1 minute for processing
        
        # Test queries
        test_queries()
    
    print("\n=== PDF Test Complete ===")
    print(f"Document key: {document_key}")
    print("Check CloudWatch logs for processing details")

if __name__ == "__main__":
    main()
EOF

# Make the script executable
chmod +x /Users/adrian/Projects/Cloudable.AI/infras/envs/us-east-1/tools/upload/upload_pdf_test.py

# Run the PDF upload and test
echo -e "${BLUE}Running PDF upload and test...${NC}"
cd /Users/adrian/Projects/Cloudable.AI/infras/envs/us-east-1/tools/upload/
python3 upload_pdf_test.py

echo ""
echo -e "${GREEN}PDF upload and test completed!${NC}"
echo -e "${BLUE}Next steps:${NC}"
echo "1. Check CloudWatch logs for processing details"
echo "2. Test API endpoints with the uploaded document"
echo "3. Use the knowledge base query tool to search the PDF content"
echo ""
echo -e "${YELLOW}To test API endpoints:${NC}"
echo "curl -X POST '$API_ENDPOINT/kb/query' \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -H 'x-api-key: $API_KEY' \\"
echo "  -d '{\"tenant_id\":\"acme\",\"customer_id\":\"c001\",\"query\":\"What is in the PDF?\"}'"
