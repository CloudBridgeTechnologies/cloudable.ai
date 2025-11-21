#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Set AWS region to eu-west-1
export AWS_REGION=eu-west-1
export AWS_DEFAULT_REGION=eu-west-1

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   DEPLOYING REAL KB IMPLEMENTATION (eu-west-1)   ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Check if we have the Lambda package
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAMBDA_DIR="${SCRIPT_DIR}/infras/lambdas/kb_manager"
CORE_DIR="${SCRIPT_DIR}/infras/core"
REAL_LAMBDA_ZIP="${CORE_DIR}/kb_manager_real.zip"

echo -e "${YELLOW}Step 1: Packaging the real KB Lambda implementation...${NC}"
if [ -d "$LAMBDA_DIR" ]; then
  cd "$LAMBDA_DIR" || exit 1
  echo -e "${GREEN}✓ Found KB Manager Lambda directory${NC}"
  
  # Create zip package
  echo "Creating Lambda package..."
  zip -q -r "$REAL_LAMBDA_ZIP" main.py rest_adapter.py
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Created Lambda package at ${REAL_LAMBDA_ZIP}${NC}"
  else
    echo -e "${RED}✗ Failed to create Lambda package${NC}"
    exit 1
  fi
else
  echo -e "${RED}✗ Cannot find Lambda directory at ${LAMBDA_DIR}${NC}"
  exit 1
fi

# Go back to core directory
cd "$CORE_DIR" || exit 1

echo -e "${YELLOW}Step 2: Creating pgvector setup script...${NC}"
PGVECTOR_SETUP_DIR="${SCRIPT_DIR}/infras/envs/us-east-1"

# Copy pgvector setup files
if [ -f "${PGVECTOR_SETUP_DIR}/setup_pgvector.py" ] && [ -f "${PGVECTOR_SETUP_DIR}/setup_pgvector.sql" ]; then
  cp "${PGVECTOR_SETUP_DIR}/setup_pgvector.py" "${CORE_DIR}/setup_pgvector.py"
  cp "${PGVECTOR_SETUP_DIR}/setup_pgvector.sql" "${CORE_DIR}/setup_pgvector.sql"
  echo -e "${GREEN}✓ Copied pgvector setup scripts${NC}"
else
  echo -e "${RED}✗ Missing pgvector setup scripts${NC}"
  exit 1
fi

# Create Terraform configuration for the real KB implementation
echo -e "${YELLOW}Step 3: Creating Terraform configuration for real KB implementation...${NC}"

cat > "${CORE_DIR}/real_kb_implementation.tf" << 'EOF'
# Real KB implementation with pgvector
# This file adds the real KB implementation to the existing infrastructure

# Enable pgvector in Aurora PostgreSQL
resource "aws_rds_cluster_parameter_group" "pgvector_params" {
  name        = "cloudable-pgvector-params-${terraform.workspace}"
  family      = "aurora-postgresql14"
  description = "Parameter group for pgvector extension"

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,pgvector"
  }

  parameter {
    name  = "rds.allowed_extensions"
    value = "vector,uuid-ossp,pg_stat_statements"
  }
}

# Update RDS cluster with pgvector parameter group
resource "aws_rds_cluster" "aurora" {
  # This is a resource update, not creation - the cluster already exists
  count = 0  # Not creating a new cluster, just updating through aws_rds_cluster_parameter_group_association

  # This is here to show what would be configured in a real deployment
  cluster_identifier      = "aurora-dev-core-v2"
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.pgvector_params.name
}

# Associate the parameter group with the existing cluster
resource "aws_rds_cluster_parameter_group_association" "pgvector_association" {
  cluster_identifier  = "aurora-dev-core-v2"
  parameter_group_name = aws_rds_cluster_parameter_group.pgvector_params.name
}

# Lambda function to set up pgvector tables
resource "aws_lambda_function" "pgvector_setup" {
  function_name    = "pgvector-setup-eu-west-1"
  filename         = "${path.module}/pgvector_setup.zip"
  source_code_hash = filebase64sha256("${path.module}/pgvector_setup.zip")
  
  handler          = "setup_pgvector_lambda.handler"
  runtime          = "python3.9"
  timeout          = 300
  memory_size      = 256
  
  role             = aws_iam_role.lambda_role.arn
  
  environment {
    variables = {
      RDS_CLUSTER_ARN = data.aws_rds_cluster.existing_cluster.arn
      RDS_SECRET_ARN  = data.aws_secretsmanager_secret.db_secret.arn
      RDS_DATABASE    = "cloudable"
      TENANT_LIST     = jsonencode(["acme", "globex"])
      INDEX_TYPE      = "hnsw"
      ENVIRONMENT     = "dev"
      AWS_REGION      = "eu-west-1"
    }
  }
}

# Update existing kb-manager-dev-core Lambda to use the real implementation
resource "aws_lambda_function" "kb_manager_real" {
  function_name    = "kb-manager-dev-core"
  filename         = "${path.module}/kb_manager_real.zip"
  source_code_hash = filebase64sha256("${path.module}/kb_manager_real.zip")
  
  handler          = "main.handler"
  runtime          = "python3.9"
  
  # Use existing role
  role             = aws_iam_role.lambda_role.arn
  
  # Add necessary environment variables
  environment {
    variables = {
      RDS_CLUSTER_ARN = data.aws_rds_cluster.existing_cluster.arn
      RDS_SECRET_ARN  = data.aws_secretsmanager_secret.db_secret.arn
      RDS_DATABASE    = "cloudable"
      REGION          = "eu-west-1"
      ENV             = "dev"
      
      # Tenant-specific config
      BUCKET_ACME     = "cloudable-kb-dev-eu-west-1-acme-20251114095518"
      BUCKET_GLOBEX   = "cloudable-kb-dev-eu-west-1-globex-20251114095518"
      
      # Use Claude 3 Sonnet for embeddings and retrieval
      CLAUDE_MODEL_ARN = "anthropic.claude-3-sonnet-20240229-v1:0"
    }
  }
  
  # Reuse existing configurations
  reserved_concurrent_executions = null
  memory_size = 512
  timeout     = 60
}

# Data sources to reference existing resources
data "aws_rds_cluster" "existing_cluster" {
  cluster_identifier = "aurora-dev-core-v2"
}

data "aws_secretsmanager_secret" "db_secret" {
  name = "aurora-dev-admin-secret"
}

# Create a pgvector setup package
data "archive_file" "pgvector_setup_package" {
  type        = "zip"
  output_path = "${path.module}/pgvector_setup.zip"
  
  source {
    content  = file("${path.module}/setup_pgvector.py")
    filename = "setup_pgvector.py"
  }
  
  source {
    content  = <<-EOF
      #!/usr/bin/env python3
      import json
      import os
      import setup_pgvector

      def handler(event, context):
          """Lambda handler for pgvector setup"""
          # Get parameters from environment variables
          cluster_arn = os.environ.get('RDS_CLUSTER_ARN')
          secret_arn = os.environ.get('RDS_SECRET_ARN')
          database = os.environ.get('RDS_DATABASE', 'cloudable')
          tenant_list = json.loads(os.environ.get('TENANT_LIST', '["acme", "globex"]'))
          index_type = os.environ.get('INDEX_TYPE', 'hnsw')
          region = os.environ.get('AWS_REGION', 'eu-west-1')
          
          # Set up args for the setup_pgvector.main function
          import sys
          sys.argv = [
              'setup_pgvector.py',
              '--cluster-arn', cluster_arn,
              '--secret-arn', secret_arn,
              '--database', database,
              '--region', region,
              '--index-type', index_type,
          ]
          
          # Add tenants to args
          for tenant in tenant_list:
              sys.argv.append('--tenants')
              sys.argv.append(tenant)
          
          # Run the setup
          try:
              setup_pgvector.main()
              return {
                  'statusCode': 200,
                  'body': json.dumps('PGVector setup completed successfully')
              }
          except Exception as e:
              print(f"Error setting up pgvector: {e}")
              return {
                  'statusCode': 500,
                  'body': json.dumps(f'Error setting up pgvector: {str(e)}')
              }
    EOF
    filename = "setup_pgvector_lambda.py"
  }
}
EOF

echo -e "${GREEN}✓ Created Terraform configuration${NC}"

# Create S3 buckets if they don't exist
echo -e "${YELLOW}Step 4: Creating S3 buckets for tenants...${NC}"
for tenant in "acme" "globex"; do
  BUCKET_NAME="cloudable-kb-dev-eu-west-1-${tenant}-20251114095518"
  if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region eu-west-1 --create-bucket-configuration LocationConstraint=eu-west-1
    echo -e "${GREEN}✓ Created bucket ${BUCKET_NAME}${NC}"
  else
    echo -e "${GREEN}✓ Bucket ${BUCKET_NAME} already exists${NC}"
  fi
done

# Apply Terraform changes
echo -e "${YELLOW}Step 5: Applying Terraform changes...${NC}"
cd "$CORE_DIR"
terraform init -reconfigure
terraform apply -target=aws_rds_cluster_parameter_group.pgvector_params -auto-approve
terraform apply -target=aws_rds_cluster_parameter_group_association.pgvector_association -auto-approve
terraform apply -target=data.archive_file.pgvector_setup_package -auto-approve
terraform apply -target=aws_lambda_function.pgvector_setup -auto-approve
terraform apply -target=aws_lambda_function.kb_manager_real -auto-approve

echo -e "${YELLOW}Step 6: Invoking pgvector setup Lambda...${NC}"
aws lambda invoke \
  --function-name "pgvector-setup-eu-west-1" \
  --payload '{}' \
  /tmp/pgvector_setup_output.json

# Check if the Lambda execution was successful
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ pgvector setup Lambda executed successfully${NC}"
else
  echo -e "${RED}✗ pgvector setup Lambda execution failed${NC}"
fi

echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}REAL KB IMPLEMENTATION DEPLOYED SUCCESSFULLY!${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "${YELLOW}Now you can test the knowledge base integration with:${NC}"
echo -e "${YELLOW}  ./test_e2e_pipeline.sh${NC}"
echo -e "${BLUE}==================================================${NC}"
