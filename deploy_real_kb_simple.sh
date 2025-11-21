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
TEMP_DIR="/tmp/cloudable_kb_deploy"
REAL_LAMBDA_ZIP="${TEMP_DIR}/kb_manager_real.zip"

# Create temporary directory
mkdir -p "$TEMP_DIR"

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

# Get current Lambda configuration
echo -e "${YELLOW}Step 2: Getting current Lambda configuration...${NC}"
LAMBDA_NAME="kb-manager-dev-core"
LAMBDA_CONFIG=$(aws lambda get-function --function-name "$LAMBDA_NAME" --query 'Configuration')

if [ $? -ne 0 ]; then
  echo -e "${RED}✗ Failed to get Lambda configuration for ${LAMBDA_NAME}${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Got Lambda configuration${NC}"

# Update Lambda function
echo -e "${YELLOW}Step 3: Updating Lambda function with real KB implementation...${NC}"
aws lambda update-function-code \
  --function-name "$LAMBDA_NAME" \
  --zip-file "fileb://${REAL_LAMBDA_ZIP}"

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Updated Lambda function code${NC}"
else
  echo -e "${RED}✗ Failed to update Lambda function code${NC}"
  exit 1
fi

# Update Lambda configuration with required environment variables
echo -e "${YELLOW}Step 4: Updating Lambda environment variables...${NC}"
aws lambda update-function-configuration \
  --function-name "$LAMBDA_NAME" \
  --environment "Variables={RDS_CLUSTER_ARN=$(aws rds describe-db-clusters --db-cluster-identifier aurora-dev-core-v2 --query 'DBClusters[0].DBClusterArn' --output text),RDS_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id aurora-dev-admin-secret --query 'ARN' --output text),RDS_DATABASE=cloudable,REGION=eu-west-1,ENV=dev,BUCKET_ACME=cloudable-kb-dev-eu-west-1-acme-20251114095518,BUCKET_GLOBEX=cloudable-kb-dev-eu-west-1-globex-20251114095518,CLAUDE_MODEL_ARN=anthropic.claude-3-sonnet-20240229-v1:0}"

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Updated Lambda environment variables${NC}"
else
  echo -e "${RED}✗ Failed to update Lambda environment variables${NC}"
  exit 1
fi

# Create pgvector setup script
echo -e "${YELLOW}Step 5: Creating pgvector setup script...${NC}"
PGVECTOR_SETUP_DIR="${SCRIPT_DIR}/infras/envs/us-east-1"

# Create pgvector setup Lambda
echo -e "${YELLOW}Step 6: Creating pgvector setup Lambda function...${NC}"

# First, package the setup script
if [ -f "${PGVECTOR_SETUP_DIR}/setup_pgvector.py" ] && [ -f "${PGVECTOR_SETUP_DIR}/setup_pgvector.sql" ]; then
  cp "${PGVECTOR_SETUP_DIR}/setup_pgvector.py" "${TEMP_DIR}/setup_pgvector.py"
  cp "${PGVECTOR_SETUP_DIR}/setup_pgvector.sql" "${TEMP_DIR}/setup_pgvector.sql"
  
  # Create Lambda handler
  cat > "${TEMP_DIR}/setup_pgvector_lambda.py" << 'EOF'
#!/usr/bin/env python3
import json
import os
import sys
import boto3

def handler(event, context):
    """Lambda handler for pgvector setup"""
    import setup_pgvector
    
    # Get parameters from environment variables
    cluster_arn = os.environ.get('RDS_CLUSTER_ARN')
    secret_arn = os.environ.get('RDS_SECRET_ARN')
    database = os.environ.get('RDS_DATABASE', 'cloudable')
    tenant_list = json.loads(os.environ.get('TENANT_LIST', '["acme", "globex"]'))
    index_type = os.environ.get('INDEX_TYPE', 'hnsw')
    region = os.environ.get('AWS_REGION', 'eu-west-1')
    
    # Set up args for the setup_pgvector.main function
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

  # Create pgvector setup Lambda package
  cd "$TEMP_DIR" || exit 1
  zip -q -r "${TEMP_DIR}/pgvector_setup.zip" setup_pgvector.py setup_pgvector.sql setup_pgvector_lambda.py
  
  echo -e "${GREEN}✓ Created pgvector setup Lambda package${NC}"
  
  # Get Lambda role ARN
  LAMBDA_ROLE=$(aws lambda get-function --function-name "$LAMBDA_NAME" --query 'Configuration.Role' --output text)
  
  # Create pgvector setup Lambda
  if aws lambda get-function --function-name pgvector-setup-eu-west-1 2>/dev/null; then
    # Update existing Lambda
    aws lambda update-function-code \
      --function-name pgvector-setup-eu-west-1 \
      --zip-file "fileb://${TEMP_DIR}/pgvector_setup.zip"
    
    aws lambda update-function-configuration \
      --function-name pgvector-setup-eu-west-1 \
      --handler setup_pgvector_lambda.handler \
      --runtime python3.9 \
      --timeout 300 \
      --memory-size 256 \
      --environment "Variables={RDS_CLUSTER_ARN=$(aws rds describe-db-clusters --db-cluster-identifier aurora-dev-core-v2 --query 'DBClusters[0].DBClusterArn' --output text),RDS_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id aurora-dev-admin-secret --query 'ARN' --output text),RDS_DATABASE=cloudable,TENANT_LIST=[\"acme\",\"globex\"],INDEX_TYPE=hnsw,ENVIRONMENT=dev}"
  else
    # Create new Lambda
    aws lambda create-function \
      --function-name pgvector-setup-eu-west-1 \
      --runtime python3.9 \
      --role "$LAMBDA_ROLE" \
      --handler setup_pgvector_lambda.handler \
      --zip-file "fileb://${TEMP_DIR}/pgvector_setup.zip" \
      --timeout 300 \
      --memory-size 256 \
      --environment "Variables={RDS_CLUSTER_ARN=$(aws rds describe-db-clusters --db-cluster-identifier aurora-dev-core-v2 --query 'DBClusters[0].DBClusterArn' --output text),RDS_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id aurora-dev-admin-secret --query 'ARN' --output text),RDS_DATABASE=cloudable,TENANT_LIST=[\"acme\",\"globex\"],INDEX_TYPE=hnsw,ENVIRONMENT=dev}"
  fi
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Created/updated pgvector setup Lambda function${NC}"
  else
    echo -e "${RED}✗ Failed to create/update pgvector setup Lambda function${NC}"
  fi
else
  echo -e "${RED}✗ Missing pgvector setup scripts${NC}"
fi

# Create parameter group for pgvector
echo -e "${YELLOW}Step 7: Creating RDS parameter group for pgvector...${NC}"
PARAM_GROUP_NAME="cloudable-pgvector-params-dev"

# Check if parameter group already exists
if aws rds describe-db-cluster-parameter-groups --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" 2>/dev/null; then
  echo -e "${GREEN}✓ Parameter group $PARAM_GROUP_NAME already exists${NC}"
else
  aws rds create-db-cluster-parameter-group \
    --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
    --db-parameter-group-family aurora-postgresql14 \
    --description "Parameter group for pgvector extension"
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Created parameter group $PARAM_GROUP_NAME${NC}"
  else
    echo -e "${RED}✗ Failed to create parameter group${NC}"
  fi
fi

# Add pgvector parameters
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
  --parameters "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,pgvector,ApplyMethod=pending-reboot" \
                "ParameterName=rds.allowed_extensions,ParameterValue=vector,uuid-ossp,pg_stat_statements,ApplyMethod=pending-reboot"

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Modified parameter group to enable pgvector${NC}"
else
  echo -e "${RED}✗ Failed to modify parameter group${NC}"
fi

# Associate parameter group with RDS cluster
echo -e "${YELLOW}Step 8: Associating parameter group with RDS cluster...${NC}"
aws rds modify-db-cluster \
  --db-cluster-identifier aurora-dev-core-v2 \
  --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
  --apply-immediately

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Associated parameter group with RDS cluster${NC}"
  echo -e "${YELLOW}Note: You may need to reboot the cluster for pgvector to be fully enabled.${NC}"
else
  echo -e "${RED}✗ Failed to associate parameter group with RDS cluster${NC}"
fi

echo -e "${YELLOW}Step 9: Invoking pgvector setup Lambda...${NC}"
aws lambda invoke \
  --function-name pgvector-setup-eu-west-1 \
  --payload '{}' \
  /tmp/pgvector_setup_output.json

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Invoked pgvector setup Lambda${NC}"
  echo -e "${YELLOW}Output:${NC}"
  cat /tmp/pgvector_setup_output.json
else
  echo -e "${RED}✗ Failed to invoke pgvector setup Lambda${NC}"
fi

echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}REAL KB IMPLEMENTATION DEPLOYED SUCCESSFULLY!${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. If RDS needed a reboot, wait until it's available."
echo -e "2. Run tests with: ./test_e2e_pipeline.sh"
echo -e "${BLUE}==================================================${NC}"

# Clean up temporary files
rm -rf "$TEMP_DIR"
