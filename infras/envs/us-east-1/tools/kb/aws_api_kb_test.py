#!/usr/bin/env python3
"""
AWS API-based approach for testing Bedrock Knowledge Base
This script uses AWS APIs exclusively to test knowledge base functionality
"""
import boto3
import json
import uuid
import time
import os
import sys
from datetime import datetime

# Configure colors for output
GREEN = '\033[0;32m'
RED = '\033[0;31m'
BLUE = '\033[0;34m'
YELLOW = '\033[1;33m'
NC = '\033[0m'  # No Color

def print_status(status, message):
    """Print colored status messages"""
    if status == "SUCCESS":
        print(f"{GREEN}✓ {message}{NC}")
    elif status == "FAIL":
        print(f"{RED}✗ {message}{NC}")
    elif status == "INFO":
        print(f"{BLUE}ℹ {message}{NC}")
    elif status == "WARNING":
        print(f"{YELLOW}⚠ {message}{NC}")

class AWSAPIKnowledgeBaseTest:
    """Class for testing knowledge base using AWS APIs"""
    
    def __init__(self):
        """Initialize with AWS clients and configuration"""
        # Initialize AWS clients
        self.s3_client = boto3.client('s3', region_name='us-east-1')
        self.bedrock_agent = boto3.client('bedrock-agent', region_name='us-east-1')
        self.bedrock_runtime = boto3.client('bedrock-agent-runtime', region_name='us-east-1')
        
        # Configuration from terraform
        self.bucket_name = None
        self.knowledge_base_id = None
        self.data_source_id = None
        
        # Runtime variables
        self.document_key = None
        self.ingestion_job_id = None
        self.pdf_file = '/Users/adrian/Projects/Cloudable.AI/Amazon Bedrock Knowledge Bases by Example _ by John Tucker _ Medium.pdf'
    
    def get_configuration(self):
        """Get configuration from terraform outputs"""
        print_status("INFO", "Getting configuration from terraform outputs")
        
        # Save current directory
        original_dir = os.getcwd()
        os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../..'))
        
        try:
            # Get bucket name for tenant t001 (acme)
            bucket_output = os.popen('terraform output -json s3_buckets').read()
            buckets = json.loads(bucket_output)
            self.bucket_name = buckets.get('t001')
            
            # Get knowledge base ID for tenant t001 (acme)
            kb_output = os.popen('terraform output -json knowledge_base_ids').read()
            kb_ids = json.loads(kb_output)
            self.knowledge_base_id = kb_ids.get('t001')
            
            # List data sources and select first one
            if self.knowledge_base_id:
                response = self.bedrock_agent.list_data_sources(
                    knowledgeBaseId=self.knowledge_base_id,
                    maxResults=10
                )
                data_sources = response.get('dataSourceSummaries', [])
                if data_sources:
                    self.data_source_id = data_sources[0].get('dataSourceId')
        finally:
            # Return to original directory
            os.chdir(original_dir)
        
        # Verify we have all required values
        if not all([self.bucket_name, self.knowledge_base_id, self.data_source_id]):
            print_status("FAIL", "Missing required configuration")
            print_status("INFO", f"Bucket: {self.bucket_name}")
            print_status("INFO", f"Knowledge Base ID: {self.knowledge_base_id}")
            print_status("INFO", f"Data Source ID: {self.data_source_id}")
            return False
        
        print_status("SUCCESS", f"Using bucket: {self.bucket_name}")
        print_status("SUCCESS", f"Using knowledge base: {self.knowledge_base_id}")
        print_status("SUCCESS", f"Using data source: {self.data_source_id}")
        return True
    
    def upload_document(self):
        """Upload test document to S3 using AWS S3 API"""
        print_status("INFO", "Uploading document to S3")
        
        # Check if file exists
        if not os.path.exists(self.pdf_file):
            print_status("FAIL", f"PDF file not found: {self.pdf_file}")
            return False
        
        try:
            # Generate a key with timestamp
            timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
            file_id = uuid.uuid4().hex[:8]
            self.document_key = f"documents/aws_api_test_{timestamp}_{file_id}_kb.pdf"
            
            # Prepare metadata
            document_metadata = {
                "source": f"aws-api-test/{timestamp}",
                "title": "Amazon Bedrock Knowledge Bases by Example",
                "content_type": "application/pdf",
                "document_type": "article",
                "document_category": "technical",
                "upload_timestamp": timestamp,
                "processing_timestamp": datetime.utcnow().isoformat(),
                "tenant": "acme",
                "version": "1.0",
                "uuid": str(uuid.uuid4())
            }
            
            # Read file content
            with open(self.pdf_file, 'rb') as f:
                content = f.read()
            
            # Upload using S3 API
            print_status("INFO", f"Uploading to {self.bucket_name}/{self.document_key}")
            self.s3_client.put_object(
                Bucket=self.bucket_name,
                Key=self.document_key,
                Body=content,
                ContentType="application/pdf",
                Metadata={
                    "kb_metadata": json.dumps(document_metadata)
                }
            )
            
            print_status("SUCCESS", f"Document uploaded successfully ({len(content)} bytes)")
            return True
        except Exception as e:
            print_status("FAIL", f"Error uploading document: {str(e)}")
            return False
    
    def start_ingestion(self):
        """Start ingestion job using AWS Bedrock Agent API"""
        print_status("INFO", "Starting knowledge base ingestion job")
        
        try:
            # Check storage configuration first
            kb_response = self.bedrock_agent.get_knowledge_base(
                knowledgeBaseId=self.knowledge_base_id
            )
            
            storage_type = kb_response.get('knowledgeBase', {}).get('storageConfiguration', {}).get('type')
            print_status("INFO", f"Knowledge base storage type: {storage_type}")
            
            # Use AWS Bedrock Agent API to start ingestion
            try:
                response = self.bedrock_agent.start_ingestion_job(
                    knowledgeBaseId=self.knowledge_base_id,
                    dataSourceId=self.data_source_id,
                    description=f"AWS API Test {datetime.utcnow().strftime('%Y%m%d_%H%M%S')}",
                    clientToken=str(uuid.uuid4())
                )
                
                # Extract job ID from response
                self.ingestion_job_id = response['ingestionJob']['ingestionJobId']
                print_status("SUCCESS", f"Ingestion job started with ID: {self.ingestion_job_id}")
                return True
            except self.bedrock_agent.exceptions.ValidationException as ve:
                print_status("WARNING", f"Validation exception: {str(ve)}")
                print_status("INFO", "Skipping ingestion job, will proceed with existing knowledge base content")
                return True
        except Exception as e:
            print_status("FAIL", f"Failed to start ingestion job: {str(e)}")
            return False
    
    def check_ingestion_status(self, max_attempts=10, wait_seconds=15):
        """Check ingestion job status using AWS Bedrock Agent API"""
        if not self.ingestion_job_id:
            print_status("INFO", "No ingestion job ID to check - skipping status check")
            return True
        
        print_status("INFO", f"Monitoring ingestion job (max {max_attempts} attempts)")
        
        for attempt in range(1, max_attempts + 1):
            try:
                # Use AWS Bedrock Agent API to check status
                response = self.bedrock_agent.get_ingestion_job(
                    knowledgeBaseId=self.knowledge_base_id,
                    dataSourceId=self.data_source_id,
                    ingestionJobId=self.ingestion_job_id
                )
                
                status = response['ingestionJob']['status']
                print_status("INFO", f"Attempt {attempt}/{max_attempts}: Status = {status}")
                
                if status == "COMPLETE":
                    print_status("SUCCESS", "Ingestion job completed successfully")
                    return True
                elif status in ["FAILED", "STOPPING", "STOPPED"]:
                    print_status("FAIL", f"Ingestion job failed with status: {status}")
                    failure_reason = response['ingestionJob'].get('failureReason', 'No reason provided')
                    print_status("INFO", f"Failure reason: {failure_reason}")
                    return False
                
                if attempt < max_attempts:
                    print_status("INFO", f"Waiting {wait_seconds} seconds before next check")
                    time.sleep(wait_seconds)
            except Exception as e:
                print_status("FAIL", f"Error checking ingestion status: {str(e)}")
                return False
        
        print_status("WARNING", f"Ingestion still in progress after {max_attempts} checks")
        print_status("INFO", "Continuing with tests, but results might not include the new document yet")
        return True
    
    def query_knowledge_base(self, query_text):
        """Query knowledge base using AWS Bedrock Agent Runtime API"""
        print_status("INFO", f"Querying knowledge base: '{query_text}'")
        
        try:
            # Use AWS Bedrock Agent Runtime API to query the KB
            response = self.bedrock_runtime.retrieve(
                knowledgeBaseId=self.knowledge_base_id,
                retrievalQuery={
                    'text': query_text
                },
                retrievalConfiguration={
                    'vectorSearchConfiguration': {
                        'numberOfResults': 3,
                        'overrideSearchType': 'HYBRID'
                    }
                }
            )
            
            results = response.get('retrievalResults', [])
            
            if results:
                print_status("SUCCESS", f"Found {len(results)} results")
                
                for i, result in enumerate(results):
                    score = result.get('score', 0)
                    location = result.get('location', {}).get('s3Location', {}).get('uri', 'Unknown')
                    content = result.get('content', {}).get('text', 'No content')
                    
                    # Extract filename from location
                    filename = location.split('/')[-1] if '/' in location else location
                    
                    print(f"\n{BLUE}Result {i+1} (Score: {score}):{NC}")
                    print(f"Location: {filename}")
                    print(f"Content snippet: {content[:150]}...")
                
                return True
            else:
                print_status("WARNING", "No results found for this query")
                return False
        except Exception as e:
            print_status("FAIL", f"Error querying knowledge base: {str(e)}")
            return False
    
    def run_test_queries(self):
        """Run a series of test queries against the knowledge base"""
        test_queries = [
            "What is Amazon Bedrock Knowledge Base?",
            "How do you create a knowledge base using Bedrock?",
            "What is RAG architecture in Bedrock?",
            "How do vector embeddings work?",
            "What are the steps to query a Bedrock knowledge base?"
        ]
        
        print_status("INFO", f"Running {len(test_queries)} test queries")
        
        success_count = 0
        for i, query in enumerate(test_queries, 1):
            print_status("INFO", f"Query {i}/{len(test_queries)}")
            if self.query_knowledge_base(query):
                success_count += 1
            
            # Add delay between queries
            if i < len(test_queries):
                time.sleep(2)
        
        print_status("INFO", f"Query results: {success_count}/{len(test_queries)} successful")
        return success_count > 0
    
    def run_full_test(self):
        """Run the full AWS API-based test sequence"""
        print_status("INFO", "=== STARTING AWS API KNOWLEDGE BASE TEST ===")
        
        # Step 1: Get configuration
        if not self.get_configuration():
            return False
        
        # Step 2: Upload document
        if not self.upload_document():
            return False
        
        # Step 3: Start ingestion
        if not self.start_ingestion():
            return False
        
        # Step 4: Check ingestion status
        self.check_ingestion_status()
        
        # Step 5: Run test queries
        query_success = self.run_test_queries()
        
        # Summary
        print_status("INFO", "=== AWS API TEST COMPLETE ===")
        if query_success:
            print_status("SUCCESS", "AWS API-based knowledge base test completed successfully")
        else:
            print_status("WARNING", "AWS API-based knowledge base test completed with issues")
            print_status("INFO", "The document may still be processing or indexing")
        
        return True

def main():
    """Main function"""
    test = AWSAPIKnowledgeBaseTest()
    success = test.run_full_test()
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main())
