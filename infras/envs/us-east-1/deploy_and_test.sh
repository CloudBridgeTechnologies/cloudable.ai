#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Set environment variables
export ENV="dev"
export REGION="us-east-1"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI DEPLOYMENT AND TESTING SCRIPT      ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"
PREREQS_MET=true

# Check AWS CLI
if ! command_exists aws; then
    echo -e "${RED}AWS CLI not installed. Please install it first.${NC}"
    PREREQS_MET=false
fi

# Check Terraform
if ! command_exists terraform; then
    echo -e "${RED}Terraform not installed. Please install it first.${NC}"
    PREREQS_MET=false
fi

# Check jq
if ! command_exists jq; then
    echo -e "${RED}jq not installed. Please install it first.${NC}"
    PREREQS_MET=false
fi

# Check AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}AWS credentials not configured. Please configure AWS CLI first.${NC}"
    PREREQS_MET=false
fi

if [ "$PREREQS_MET" = false ]; then
    echo -e "${RED}Prerequisites not met. Please install the required tools and try again.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met.${NC}"

# STEP 1: Deploy Terraform infrastructure
echo -e "\n${YELLOW}STEP 1: Deploying Terraform infrastructure...${NC}"
cd "$SCRIPT_DIR"

# Initialize Terraform
echo -e "\n${YELLOW}Initializing Terraform with reconfigured backend...${NC}"
terraform init -reconfigure

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform initialization failed.${NC}"
    exit 1
fi

# Plan deployment
echo -e "\n${YELLOW}Planning Terraform deployment...${NC}"
terraform plan -out=tfplan

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform plan failed.${NC}"
    exit 1
fi

# Apply deployment
echo -e "\n${YELLOW}Applying Terraform deployment...${NC}"
terraform apply -auto-approve tfplan

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform apply failed.${NC}"
    exit 1
fi

# Clean up plan file
rm -f tfplan

# Extract outputs
echo -e "\n${YELLOW}Extracting deployment outputs...${NC}"
RDS_CLUSTER_ARN=$(terraform output -raw rds_cluster_arn 2>/dev/null || echo "")
RDS_SECRET_ARN=$(terraform output -raw rds_secret_arn 2>/dev/null || echo "")
BUCKET_T001=$(terraform output -raw kb_bucket_t001 2>/dev/null || echo "")
BUCKET_T002=$(terraform output -raw kb_bucket_t002 2>/dev/null || echo "")
KB_ID_T001=$(terraform output -raw kb_id_t001 2>/dev/null || echo "")
KB_ID_T002=$(terraform output -raw kb_id_t002 2>/dev/null || echo "")
API_ENDPOINT=$(terraform output -raw api_gateway_endpoint 2>/dev/null || echo "")

if [ -z "$RDS_CLUSTER_ARN" ] || [ -z "$RDS_SECRET_ARN" ] || [ -z "$BUCKET_T001" ] || [ -z "$KB_ID_T001" ]; then
    echo -e "${RED}Failed to extract all required outputs from Terraform.${NC}"
    echo -e "${YELLOW}Continuing with available values...${NC}"
fi

# STEP 2: Set up pgvector in RDS
echo -e "\n${YELLOW}STEP 2: Setting up pgvector in RDS...${NC}"
echo -e "${YELLOW}Running setup_pgvector.py...${NC}"

cd "$SCRIPT_DIR"
python3 setup_pgvector.py --cluster-arn "$RDS_CLUSTER_ARN" --secret-arn "$RDS_SECRET_ARN" --database cloudable --tenant acme,globex --index-type hnsw

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to set up pgvector.${NC}"
    exit 1
fi

# STEP 3: Create test documents
echo -e "\n${YELLOW}STEP 3: Creating test documents...${NC}"

mkdir -p "$PROJECT_ROOT/test_docs"
TEST_DOC_PATH="$PROJECT_ROOT/test_docs/test_document_$(date +%Y%m%d%H%M%S).md"

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

echo -e "${GREEN}✓ Created test document: $TEST_DOC_PATH${NC}"

# STEP 4: Initialize testing environment
echo -e "\n${YELLOW}STEP 4: Initializing testing environment...${NC}"

# Save important variables to a config file
CONFIG_FILE="$PROJECT_ROOT/cloudable_test_config.json"
cat > "$CONFIG_FILE" << EOF
{
  "env": "$ENV",
  "region": "$REGION",
  "rds_cluster_arn": "$RDS_CLUSTER_ARN",
  "rds_secret_arn": "$RDS_SECRET_ARN",
  "bucket_t001": "$BUCKET_T001",
  "bucket_t002": "$BUCKET_T002",
  "kb_id_t001": "$KB_ID_T001",
  "kb_id_t002": "$KB_ID_T002",
  "api_endpoint": "$API_ENDPOINT",
  "test_doc_path": "$TEST_DOC_PATH"
}
EOF

echo -e "${GREEN}✓ Saved configuration to $CONFIG_FILE${NC}"

# STEP 5: Create end-to-end testing script
echo -e "\n${YELLOW}STEP 5: Creating E2E testing script...${NC}"

E2E_TEST_SCRIPT="$PROJECT_ROOT/e2e_test_api.sh"
cat > "$E2E_TEST_SCRIPT" << 'EOF'
#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Load configuration
CONFIG_FILE="$(dirname "$0")/cloudable_test_config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Configuration file not found: $CONFIG_FILE${NC}"
    exit 1
fi

ENV=$(jq -r '.env' "$CONFIG_FILE")
REGION=$(jq -r '.region' "$CONFIG_FILE")
BUCKET_T001=$(jq -r '.bucket_t001' "$CONFIG_FILE")
KB_ID_T001=$(jq -r '.kb_id_t001' "$CONFIG_FILE")
API_ENDPOINT=$(jq -r '.api_endpoint' "$CONFIG_FILE")
TEST_DOC_PATH=$(jq -r '.test_doc_path' "$CONFIG_FILE")

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI END-TO-END API TESTING SCRIPT      ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Function to make API call and handle response
call_api() {
    local endpoint=$1
    local method=$2
    local data=$3
    local description=$4
    
    echo -e "\n${YELLOW}Test: ${description}${NC}"
    echo -e "${YELLOW}API: ${method} ${endpoint}${NC}"
    
    if [ -n "$data" ]; then
        echo -e "${YELLOW}Request:${NC}"
        echo "$data" | jq '.'
        
        RESPONSE=$(curl -s -X ${method} \
            "${API_ENDPOINT}${endpoint}" \
            -H "Content-Type: application/json" \
            -d "${data}")
    else
        RESPONSE=$(curl -s -X ${method} "${API_ENDPOINT}${endpoint}")
    fi
    
    echo -e "${YELLOW}Response:${NC}"
    echo "$RESPONSE" | jq '.'
    
    # Check if response contains error
    ERROR=$(echo "$RESPONSE" | jq -r '.error // empty')
    if [ -n "$ERROR" ]; then
        echo -e "${RED}✗ Test failed: $ERROR${NC}"
        return 1
    else
        echo -e "${GREEN}✓ Test passed${NC}"
        return 0
    fi
}

# Test 1: Get upload URL
echo -e "\n${YELLOW}TEST 1: Get upload URL for document${NC}"
UPLOAD_DATA=$(cat << EOF
{
  "tenant": "acme",
  "filename": "test_document.md"
}
EOF
)

UPLOAD_RESPONSE=$(call_api "/api/upload-url" "POST" "$UPLOAD_DATA" "Get upload URL")
UPLOAD_URL=$(echo "$UPLOAD_RESPONSE" | jq -r '.url // empty')

if [ -z "$UPLOAD_URL" ]; then
    echo -e "${RED}Failed to get upload URL${NC}"
    exit 1
fi

# Test 2: Upload document
echo -e "\n${YELLOW}TEST 2: Upload document to S3${NC}"
if [ -f "$TEST_DOC_PATH" ]; then
    echo -e "${YELLOW}Uploading document: $TEST_DOC_PATH${NC}"
    UPLOAD_RESULT=$(curl -s -X PUT -H "Content-Type: text/markdown" --upload-file "$TEST_DOC_PATH" "$UPLOAD_URL")
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Document uploaded successfully${NC}"
        
        # Extract the key from the upload URL
        DOCUMENT_KEY=$(echo "$UPLOAD_URL" | grep -o '[^/]*$')
        echo -e "${YELLOW}Document key: $DOCUMENT_KEY${NC}"
    else
        echo -e "${RED}Failed to upload document${NC}"
        exit 1
    fi
else
    echo -e "${RED}Test document not found: $TEST_DOC_PATH${NC}"
    exit 1
fi

# Test 3: Sync knowledge base
echo -e "\n${YELLOW}TEST 3: Sync knowledge base${NC}"
SYNC_DATA=$(cat << EOF
{
  "tenant": "acme",
  "document_key": "$DOCUMENT_KEY"
}
EOF
)

call_api "/api/kb/sync" "POST" "$SYNC_DATA" "Sync knowledge base"

# Wait for sync to complete
echo -e "${YELLOW}Waiting 30 seconds for knowledge base sync to complete...${NC}"
sleep 30

# Test 4: Query knowledge base
echo -e "\n${YELLOW}TEST 4: Query knowledge base${NC}"
QUERY_DATA=$(cat << EOF
{
  "tenant": "acme",
  "query": "What is the technical stack of Cloudable.AI?",
  "max_results": 3
}
EOF
)

call_api "/api/kb/query" "POST" "$QUERY_DATA" "Query knowledge base"

# Test 5: Chat with context
echo -e "\n${YELLOW}TEST 5: Chat with knowledge base context${NC}"
CHAT_DATA=$(cat << EOF
{
  "tenant": "acme",
  "message": "Explain the features of Cloudable.AI",
  "use_kb": true
}
EOF
)

call_api "/api/chat" "POST" "$CHAT_DATA" "Chat with knowledge base context"

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}END-TO-END API TESTS COMPLETED${NC}"
echo -e "${BLUE}==================================================${NC}"

exit 0
EOF

chmod +x "$E2E_TEST_SCRIPT"
echo -e "${GREEN}✓ Created E2E testing script: $E2E_TEST_SCRIPT${NC}"

# STEP 6: Wait for deployment to be ready
echo -e "\n${YELLOW}STEP 6: Waiting for deployment to be fully ready...${NC}"
echo -e "${YELLOW}Waiting 2 minutes for all resources to initialize...${NC}"
sleep 120

# STEP 7: Run end-to-end tests
echo -e "\n${YELLOW}STEP 7: Running end-to-end API tests...${NC}"
"$E2E_TEST_SCRIPT"

if [ $? -ne 0 ]; then
    echo -e "${RED}End-to-end tests failed.${NC}"
    exit 1
fi

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}DEPLOYMENT AND TESTING COMPLETED SUCCESSFULLY${NC}"
echo -e "${BLUE}==================================================${NC}"

echo -e "${YELLOW}API Gateway Endpoint: $API_ENDPOINT${NC}"
echo -e "${YELLOW}Configuration saved to: $CONFIG_FILE${NC}"
echo -e "${YELLOW}Test document: $TEST_DOC_PATH${NC}"

exit 0
