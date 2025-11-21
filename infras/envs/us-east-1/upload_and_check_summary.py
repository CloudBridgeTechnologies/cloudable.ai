#!/usr/bin/env python3
"""
Test script to upload a document and verify the chunked summarization works
"""

import os
import sys
import json
import time
import uuid
import boto3
import requests
import subprocess
from datetime import datetime

# ANSI color codes for output
COLORS = {
    'INFO': '\033[0;34m',  # Blue
    'SUCCESS': '\033[0;32m',  # Green
    'WARNING': '\033[0;33m',  # Yellow
    'FAIL': '\033[0;31m',  # Red
    'RESET': '\033[0m'
}

def print_status(status, message):
    """Print colored status messages"""
    symbol = {
        'INFO': 'ℹ',
        'SUCCESS': '✓',
        'WARNING': '⚠',
        'FAIL': '✗'
    }.get(status, '?')
    
    color = COLORS.get(status, COLORS['RESET'])
    print(f"{color}{symbol} {message}{COLORS['RESET']}")

def get_terraform_outputs():
    """Get configuration from terraform outputs"""
    try:
        # Get S3 bucket from s3_buckets output (tenant t001)
        result = subprocess.run(['terraform', 'output', '-json', 's3_buckets'],
                              capture_output=True, text=True, check=True)
        s3_buckets = json.loads(result.stdout)
        bucket_name = s3_buckets['t001']
        
        # Get API key for secure REST API
        result = subprocess.run(['terraform', 'output', '-raw', 'secure_api_key'],
                              capture_output=True, text=True, check=True)
        api_key = result.stdout.strip()
        
        # Get secure REST API endpoint
        result = subprocess.run(['terraform', 'output', '-raw', 'secure_api_endpoint'],
                              capture_output=True, text=True, check=True)
        api_endpoint = result.stdout.strip()
        
        return bucket_name, api_endpoint, api_key
    except subprocess.CalledProcessError as e:
        print_status("FAIL", f"Failed to get terraform outputs: {e}")
        sys.exit(1)

def direct_upload_document(bucket_name, pdf_path):
    """Upload a document directly to S3 for processing"""
    timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
    file_id = str(uuid.uuid4())[:8]
    document_key = f"documents/raw/chunking_test_{timestamp}_{file_id}.pdf"
    
    print_status("INFO", f"Uploading document to s3://{bucket_name}/{document_key}")
    
    # Create S3 client
    s3_client = boto3.client('s3')
    
    try:
        with open(pdf_path, 'rb') as f:
            # Upload with metadata
            s3_client.put_object(
                Bucket=bucket_name,
                Key=document_key,
                Body=f,
                ContentType='application/pdf',
                Metadata={
                    'tenant_id': 't001',
                    'customer_id': 'c001',
                    'document_type': 'knowledge_base',
                    'source': 'chunking_test'
                }
            )
            
        print_status("SUCCESS", "Document uploaded successfully")
        return document_key
    except Exception as e:
        print_status("FAIL", f"Failed to upload document: {e}")
        return None

def wait_for_processing(bucket_name, original_key, max_wait=90):
    """Wait for the S3 helper to process the document"""
    s3_client = boto3.client('s3')
    
    # Expected processed key
    filename = original_key.split('/')[-1]
    base_name, extension = os.path.splitext(filename)
    processed_key = f"documents/processed/{base_name}_processed{extension}"
    
    print_status("INFO", f"Waiting for document processing (max {max_wait}s)")
    print_status("INFO", f"Looking for: {processed_key}")
    
    start_time = time.time()
    while time.time() - start_time < max_wait:
        try:
            s3_client.head_object(Bucket=bucket_name, Key=processed_key)
            print_status("SUCCESS", f"Document processed successfully: {processed_key}")
            return processed_key
        except Exception:
            time.sleep(5)
            print_status("INFO", f"Still waiting... ({int(time.time() - start_time)}s elapsed)")
    
    print_status("WARNING", "Document processing timed out")
    return None

def wait_for_summary_via_api(api_endpoint, api_key, tenant_id, document_id, max_wait=120):
    """Wait for a summary to be available via API and retrieve it"""
    headers = {
        'x-api-key': api_key,
        'Content-Type': 'application/json'
    }
    
    print_status("INFO", f"Testing POST /summary/{tenant_id}/{document_id} to trigger summarization")
    
    try:
        # First, try to trigger the summary generation
        response = requests.post(
            f"{api_endpoint}/summary/{tenant_id}/{document_id}",
            headers=headers,
            timeout=30
        )
        
        print_status("INFO", f"POST /summary response: {response.status_code}")
        if response.status_code == 200:
            print_status("SUCCESS", "Summary already exists or was created immediately")
            result = response.json()
            if 'summary' in result:
                print_status("INFO", "Summary preview:")
                print(f"\n{result['summary'][:500]}...\n")
                return result
        elif response.status_code == 202:
            print_status("INFO", "Summary generation has been initiated")
        else:
            print_status("WARNING", f"Unexpected response: {response.text}")
            return None
            
    except Exception as e:
        print_status("FAIL", f"POST /summary failed: {e}")
        return None
    
    # Now poll the GET endpoint until the summary is available
    print_status("INFO", f"Polling GET /summary/{tenant_id}/{document_id} (max {max_wait}s)")
    
    start_time = time.time()
    while time.time() - start_time < max_wait:
        try:
            response = requests.get(
                f"{api_endpoint}/summary/{tenant_id}/{document_id}",
                headers=headers,
                timeout=30
            )
            
            if response.status_code == 200:
                result = response.json()
                if 'summary' in result:
                    print_status("SUCCESS", "Summary retrieved successfully!")
                    print_status("INFO", "Summary preview:")
                    print(f"\n{result['summary'][:500]}...\n")
                    return result
            
            time.sleep(10)
            print_status("INFO", f"Still waiting... ({int(time.time() - start_time)}s elapsed)")
            
        except Exception as e:
            print_status("WARNING", f"GET request failed: {e}, retrying...")
            time.sleep(5)
    
    print_status("WARNING", "Summary retrieval timed out")
    return None

def check_summary_for_truncation(summary):
    """Check if the summary still has truncation notices"""
    if not summary:
        return False
    
    if "[Note: Document was truncated" in summary:
        print_status("FAIL", "Summary still shows truncation notice!")
        return True
    else:
        print_status("SUCCESS", "Summary does NOT have truncation notice")
        return False

def main():
    """Main test function"""
    print_status("INFO", "=== TESTING DOCUMENT CHUNKING FOR SUMMARIZATION ===")
    
    # Get configuration
    bucket_name, api_endpoint, api_key = get_terraform_outputs()
    print_status("SUCCESS", f"Using bucket: {bucket_name}")
    print_status("SUCCESS", f"Using API endpoint: {api_endpoint}")
    
    # Upload test document (large PDF)
    pdf_path = '/Users/adrian/Projects/Cloudable.AI/Amazon Bedrock Knowledge Bases by Example _ by John Tucker _ Medium.pdf'
    if not os.path.exists(pdf_path):
        print_status("FAIL", f"Test PDF not found: {pdf_path}")
        sys.exit(1)
    
    document_key = direct_upload_document(bucket_name, pdf_path)
    if not document_key:
        print_status("FAIL", "Failed to upload document")
        sys.exit(1)
    
    # Wait for processing
    processed_key = wait_for_processing(bucket_name, document_key)
    if not processed_key:
        print_status("FAIL", "Document was not processed")
        sys.exit(1)
    
    # Extract document ID for API calls
    filename = processed_key.split('/')[-1]
    document_id = filename.replace('_processed.pdf', '')
    
    # Test summary retrieval via API
    print_status("INFO", f"Using document ID: {document_id}")
    summary_result = wait_for_summary_via_api(
        api_endpoint, 
        api_key, 
        'acme',  # Using tenant name instead of ID for summary API
        document_id
    )
    
    # Check summary content
    if summary_result and 'summary' in summary_result:
        has_truncation = check_summary_for_truncation(summary_result['summary'])
        
        # Check summary length as indicator of chunking working
        if len(summary_result['summary']) > 2000:
            print_status("SUCCESS", f"Summary is substantial ({len(summary_result['summary'])} chars)")
        else:
            print_status("WARNING", f"Summary seems short ({len(summary_result['summary'])} chars)")
    
    print_status("INFO", "=== DOCUMENT CHUNKING TEST COMPLETE ===")

if __name__ == "__main__":
    main()








