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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/infras/envs/us-east-1"

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI AUTOMATED DEPLOYMENT              ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Step 1: Create Terraform config for local backend
echo -e "\n${YELLOW}Creating Terraform local backend configuration...${NC}"
cat > "$TERRAFORM_DIR/backend.tf" << EOF
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
EOF
echo -e "${GREEN}✓ Created local backend configuration${NC}"

# Step 2: Create auto-vars file
echo -e "\n${YELLOW}Creating Terraform auto variables file...${NC}"
cat > "$TERRAFORM_DIR/terraform.auto.tfvars" << EOF
env                  = "dev"
domain_name          = "cloudable.ai"
aurora_engine_version = "15.12"

# Override any other variables as needed
vpc_id               = ""
subnet_ids           = []
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]

# Force destroy all resources
force_destroy        = true
prevent_destroy      = false
EOF
echo -e "${GREEN}✓ Created Terraform auto variables file${NC}"

# Step 3: Initialize and deploy Terraform
echo -e "\n${YELLOW}Initializing Terraform...${NC}"
cd "$TERRAFORM_DIR"
terraform init -reconfigure -input=false

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform initialization failed.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Creating VPC module for automated deployment...${NC}"
cat > "$TERRAFORM_DIR/vpc_auto.tf" << EOF
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  
  name = "cloudable-vpc-\${var.env}"
  cidr = "10.0.0.0/16"
  
  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  
  enable_nat_gateway = true
  single_nat_gateway = true
  
  tags = {
    Environment = var.env
    Project     = "cloudable"
  }
}

locals {
  vpc_id = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
}
EOF

echo -e "\n${YELLOW}Creating automated variables file...${NC}"
cat > "$TERRAFORM_DIR/auto_vars.tf" << EOF
# Automatically set VPC and subnet IDs from VPC module
locals {
  vpc_id_final     = coalesce(var.vpc_id, local.vpc_id)
  subnet_ids_final = length(var.subnet_ids) > 0 ? var.subnet_ids : local.private_subnet_ids
}

# Use these variables in all resources
variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs"
  type        = list(string)
  default     = []
}

variable "availability_zones" {
  description = "Availability Zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "force_destroy" {
  description = "Whether to force destroy resources"
  type        = bool
  default     = true
}

variable "prevent_destroy" {
  description = "Whether to prevent destroy of resources"
  type        = bool
  default     = false
}
EOF

# Fix references to vpc_id and subnet_ids
echo -e "\n${YELLOW}Updating resource references to use the auto VPC variables...${NC}"
for file in $(grep -l "vpc_id" "$TERRAFORM_DIR"/*.tf | grep -v "auto_vars.tf" | grep -v "vpc_auto.tf"); do
  sed -i.bak 's/vpc_id = var.vpc_id/vpc_id = local.vpc_id_final/g' "$file"
  sed -i.bak 's/subnet_ids = var.subnet_ids/subnet_ids = local.subnet_ids_final/g' "$file"
done
rm -f "$TERRAFORM_DIR"/*.bak

echo -e "\n${YELLOW}Planning Terraform deployment...${NC}"
terraform plan -out=tfplan -input=false

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform plan failed.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Applying Terraform deployment...${NC}"
terraform apply -auto-approve tfplan

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform apply failed.${NC}"
    exit 1
fi

# Step 4: Extract outputs
echo -e "\n${YELLOW}Extracting deployment outputs...${NC}"
RDS_CLUSTER_ARN=$(terraform output -raw rds_cluster_arn 2>/dev/null || echo "")
RDS_SECRET_ARN=$(terraform output -raw rds_secret_arn 2>/dev/null || echo "")
BUCKET_T001=$(terraform output -raw kb_bucket_t001 2>/dev/null || echo "")
KB_ID_T001=$(terraform output -raw kb_id_t001 2>/dev/null || echo "")
API_ENDPOINT=$(terraform output -raw api_gateway_endpoint 2>/dev/null || echo "")

if [ -z "$RDS_CLUSTER_ARN" ] || [ -z "$RDS_SECRET_ARN" ]; then
    echo -e "${YELLOW}Some outputs could not be extracted. Continuing anyway...${NC}"
fi

echo -e "\n${GREEN}RDS Cluster ARN: $RDS_CLUSTER_ARN${NC}"
echo -e "${GREEN}RDS Secret ARN: $RDS_SECRET_ARN${NC}"
echo -e "${GREEN}Bucket: $BUCKET_T001${NC}"
echo -e "${GREEN}Knowledge Base ID: $KB_ID_T001${NC}"
echo -e "${GREEN}API Endpoint: $API_ENDPOINT${NC}"

# Step 5: Setup pgvector
echo -e "\n${YELLOW}Setting up pgvector in RDS...${NC}"
if [ -n "$RDS_CLUSTER_ARN" ] && [ -n "$RDS_SECRET_ARN" ]; then
    cd "$TERRAFORM_DIR"
    python3 setup_pgvector.py --cluster-arn "$RDS_CLUSTER_ARN" --secret-arn "$RDS_SECRET_ARN" --database cloudable --tenant acme,globex --index-type hnsw -y
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Warning: pgvector setup had issues, but continuing...${NC}"
    else
        echo -e "${GREEN}✓ Successfully set up pgvector${NC}"
    fi
else
    echo -e "${RED}Missing RDS ARNs. Skipping pgvector setup.${NC}"
fi

# Step 6: Create and upload test document
echo -e "\n${YELLOW}Creating test document...${NC}"
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

if [ -n "$BUCKET_T001" ]; then
    echo -e "${YELLOW}Uploading test document to S3...${NC}"
    UPLOAD_KEY="documents/test_document_$(date +%Y%m%d%H%M%S).md"
    aws s3 cp "$TEST_DOC_PATH" "s3://$BUCKET_T001/$UPLOAD_KEY"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to upload test document.${NC}"
    else
        echo -e "${GREEN}✓ Successfully uploaded test document to s3://$BUCKET_T001/$UPLOAD_KEY${NC}"
        
        # Save document key and tenant info for testing
        echo "{\"document_key\":\"$UPLOAD_KEY\",\"tenant\":\"acme\",\"kb_id\":\"$KB_ID_T001\"}" > "$SCRIPT_DIR/test_document_info.json"
    fi
else
    echo -e "${RED}Missing bucket name. Skipping document upload.${NC}"
fi

# Step 7: Wait for everything to initialize
echo -e "\n${YELLOW}Waiting for resources to initialize (2 minutes)...${NC}"
sleep 120

# Step 8: Test API endpoints
echo -e "\n${YELLOW}Testing API endpoints...${NC}"
if [ -n "$API_ENDPOINT" ]; then
    # Save API endpoint for future use
    echo "$API_ENDPOINT" > "$SCRIPT_DIR/api_endpoint.txt"
    
    # Test API Gateway endpoint
    echo -e "\n${YELLOW}Testing API Gateway endpoint...${NC}"
    curl -s "$API_ENDPOINT/api/health" || echo "API health check failed"
    
    # If we have document info, test document sync
    if [ -f "$SCRIPT_DIR/test_document_info.json" ]; then
        DOC_KEY=$(jq -r '.document_key' "$SCRIPT_DIR/test_document_info.json")
        TENANT=$(jq -r '.tenant' "$SCRIPT_DIR/test_document_info.json")
        
        echo -e "\n${YELLOW}Testing document sync API...${NC}"
        SYNC_PAYLOAD="{\"tenant\":\"$TENANT\",\"document_key\":\"$DOC_KEY\"}"
        
        echo -e "${YELLOW}Payload: $SYNC_PAYLOAD${NC}"
        SYNC_RESPONSE=$(curl -s -X POST \
            "$API_ENDPOINT/api/kb/sync" \
            -H "Content-Type: application/json" \
            -d "$SYNC_PAYLOAD")
        
        echo -e "${YELLOW}Response: $SYNC_RESPONSE${NC}"
        
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
        
        echo -e "${YELLOW}Response: $QUERY_RESPONSE${NC}"
        
        # Test chat API
        echo -e "\n${YELLOW}Testing chat API with knowledge base context...${NC}"
        CHAT_PAYLOAD="{\"tenant\":\"$TENANT\",\"message\":\"Explain the features of Cloudable.AI\",\"use_kb\":true}"
        
        echo -e "${YELLOW}Payload: $CHAT_PAYLOAD${NC}"
        CHAT_RESPONSE=$(curl -s -X POST \
            "$API_ENDPOINT/api/chat" \
            -H "Content-Type: application/json" \
            -d "$CHAT_PAYLOAD")
        
        echo -e "${YELLOW}Response: $CHAT_RESPONSE${NC}"
    else
        echo -e "${YELLOW}No document info found. Skipping document-related API tests.${NC}"
    fi
else
    echo -e "${RED}API endpoint not available. Skipping API tests.${NC}"
fi

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}CLOUDABLE.AI AUTOMATED DEPLOYMENT COMPLETED${NC}"
echo -e "${BLUE}==================================================${NC}"

echo -e "\n${YELLOW}Deployment Summary:${NC}"
echo -e "RDS Cluster ARN: ${RDS_CLUSTER_ARN:-Not available}"
echo -e "S3 Bucket: ${BUCKET_T001:-Not available}"
echo -e "Knowledge Base ID: ${KB_ID_T001:-Not available}"
echo -e "API Gateway Endpoint: ${API_ENDPOINT:-Not available}"

echo -e "\n${YELLOW}Test Document:${NC} $TEST_DOC_PATH"
if [ -f "$SCRIPT_DIR/test_document_info.json" ]; then
    echo -e "${YELLOW}Document Key:${NC} $(jq -r '.document_key' "$SCRIPT_DIR/test_document_info.json")"
fi

exit 0
