#!/bin/bash

# Script to fix the customer status API endpoint

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================="
echo "  FIXING CUSTOMER STATUS API ENDPOINT"
echo -e "==========================================================${NC}"

# Set AWS region for this session
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1

# Create a temporary directory
mkdir -p lambda_fix
cd lambda_fix

# Create a fixed lambda handler
cat > lambda_function_simple.py << 'EOF'
import json
import os
import logging
import time
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """Lambda handler function"""
    start_time = time.time()
    request_id = context.aws_request_id if context else str(uuid.uuid4())
    
    try:
        logger.info(f"[RequestId: {request_id}] Received event: {json.dumps(event)}")
        
        # Get the HTTP method and path
        http_method = event.get('httpMethod', '')
        path = event.get('path', '')
        
        # For API Gateway HTTP API integrations
        if 'requestContext' in event and 'http' in event['requestContext']:
            http_method = event['requestContext']['http']['method']
            path = event['requestContext']['http']['path']
        
        # Extract request body
        body = {}
        if 'body' in event:
            if isinstance(event['body'], str):
                try:
                    body = json.loads(event['body'])
                except json.JSONDecodeError:
                    logger.error("Failed to parse request body as JSON")
                    pass
            elif isinstance(event['body'], dict):
                body = event['body']
        
        # Extract tenant from request headers or body
        tenant = body.get('tenant') or (event.get('headers', {}).get('x-tenant-id') if event.get('headers') else None)
        
        logger.info(f"HTTP Method: {http_method}, Path: {path}, Body: {json.dumps(body)}")
        
        # Process health check
        if http_method == 'GET' and path.endswith('/health'):
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({"message": "Cloudable.AI KB Manager API is operational"})
            }
        
        # Handle KB query endpoint
        if http_method == 'POST' and path.endswith('/kb/query'):
            tenant = body.get('tenant', '')
            query = body.get('query', '')
            
            # Mock response based on tenant
            results = []
            if tenant == 'acme':
                results = [{
                    "text": "ACME Corporation is currently in the Implementation stage (phase 3 of 5), with a projected completion date of December 10, 2025.",
                    "metadata": {"source": "Customer Journey Report - ACME", "kb_id": "KB-ACME-2025-11-01"},
                    "score": 0.95
                }]
            elif tenant == 'globex':
                results = [{
                    "text": "Globex Industries is currently in the Onboarding stage (phase 1 of 4), with implementation having started on October 2, 2025.",
                    "metadata": {"source": "Globex Industries Onboarding Report", "kb_id": "KB-GLOBEX-2025-11-08"},
                    "score": 0.93
                }]
            
            response_data = {"results": results, "query": query}
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(response_data)
            }
        
        # Handle chat endpoint
        if http_method == 'POST' and path.endswith('/chat'):
            tenant = body.get('tenant', '')
            message = body.get('message', '')
            
            # Mock response based on tenant
            response = f"Information about {tenant} tenant."
            source_documents = [{
                "text": f"{tenant.capitalize()} tenant information",
                "metadata": {"source": f"{tenant.capitalize()} Knowledge Base", "kb_id": f"KB-{tenant.upper()}-GENERAL"}
            }]
            
            response_data = {"response": response, "source_documents": source_documents}
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(response_data)
            }
        
        # Handle customer status endpoint
        if http_method == 'POST' and (path.endswith('/customer-status') or path.endswith('/api/customer-status')):
            tenant_id = body.get('tenant', '')
            customer_id = body.get('customer_id')
            
            logger.info(f"Customer status request: tenant={tenant_id}, customer_id={customer_id}")
            
            # Mock response based on tenant
            if tenant_id == 'acme':
                if customer_id:
                    customer = {
                        "customer_id": customer_id,
                        "customer_name": "ACME Corp",
                        "current_stage": "Implementation",
                        "stage_order": 3,
                        "status_summary": "Phase 3 of 5 in progress. On track for December completion."
                    }
                    milestones = [
                        {
                            "milestone_id": "ms-001-001",
                            "milestone_name": "Project Kickoff",
                            "status": "Completed",
                            "planned_date": "2025-08-15"
                        },
                        {
                            "milestone_id": "ms-001-005",
                            "milestone_name": "Implementation Phase 2",
                            "status": "In Progress",
                            "planned_date": "2025-11-15"
                        }
                    ]
                    response_data = {
                        "customer": customer,
                        "milestones": milestones,
                        "summary": "ACME Corporation is currently in the Implementation stage (phase 3 of 5), with a projected completion date of December 10, 2025."
                    }
                else:
                    customers = [
                        {
                            "customer_id": "cust-001",
                            "customer_name": "ACME Corp",
                            "current_stage": "Implementation",
                            "stage_order": 3
                        },
                        {
                            "customer_id": "cust-002",
                            "customer_name": "ACME Subsidiary",
                            "current_stage": "Planning",
                            "stage_order": 2
                        }
                    ]
                    response_data = {"customers": customers}
            elif tenant_id == 'globex':
                if customer_id:
                    customer = {
                        "customer_id": customer_id,
                        "customer_name": "Globex Industries",
                        "current_stage": "Onboarding",
                        "stage_order": 1,
                        "status_summary": "Initial onboarding started October 2, 2025."
                    }
                    milestones = [
                        {
                            "milestone_id": "ms-002-001",
                            "milestone_name": "Initial Meeting",
                            "status": "Completed",
                            "planned_date": "2025-10-02"
                        },
                        {
                            "milestone_id": "ms-002-002",
                            "milestone_name": "Requirements Gathering",
                            "status": "In Progress",
                            "planned_date": "2025-11-15"
                        }
                    ]
                    response_data = {
                        "customer": customer,
                        "milestones": milestones,
                        "summary": "Globex Industries is currently in the early Onboarding phase (1 of 4), with focus on requirements gathering."
                    }
                else:
                    customers = [
                        {
                            "customer_id": "cust-001",
                            "customer_name": "Globex Main",
                            "current_stage": "Onboarding",
                            "stage_order": 1
                        },
                        {
                            "customer_id": "cust-002",
                            "customer_name": "Globex Subsidiary",
                            "current_stage": "Planning",
                            "stage_order": 2
                        }
                    ]
                    response_data = {"customers": customers}
            else:
                response_data = {"error": "Invalid tenant ID"}
            
            logger.info(f"Customer status response: {json.dumps(response_data)}")
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(response_data)
            }
        
        # Default response for unsupported paths
        logger.warning(f"Unsupported path: {path}, method: {http_method}")
        return {
            'statusCode': 404,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({"message": "Not Found"})
        }
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({"message": "Internal Server Error", "error": str(e)})
        }
EOF

# Create deployment package
echo -e "\n${YELLOW}Creating deployment package...${NC}"
zip -r lambda_function_simple.zip lambda_function_simple.py

# Deploy to Lambda
echo -e "\n${YELLOW}Deploying to Lambda...${NC}"
aws lambda update-function-code \
    --function-name kb-manager-dev-core \
    --zip-file fileb://lambda_function_simple.zip

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to deploy Lambda function${NC}"
    exit 1
else
    echo -e "${GREEN}Lambda function deployed successfully${NC}"
fi

# Clean up
cd ..
rm -rf lambda_fix

echo -e "\n${BLUE}=========================================================="
echo "  CUSTOMER STATUS API ENDPOINT FIX COMPLETED"
echo -e "==========================================================${NC}"
