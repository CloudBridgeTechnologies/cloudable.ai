#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/infras/envs/us-east-1"

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI FINAL DEPLOYMENT & TESTING        ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Step 1: Get existing resource information
echo -e "\n${YELLOW}Step 1: Gathering information about existing resources...${NC}"

# Get RDS Cluster ARN
echo -e "${YELLOW}Looking up RDS Cluster ARN...${NC}"
RDS_CLUSTER_ARN=$(aws rds describe-db-clusters --query "DBClusters[?DBClusterIdentifier=='aurora-dev'].DBClusterArn" --output text)

if [ -z "$RDS_CLUSTER_ARN" ]; then
    echo -e "${RED}Error: Could not find RDS Cluster ARN for 'aurora-dev'.${NC}"
    echo -e "${YELLOW}Continuing anyway, but pgvector setup may fail.${NC}"
else
    echo -e "${GREEN}✓ Found RDS Cluster ARN: $RDS_CLUSTER_ARN${NC}"
fi

# Get RDS Secret ARN
echo -e "${YELLOW}Looking up RDS Secret ARN...${NC}"
RDS_SECRET_ARN=$(aws secretsmanager list-secrets --query "SecretList[?Name=='aurora-dev-admin-secret'].ARN" --output text)

if [ -z "$RDS_SECRET_ARN" ]; then
    echo -e "${RED}Error: Could not find Secret ARN for 'aurora-dev-admin-secret'.${NC}"
    echo -e "${YELLOW}Continuing anyway, but pgvector setup may fail.${NC}"
else
    echo -e "${GREEN}✓ Found RDS Secret ARN: $RDS_SECRET_ARN${NC}"
fi

# Find S3 buckets
echo -e "${YELLOW}Looking up S3 buckets...${NC}"
BUCKET_ACME=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'cloudable-kb-dev-us-east-1-acme')].Name" --output text | head -n 1)
BUCKET_GLOBEX=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'cloudable-kb-dev-us-east-1-globex')].Name" --output text | head -n 1)

if [ -z "$BUCKET_ACME" ] || [ -z "$BUCKET_GLOBEX" ]; then
    echo -e "${RED}Warning: Could not find all required S3 buckets.${NC}"
    echo -e "${YELLOW}Creating new buckets if needed...${NC}"
    
    if [ -z "$BUCKET_ACME" ]; then
        NEW_BUCKET_ACME="cloudable-kb-dev-us-east-1-acme-$(date +%Y%m%d%H%M%S)"
        aws s3api create-bucket --bucket "$NEW_BUCKET_ACME" --region us-east-1
        BUCKET_ACME=$NEW_BUCKET_ACME
        echo -e "${GREEN}✓ Created new bucket for acme tenant: $BUCKET_ACME${NC}"
    fi
    
    if [ -z "$BUCKET_GLOBEX" ]; then
        NEW_BUCKET_GLOBEX="cloudable-kb-dev-us-east-1-globex-$(date +%Y%m%d%H%M%S)"
        aws s3api create-bucket --bucket "$NEW_BUCKET_GLOBEX" --region us-east-1
        BUCKET_GLOBEX=$NEW_BUCKET_GLOBEX
        echo -e "${GREEN}✓ Created new bucket for globex tenant: $BUCKET_GLOBEX${NC}"
    fi
else
    echo -e "${GREEN}✓ Found S3 buckets: $BUCKET_ACME, $BUCKET_GLOBEX${NC}"
fi

# Step 2: Setup pgvector if we have RDS resources
echo -e "\n${YELLOW}Step 2: Setting up pgvector in RDS...${NC}"
if [ -n "$RDS_CLUSTER_ARN" ] && [ -n "$RDS_SECRET_ARN" ]; then
    cd "$TERRAFORM_DIR"
    
    # Check if setup_pgvector.py exists
    if [ -f "setup_pgvector.py" ]; then
        echo -e "${YELLOW}Running setup_pgvector.py...${NC}"
        python3 setup_pgvector.py --cluster-arn "$RDS_CLUSTER_ARN" --secret-arn "$RDS_SECRET_ARN" --database cloudable --tenant acme,globex --index-type hnsw
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Warning: pgvector setup had issues, but continuing...${NC}"
        else
            echo -e "${GREEN}✓ Successfully set up pgvector${NC}"
        fi
    else
        echo -e "${RED}Error: setup_pgvector.py not found in $TERRAFORM_DIR.${NC}"
    fi
else
    echo -e "${RED}Skipping pgvector setup due to missing RDS resources.${NC}"
fi

# Step 3: Create a test document
echo -e "\n${YELLOW}Step 3: Creating test document...${NC}"
TEST_DOC_PATH="$SCRIPT_DIR/test_document_cloudable.md"

cat > "$TEST_DOC_PATH" << EOF
# Cloudable.AI Test Document

## Overview
This is a test document for the Cloudable.AI knowledge base system.

## Features
- Vector similarity search using pgvector
- Multi-tenant architecture
- Document processing pipeline
- Integration with AWS Bedrock for embeddings

## Technical Stack
- AWS Lambda for serverless compute
- Amazon RDS with PostgreSQL and pgvector extension
- Amazon S3 for document storage
- Amazon Bedrock for embeddings and AI capabilities
- API Gateway for REST API endpoints

## Testing Procedure
1. Upload this document to the knowledge base
2. Process and embed the document content
3. Query the knowledge base with relevant questions
4. Verify accurate retrieval and responses

## Expected Outcomes
The system should correctly identify this document when queried about Cloudable.AI features, technical stack, or testing procedures.
EOF

echo -e "${GREEN}✓ Created test document at $TEST_DOC_PATH${NC}"

# Step 4: Upload test document to S3
echo -e "\n${YELLOW}Step 4: Uploading test document to S3...${NC}"
if [ -n "$BUCKET_ACME" ]; then
    UPLOAD_KEY="documents/test_document_$(date +%Y%m%d%H%M%S).md"
    aws s3 cp "$TEST_DOC_PATH" "s3://$BUCKET_ACME/$UPLOAD_KEY"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to upload test document.${NC}"
    else
        echo -e "${GREEN}✓ Successfully uploaded test document to s3://$BUCKET_ACME/$UPLOAD_KEY${NC}"
        
        # Save document key and tenant info for testing
        echo "{\"document_key\":\"$UPLOAD_KEY\",\"tenant\":\"acme\",\"bucket\":\"$BUCKET_ACME\"}" > "$SCRIPT_DIR/test_document_info.json"
        echo -e "${GREEN}✓ Saved document information to test_document_info.json${NC}"
    fi
else
    echo -e "${RED}Missing bucket name. Skipping document upload.${NC}"
fi

# Step 5: Find API Gateway endpoint
echo -e "\n${YELLOW}Step 5: Looking for API Gateway endpoints...${NC}"
API_ENDPOINTS=$(aws apigateway get-rest-apis --query "items[*].{name:name,id:id}" --output text)

if [ -n "$API_ENDPOINTS" ]; then
    echo -e "${GREEN}Found API Gateway endpoints:${NC}"
    aws apigateway get-rest-apis --query "items[*].{Name:name,ID:id}" --output table
    
    # Ask for API ID
    echo -e "${YELLOW}Enter the API ID to test (or press Enter to skip):${NC}"
    read API_ID
    
    if [ -n "$API_ID" ]; then
        # Get API stage name
        STAGE_NAME=$(aws apigateway get-stages --rest-api-id $API_ID --query "item[0].stageName" --output text || echo "dev")
        API_ENDPOINT="https://$API_ID.execute-api.us-east-1.amazonaws.com/$STAGE_NAME"
        
        echo -e "${GREEN}Using API endpoint: $API_ENDPOINT${NC}"
        
        # Test API endpoints
        echo -e "\n${YELLOW}Testing API endpoints...${NC}"
        
        # Test health endpoint
        echo -e "${YELLOW}Testing health endpoint...${NC}"
        HEALTH_RESPONSE=$(curl -s "$API_ENDPOINT/api/health" || echo "Failed to reach API")
        echo -e "${GREEN}Response: $HEALTH_RESPONSE${NC}"
        
        # If we have document info, test document sync
        if [ -f "$SCRIPT_DIR/test_document_info.json" ]; then
            DOC_KEY=$(jq -r '.document_key' "$SCRIPT_DIR/test_document_info.json")
            TENANT=$(jq -r '.tenant' "$SCRIPT_DIR/test_document_info.json")
            
            # Test document sync
            echo -e "\n${YELLOW}Testing document sync API...${NC}"
            SYNC_PAYLOAD="{\"tenant\":\"$TENANT\",\"document_key\":\"$DOC_KEY\"}"
            
            echo -e "${YELLOW}Payload: $SYNC_PAYLOAD${NC}"
            SYNC_RESPONSE=$(curl -s -X POST \
                "$API_ENDPOINT/api/kb/sync" \
                -H "Content-Type: application/json" \
                -d "$SYNC_PAYLOAD")
            
            echo -e "${GREEN}Response: $SYNC_RESPONSE${NC}"
            
            # Wait for sync to complete
            echo -e "${YELLOW}Waiting for knowledge base sync to complete (30 seconds)...${NC}"
            sleep 30
            
            # Test query API
            echo -e "\n${YELLOW}Testing knowledge base query API...${NC}"
            QUERY_PAYLOAD="{\"tenant\":\"$TENANT\",\"query\":\"What is the technical stack of Cloudable.AI?\",\"max_results\":3}"
            
            echo -e "${YELLOW}Payload: $QUERY_PAYLOAD${NC}"
            QUERY_RESPONSE=$(curl -s -X POST \
                "$API_ENDPOINT/api/kb/query" \
                -H "Content-Type: application/json" \
                -d "$QUERY_PAYLOAD")
            
            echo -e "${GREEN}Response: $QUERY_RESPONSE${NC}"
            
            # Test chat API
            echo -e "\n${YELLOW}Testing chat API with knowledge base context...${NC}"
            CHAT_PAYLOAD="{\"tenant\":\"$TENANT\",\"message\":\"Explain the features of Cloudable.AI\",\"use_kb\":true}"
            
            echo -e "${YELLOW}Payload: $CHAT_PAYLOAD${NC}"
            CHAT_RESPONSE=$(curl -s -X POST \
                "$API_ENDPOINT/api/chat" \
                -H "Content-Type: application/json" \
                -d "$CHAT_PAYLOAD")
            
            echo -e "${GREEN}Response: $CHAT_RESPONSE${NC}"
        else
            echo -e "${YELLOW}No document info found. Skipping document-related API tests.${NC}"
        fi
    else
        echo -e "${YELLOW}Skipping API testing.${NC}"
    fi
else
    echo -e "${YELLOW}No API Gateway endpoints found.${NC}"
fi

# Summary
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}CLOUDABLE.AI DEPLOYMENT AND TESTING COMPLETE${NC}"
echo -e "${BLUE}==================================================${NC}"

echo -e "\n${YELLOW}Resource Summary:${NC}"
echo -e "RDS Cluster ARN: ${RDS_CLUSTER_ARN:-Not found}"
echo -e "RDS Secret ARN: ${RDS_SECRET_ARN:-Not found}"
echo -e "S3 Bucket (acme): ${BUCKET_ACME:-Not found}"
echo -e "S3 Bucket (globex): ${BUCKET_GLOBEX:-Not found}"
if [ -n "$API_ID" ]; then
    echo -e "API Gateway Endpoint: $API_ENDPOINT"
else
    echo -e "API Gateway Endpoint: Not tested"
fi

exit 0
