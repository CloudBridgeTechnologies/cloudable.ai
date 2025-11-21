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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/infras/envs/us-east-1"
TEMP_DIR="$SCRIPT_DIR/temp_cloudable_deploy"

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI AUTOMATED DEPLOYMENT V3           ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Create a clean temporary directory for deployment
echo -e "\n${YELLOW}Creating a clean deployment environment...${NC}"
rm -rf "$TEMP_DIR" 2>/dev/null
mkdir -p "$TEMP_DIR"

# Copy the essential files to temporary directory
echo -e "\n${YELLOW}Copying essential files to temporary directory...${NC}"
cp -r "$SCRIPT_DIR/infras" "$TEMP_DIR/"

# Create a minimal Terraform configuration
echo -e "\n${YELLOW}Creating minimal Terraform configuration...${NC}"

# Create main.tf
cat > "$TEMP_DIR/main.tf" << EOF
provider "aws" {
  region = "us-east-1"
}

# Use local backend
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# VPC module
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"
  
  name = "cloudable-vpc-dev"
  cidr = "10.0.0.0/16"
  
  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  
  enable_nat_gateway = true
  single_nat_gateway = true
  
  tags = {
    Environment = "dev"
    Project     = "cloudable"
  }
}

# RDS PostgreSQL cluster
resource "aws_rds_cluster" "postgres" {
  cluster_identifier      = "aurora-dev"
  engine                  = "aurora-postgresql"
  engine_version          = "15.3"
  availability_zones      = ["us-east-1a", "us-east-1b", "us-east-1c"]
  database_name           = "cloudable"
  master_username         = "dbadmin"
  master_password         = "ComplexPassword123!"  # Would use Secrets Manager in production
  backup_retention_period = 7
  preferred_backup_window = "07:00-09:00"
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.name
  storage_encrypted       = true
  
  lifecycle {
    ignore_changes = [availability_zones]
  }
}

resource "aws_rds_cluster_instance" "postgres" {
  identifier           = "aurora-dev-instance-1"
  cluster_identifier   = aws_rds_cluster.postgres.id
  instance_class       = "db.t4g.medium"
  engine               = aws_rds_cluster.postgres.engine
  engine_version       = aws_rds_cluster.postgres.engine_version
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "aurora-dev-subnets"
  subnet_ids = module.vpc.private_subnets
  
  tags = {
    Name = "Aurora Subnet Group"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id      = module.vpc.vpc_id
  name        = "aurora-dev-sg"
  description = "Aurora access"
  
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "Aurora Security Group"
  }
}

# S3 buckets for knowledge base
resource "aws_s3_bucket" "kb_bucket_acme" {
  bucket = "cloudable-kb-dev-us-east-1-acme-\${formatdate("YYYYMMDDHHmmss", timestamp())}"
  force_destroy = true
  
  tags = {
    Environment = "dev"
    Tenant      = "acme"
  }
}

resource "aws_s3_bucket" "kb_bucket_globex" {
  bucket = "cloudable-kb-dev-us-east-1-globex-\${formatdate("YYYYMMDDHHmmss", timestamp())}"
  force_destroy = true
  
  tags = {
    Environment = "dev"
    Tenant      = "globex"
  }
}

# Create a secret for database credentials
resource "aws_secretsmanager_secret" "db_secret" {
  name = "aurora-dev-admin-secret"
  
  tags = {
    Environment = "dev"
  }
}

resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = aws_rds_cluster.postgres.master_username
    password = aws_rds_cluster.postgres.master_password
    host     = aws_rds_cluster.postgres.endpoint
    port     = 5432
    dbname   = "cloudable"
  })
}

# Outputs
output "rds_cluster_arn" {
  value = aws_rds_cluster.postgres.arn
}

output "rds_secret_arn" {
  value = aws_secretsmanager_secret.db_secret.arn
}

output "kb_bucket_acme" {
  value = aws_s3_bucket.kb_bucket_acme.bucket
}

output "kb_bucket_globex" {
  value = aws_s3_bucket.kb_bucket_globex.bucket
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}
EOF

# Initialize and deploy
echo -e "\n${YELLOW}Initializing Terraform...${NC}"
cd "$TEMP_DIR"
terraform init

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform initialization failed.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Planning Terraform deployment...${NC}"
terraform plan -out=tfplan

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

# Extract important outputs
echo -e "\n${YELLOW}Extracting deployment outputs...${NC}"
RDS_CLUSTER_ARN=$(terraform output -raw rds_cluster_arn 2>/dev/null || echo "")
RDS_SECRET_ARN=$(terraform output -raw rds_secret_arn 2>/dev/null || echo "")
BUCKET_ACME=$(terraform output -raw kb_bucket_acme 2>/dev/null || echo "")
BUCKET_GLOBEX=$(terraform output -raw kb_bucket_globex 2>/dev/null || echo "")
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
SUBNET_IDS=$(terraform output -json private_subnet_ids 2>/dev/null | jq -r 'join(",")' || echo "")

# Save outputs to a file for later use
echo -e "\n${YELLOW}Saving deployment information...${NC}"
cat > "$SCRIPT_DIR/cloudable_deployment.json" << EOF
{
  "rds_cluster_arn": "$RDS_CLUSTER_ARN",
  "rds_secret_arn": "$RDS_SECRET_ARN",
  "bucket_acme": "$BUCKET_ACME",
  "bucket_globex": "$BUCKET_GLOBEX",
  "vpc_id": "$VPC_ID",
  "subnet_ids": "$SUBNET_IDS"
}
EOF

# Setup pgvector in RDS
echo -e "\n${YELLOW}Waiting for RDS to be fully available (2 minutes)...${NC}"
sleep 120

echo -e "\n${YELLOW}Setting up pgvector in RDS...${NC}"
if [ -n "$RDS_CLUSTER_ARN" ] && [ -n "$RDS_SECRET_ARN" ]; then
    cp "$TERRAFORM_DIR/setup_pgvector.py" "$TEMP_DIR/"
    cd "$TEMP_DIR"
    
    echo -e "${YELLOW}Running pgvector setup...${NC}"
    python3 setup_pgvector.py --cluster-arn "$RDS_CLUSTER_ARN" --secret-arn "$RDS_SECRET_ARN" --database cloudable --tenant acme,globex --index-type hnsw
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Warning: pgvector setup had issues, but continuing...${NC}"
    else
        echo -e "${GREEN}✓ Successfully set up pgvector${NC}"
    fi
else
    echo -e "${RED}Missing RDS ARNs. Skipping pgvector setup.${NC}"
fi

# Create test document
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

# Upload test document to S3
if [ -n "$BUCKET_ACME" ]; then
    echo -e "${YELLOW}Uploading test document to S3...${NC}"
    UPLOAD_KEY="documents/test_document_$(date +%Y%m%d%H%M%S).md"
    aws s3 cp "$TEST_DOC_PATH" "s3://$BUCKET_ACME/$UPLOAD_KEY"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to upload test document.${NC}"
    else
        echo -e "${GREEN}✓ Successfully uploaded test document to s3://$BUCKET_ACME/$UPLOAD_KEY${NC}"
    fi
else
    echo -e "${RED}Missing bucket name. Skipping document upload.${NC}"
fi

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}CLOUDABLE.AI MINIMAL DEPLOYMENT COMPLETED${NC}"
echo -e "${BLUE}==================================================${NC}"

echo -e "\n${YELLOW}Deployment Summary:${NC}"
echo -e "RDS Cluster ARN: ${RDS_CLUSTER_ARN:-Not available}"
echo -e "RDS Secret ARN: ${RDS_SECRET_ARN:-Not available}"
echo -e "S3 Bucket (acme): ${BUCKET_ACME:-Not available}"
echo -e "S3 Bucket (globex): ${BUCKET_GLOBEX:-Not available}"
echo -e "VPC ID: ${VPC_ID:-Not available}"
echo -e "Subnet IDs: ${SUBNET_IDS:-Not available}"

echo -e "\n${YELLOW}Next Steps:${NC}"
echo -e "1. Deploy Lambda functions using the VPC ID and subnet IDs above"
echo -e "2. Configure API Gateway to integrate with the Lambda functions"
echo -e "3. Test the end-to-end flow with the uploaded test document"

exit 0
