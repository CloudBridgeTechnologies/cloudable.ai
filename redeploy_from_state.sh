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
export AWS_DEFAULT_REGION="us-east-1"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/infras/envs/us-east-1"

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI REDEPLOYMENT FROM STATE FILE      ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Step 1: Verify prerequisites
echo -e "\n${YELLOW}Step 1: Verifying prerequisites...${NC}"
# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
  echo -e "${RED}ERROR: Terraform is not installed. Please install it before running this script.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Terraform is installed${NC}"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
  echo -e "${RED}ERROR: AWS CLI is not installed. Please install it before running this script.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ AWS CLI is installed${NC}"

# Check AWS credentials
aws sts get-caller-identity > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "${RED}ERROR: AWS authentication failed. Please configure your AWS credentials.${NC}"
  exit 1
fi
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✓ AWS credentials verified for account: $ACCOUNT_ID${NC}"

# Step 2: Check for existing Terraform state
echo -e "\n${YELLOW}Step 2: Checking for existing Terraform state...${NC}"
cd "$TERRAFORM_DIR"

if [ ! -f "terraform.tfstate" ]; then
  echo -e "${RED}ERROR: terraform.tfstate file not found in $TERRAFORM_DIR.${NC}"
  echo -e "${RED}The previous state file is required for redeployment.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Found existing Terraform state file${NC}"

# Step 3: Initialize Terraform with existing state
echo -e "\n${YELLOW}Step 3: Initializing Terraform with existing state...${NC}"
terraform init -reconfigure

if [ $? -ne 0 ]; then
  echo -e "${RED}ERROR: Failed to initialize Terraform.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Terraform initialized successfully${NC}"

# Step 4: Plan Terraform deployment
echo -e "\n${YELLOW}Step 4: Planning Terraform deployment...${NC}"
terraform plan -out=tfplan

if [ $? -ne 0 ]; then
  echo -e "${RED}WARNING: Terraform plan had issues, but continuing...${NC}"
else
  echo -e "${GREEN}✓ Terraform plan created successfully${NC}"
fi

# Step 5: Apply Terraform deployment
echo -e "\n${YELLOW}Step 5: Applying Terraform deployment...${NC}"
read -p "Do you want to apply the Terraform deployment? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}Deployment canceled.${NC}"
  exit 0
fi

terraform apply -auto-approve

if [ $? -ne 0 ]; then
  echo -e "${RED}ERROR: Failed to apply Terraform deployment.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Terraform deployment applied successfully${NC}"

# Step 6: Extract outputs
echo -e "\n${YELLOW}Step 6: Extracting deployment outputs...${NC}"
RDS_CLUSTER_ARN=$(terraform output -raw rds_cluster_arn 2>/dev/null || echo "")
RDS_SECRET_ARN=$(terraform output -raw rds_secret_arn 2>/dev/null || echo "")
RDS_DATABASE=$(terraform output -raw rds_database_name 2>/dev/null || echo "cloudable")
BUCKET_ACME=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'cloudable-kb-dev-us-east-1-acme')].Name" --output text | head -n 1)
BUCKET_GLOBEX=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'cloudable-kb-dev-us-east-1-globex')].Name" --output text | head -n 1)
API_ENDPOINT=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")

echo -e "\n${GREEN}RDS Cluster ARN: $RDS_CLUSTER_ARN${NC}"
echo -e "${GREEN}RDS Secret ARN: $RDS_SECRET_ARN${NC}"
echo -e "${GREEN}RDS Database: $RDS_DATABASE${NC}"
echo -e "${GREEN}ACME Bucket: $BUCKET_ACME${NC}"
echo -e "${GREEN}GLOBEX Bucket: $BUCKET_GLOBEX${NC}"
echo -e "${GREEN}API Endpoint: $API_ENDPOINT${NC}"

# Step 7: Set up pgvector in RDS if needed
echo -e "\n${YELLOW}Step 7: Setting up pgvector in RDS...${NC}"
if [ -n "$RDS_CLUSTER_ARN" ] && [ -n "$RDS_SECRET_ARN" ] && [ -f "setup_pgvector.py" ]; then
  echo -e "${YELLOW}Would you like to set up pgvector in the RDS cluster? (y/N):${NC}"
  read -p "" setup_pgvector
  
  if [[ "$setup_pgvector" =~ ^[Yy]$ ]]; then
    python3 setup_pgvector.py --cluster-arn "$RDS_CLUSTER_ARN" --secret-arn "$RDS_SECRET_ARN" --database "$RDS_DATABASE" --tenant acme,globex --index-type hnsw
    
    if [ $? -ne 0 ]; then
      echo -e "${RED}Warning: pgvector setup had issues, but continuing...${NC}"
    else
      echo -e "${GREEN}✓ Successfully set up pgvector${NC}"
    fi
  else
    echo -e "${YELLOW}Skipping pgvector setup.${NC}"
  fi
else
  echo -e "${YELLOW}Skipping pgvector setup due to missing resources or script.${NC}"
fi

# Step 8: Test API endpoints
echo -e "\n${YELLOW}Step 8: Testing API endpoints...${NC}"
if [ -n "$API_ENDPOINT" ]; then
  echo -e "${YELLOW}Would you like to test the API endpoints? (y/N):${NC}"
  read -p "" test_api
  
  if [[ "$test_api" =~ ^[Yy]$ ]]; then
    # Test health endpoint
    echo -e "${YELLOW}Testing health endpoint...${NC}"
    HEALTH_RESPONSE=$(curl -s "${API_ENDPOINT}health" || echo "Failed to reach API")
    echo -e "${GREEN}Response: $HEALTH_RESPONSE${NC}"
    
    # Test with a sample document for ACME tenant
    echo -e "\n${YELLOW}Testing KB Query API for ACME tenant...${NC}"
    QUERY_PAYLOAD="{\"tenant\":\"acme\",\"query\":\"What is the current status of ACME Corporation?\",\"max_results\":3}"
    
    echo -e "${YELLOW}Payload: $QUERY_PAYLOAD${NC}"
    QUERY_RESPONSE=$(curl -s -X POST \
      "${API_ENDPOINT}kb/query" \
      -H "Content-Type: application/json" \
      -d "$QUERY_PAYLOAD")
    
    echo -e "${GREEN}Response: $QUERY_RESPONSE${NC}"
    
    # Test chat API for ACME tenant
    echo -e "\n${YELLOW}Testing chat API for ACME tenant...${NC}"
    CHAT_PAYLOAD="{\"tenant\":\"acme\",\"message\":\"Tell me about ACME's implementation progress\",\"use_kb\":true}"
    
    echo -e "${YELLOW}Payload: $CHAT_PAYLOAD${NC}"
    CHAT_RESPONSE=$(curl -s -X POST \
      "${API_ENDPOINT}chat" \
      -H "Content-Type: application/json" \
      -d "$CHAT_PAYLOAD")
    
    echo -e "${GREEN}Response: $CHAT_RESPONSE${NC}"
    
    # Test customer status API for ACME tenant
    echo -e "\n${YELLOW}Testing customer status API for ACME tenant...${NC}"
    STATUS_PAYLOAD="{\"tenant\":\"acme\"}"
    
    echo -e "${YELLOW}Payload: $STATUS_PAYLOAD${NC}"
    STATUS_RESPONSE=$(curl -s -X POST \
      "${API_ENDPOINT}customer-status" \
      -H "Content-Type: application/json" \
      -d "$STATUS_PAYLOAD")
    
    echo -e "${GREEN}Response: $STATUS_RESPONSE${NC}"
  else
    echo -e "${YELLOW}Skipping API tests.${NC}"
  fi
else
  echo -e "${RED}API endpoint not available. Skipping API tests.${NC}"
fi

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}CLOUDABLE.AI REDEPLOYMENT COMPLETED SUCCESSFULLY${NC}"
echo -e "${BLUE}==================================================${NC}"

echo -e "\n${YELLOW}Resource Summary:${NC}"
echo -e "RDS Cluster ARN: ${RDS_CLUSTER_ARN:-Not available}"
echo -e "RDS Secret ARN: ${RDS_SECRET_ARN:-Not available}"
echo -e "RDS Database: ${RDS_DATABASE:-Not available}"
echo -e "S3 Bucket (acme): ${BUCKET_ACME:-Not available}"
echo -e "S3 Bucket (globex): ${BUCKET_GLOBEX:-Not available}"
echo -e "API Gateway Endpoint: ${API_ENDPOINT:-Not available}"

exit 0
