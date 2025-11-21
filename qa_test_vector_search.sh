#!/bin/bash
# QA Test for Vector Search Functionality with pgvector

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
REGION="us-east-1"
TENANT="t001"
CUSTOMER_ID="vector-test-$(date +%s)"
KB_MANAGER_FUNCTION="kb-manager-dev"

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}  CLOUDABLE.AI VECTOR SEARCH QA TEST SUITE        ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Create Python script for vector testing
echo -e "\n${YELLOW}1. Creating vector test script...${NC}"
cat > vector_test.py << 'EOF'
#!/usr/bin/env python3
"""
Test script for pgvector search with various query types
"""
import argparse
import boto3
import json
import uuid
import time
from typing import List, Dict, Any

def invoke_lambda(function_name: str, path: str, body: Dict[str, Any], region: str = "us-east-1") -> Dict[str, Any]:
    """Invoke Lambda function with the given payload"""
    lambda_client = boto3.client('lambda', region_name=region)
    
    payload = {
        "path": path,
        "httpMethod": "POST",
        "body": json.dumps(body)
    }
    
    response = lambda_client.invoke(
        FunctionName=function_name,
        InvocationType="RequestResponse",
        Payload=json.dumps(payload)
    )
    
    result = json.loads(response['Payload'].read())
    if 'body' in result:
        try:
            result['body'] = json.loads(result['body'])
        except:
            pass
    
    return result

def get_upload_url(tenant_id: str, filename: str, function_name: str, region: str) -> Dict[str, Any]:
    """Get presigned URL for document upload"""
    payload = {
        "tenant_id": tenant_id,
        "filename": filename
    }
    
    response = invoke_lambda(function_name, "/kb/upload-url", payload, region)
    if response.get('statusCode', 500) != 200:
        print(f"Error: {json.dumps(response, indent=2)}")
        return None
    
    return response['body']

def upload_document(url: str, content: str) -> bool:
    """Upload document using presigned URL"""
    import requests
    
    headers = {
        "Content-Type": "text/markdown"
    }
    
    try:
        response = requests.put(url, headers=headers, data=content)
        return response.status_code == 200
    except Exception as e:
        print(f"Error uploading document: {e}")
        return False

def trigger_kb_sync(tenant_id: str, document_key: str, function_name: str, region: str) -> Dict[str, Any]:
    """Trigger knowledge base synchronization"""
    payload = {
        "tenant_id": tenant_id,
        "document_key": document_key
    }
    
    response = invoke_lambda(function_name, "/kb/sync", payload, region)
    if response.get('statusCode', 500) != 200:
        print(f"Error: {json.dumps(response, indent=2)}")
        return None
    
    return response['body']

def query_kb(tenant_id: str, customer_id: str, query: str, function_name: str, region: str) -> Dict[str, Any]:
    """Query the knowledge base"""
    payload = {
        "tenant_id": tenant_id,
        "customer_id": customer_id,
        "query": query
    }
    
    response = invoke_lambda(function_name, "/kb/query", payload, region)
    if response.get('statusCode', 500) != 200:
        print(f"Error: {json.dumps(response, indent=2)}")
        return None
    
    return response['body']

def run_vector_test(tenant_id: str, customer_id: str, function_name: str, region: str):
    """Run a comprehensive vector test"""
    print(f"\n{'=' * 50}")
    print(f"VECTOR SEARCH TEST FOR TENANT: {tenant_id}")
    print(f"{'=' * 50}")
    
    # Step 1: Create and upload document with specific semantic content
    filename = f"vector_test_{uuid.uuid4().hex[:8]}.md"
    
    # Create document with different semantic sections
    document_content = """# Vector Search Test Document

## Astronomy
Black holes are regions of spacetime where gravity is so strong that nothing, including light or other electromagnetic waves, can escape from it. The theory of general relativity predicts that a sufficiently compact mass can deform spacetime to form a black hole.

## Programming
Python is a high-level, general-purpose programming language. Its design philosophy emphasizes code readability with the use of significant indentation. Python is dynamically typed and garbage-collected.

## Finance
A stock market is a public market where you can buy and sell shares for publicly listed companies. The stocks, also known as equities, represent ownership in the company.

## Healthcare
Vaccines are biological preparations that provide active acquired immunity to particular infectious diseases. A vaccine typically contains an agent that resembles a disease-causing microorganism and is often made from weakened or killed forms of the microbe.
"""
    
    print("\n1. Getting upload URL...")
    upload_info = get_upload_url(tenant_id, filename, function_name, region)
    if not upload_info:
        print("Failed to get upload URL")
        return False
    
    print(f"   ✓ Got upload URL: {upload_info['document_key']}")
    
    print("\n2. Uploading document...")
    upload_success = upload_document(upload_info['presigned_url'], document_content)
    if not upload_success:
        print("Failed to upload document")
        return False
    
    print("   ✓ Document uploaded successfully")
    
    print("\n3. Triggering KB sync...")
    sync_result = trigger_kb_sync(tenant_id, upload_info['document_key'], function_name, region)
    if not sync_result:
        print("Failed to trigger KB sync")
        return False
    
    print(f"   ✓ KB sync started with job ID: {sync_result.get('ingestion_job_id')}")
    
    print("\n4. Waiting for processing to complete (30 seconds)...")
    time.sleep(30)
    
    # Test various query types to validate pgvector search
    test_queries = [
        {"name": "Astronomy query", "text": "How are black holes related to gravity?", "expected_topic": "astronomy"},
        {"name": "Programming query", "text": "What is Python programming language?", "expected_topic": "programming"},
        {"name": "Finance query", "text": "Explain what stocks are in the stock market", "expected_topic": "finance"},
        {"name": "Healthcare query", "text": "How do vaccines work?", "expected_topic": "healthcare"},
        {"name": "Combined query", "text": "Compare Python and black holes", "expected_topic": "astronomy|programming"}
    ]
    
    all_passed = True
    
    print("\n5. Testing vector search with different semantic queries...")
    for idx, test in enumerate(test_queries):
        print(f"\n   Test {idx+1}: {test['name']}")
        print(f"   Query: '{test['text']}'")
        
        result = query_kb(tenant_id, customer_id, test['text'], function_name, region)
        if not result:
            print(f"   ✗ Failed to get response")
            all_passed = False
            continue
        
        answer = result.get('answer', '')
        print(f"   Response: '{answer[:100]}...'")
        
        # Basic check if the answer is related to the expected topic
        expected_topics = test['expected_topic'].split('|')
        topic_found = False
        
        for topic in expected_topics:
            topic_keywords = {
                "astronomy": ["black hole", "gravity", "spacetime", "light", "electromagnetic"],
                "programming": ["python", "programming", "language", "code", "dynamically typed"],
                "finance": ["stock", "market", "shares", "equities", "companies"],
                "healthcare": ["vaccine", "immunity", "infectious", "disease", "microorganism"]
            }
            
            keywords = topic_keywords.get(topic.lower(), [])
            for keyword in keywords:
                if keyword.lower() in answer.lower():
                    topic_found = True
                    break
        
        if topic_found:
            print(f"   ✓ Answer appears to be related to expected topic: {test['expected_topic']}")
        else:
            print(f"   ✗ Answer may not be related to expected topic: {test['expected_topic']}")
            all_passed = False
    
    if all_passed:
        print("\n✓ All vector search tests passed!")
    else:
        print("\n✗ Some vector search tests failed")
    
    return all_passed

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Test pgvector search functionality")
    parser.add_argument("--tenant", default="t001", help="Tenant ID")
    parser.add_argument("--customer", default=f"vector-test-{int(time.time())}", help="Customer ID")
    parser.add_argument("--function", default="kb-manager-dev", help="Lambda function name")
    parser.add_argument("--region", default="us-east-1", help="AWS region")
    
    args = parser.parse_args()
    
    run_vector_test(args.tenant, args.customer, args.function, args.region)

if __name__ == "__main__":
    main()
EOF

echo -e "${GREEN}✓ Vector test script created${NC}"

# Make the script executable
chmod +x vector_test.py

# Check for required Python packages
echo -e "\n${YELLOW}2. Checking for required Python packages...${NC}"
MISSING_PACKAGES=()

# Check for boto3
python3 -c "import boto3" 2>/dev/null || MISSING_PACKAGES+=("boto3")

# Check for requests
python3 -c "import requests" 2>/dev/null || MISSING_PACKAGES+=("requests")

# Install missing packages if any
if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo -e "${YELLOW}Installing missing Python packages: ${MISSING_PACKAGES[@]}${NC}"
    pip3 install ${MISSING_PACKAGES[@]} --user
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to install required Python packages${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Required packages installed${NC}"
else
    echo -e "${GREEN}✓ All required Python packages are already installed${NC}"
fi

# Run the vector test script
echo -e "\n${YELLOW}3. Running vector search tests...${NC}"
python3 vector_test.py --tenant "$TENANT" --customer "$CUSTOMER_ID" --function "$KB_MANAGER_FUNCTION" --region "$REGION"

# Check the status
TEST_STATUS=$?
if [ $TEST_STATUS -ne 0 ]; then
    echo -e "${RED}Vector search tests failed with status $TEST_STATUS${NC}"
else
    echo -e "${GREEN}Vector search tests completed successfully${NC}"
fi

# Clean up
echo -e "\n${YELLOW}4. Cleaning up test files...${NC}"
rm -f vector_test.py
echo -e "${GREEN}✓ Test files removed${NC}"

echo -e "\n${BLUE}==================================================${NC}"
if [ $TEST_STATUS -eq 0 ]; then
    echo -e "${GREEN}      VECTOR SEARCH TESTS COMPLETED SUCCESSFULLY     ${NC}"
else
    echo -e "${RED}      VECTOR SEARCH TESTS FAILED     ${NC}"
fi
echo -e "${BLUE}==================================================${NC}"

exit $TEST_STATUS
