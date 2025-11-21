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
echo -e "${BLUE}   SETTING UP PGVECTOR IN AURORA POSTGRESQL      ${NC}"
echo -e "${BLUE}==================================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/cloudable_pgvector"
PGVECTOR_SETUP_DIR="${SCRIPT_DIR}/infras/envs/us-east-1"

# Create temporary directory
mkdir -p "$TEMP_DIR"

# Step 1: Create proper parameter group
echo -e "${YELLOW}Step 1: Creating RDS parameter group for pgvector...${NC}"
PARAM_GROUP_NAME="cloudable-pgvector-params-pg15-dev"

# Check if parameter group already exists
if aws rds describe-db-cluster-parameter-groups --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" 2>/dev/null; then
  echo -e "${GREEN}✓ Parameter group $PARAM_GROUP_NAME already exists${NC}"
else
  aws rds create-db-cluster-parameter-group \
    --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
    --db-parameter-group-family aurora-postgresql15 \
    --description "Parameter group for pgvector extension"
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Created parameter group $PARAM_GROUP_NAME${NC}"
  else
    echo -e "${RED}✗ Failed to create parameter group${NC}"
  fi
fi

# Add pgvector parameters - note the comma needs to be escaped with a backslash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
  --parameters "[{\"ParameterName\":\"rds.allowed_extensions\",\"ParameterValue\":\"vector,uuid-ossp,pg_stat_statements\",\"ApplyMethod\":\"pending-reboot\"}]"

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Modified parameter group to enable pgvector${NC}"
else
  echo -e "${RED}✗ Failed to modify parameter group${NC}"
fi

# Associate parameter group with RDS cluster
echo -e "${YELLOW}Step 2: Associating parameter group with RDS cluster...${NC}"
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

# Step 3: Create pgvector setup Lambda
echo -e "${YELLOW}Step 3: Creating pgvector setup Lambda function...${NC}"

# First, copy the fixed setup script
cp "${SCRIPT_DIR}/infras/envs/us-east-1/setup_pgvector_fixed.py" "${TEMP_DIR}/setup_pgvector.py"
cp "${PGVECTOR_SETUP_DIR}/setup_pgvector.sql" "${TEMP_DIR}/setup_pgvector.sql"
  
# Create Lambda handler
cat > "${TEMP_DIR}/lambda_function.py" << 'EOF'
import json
import os
import sys
import boto3
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
zip -q -r "${TEMP_DIR}/pgvector_setup.zip" setup_pgvector.py setup_pgvector.sql lambda_function.py

echo -e "${GREEN}✓ Created pgvector setup Lambda package${NC}"

# Get Lambda role ARN
LAMBDA_ROLE=$(aws lambda get-function --function-name kb-manager-dev-core --query 'Configuration.Role' --output text)

# Create pgvector setup Lambda
if aws lambda get-function --function-name pgvector-setup-eu-west-1 2>/dev/null; then
  # Update existing Lambda
  aws lambda update-function-code \
    --function-name pgvector-setup-eu-west-1 \
    --zip-file "fileb://${TEMP_DIR}/pgvector_setup.zip"
  
  aws lambda update-function-configuration \
    --function-name pgvector-setup-eu-west-1 \
    --handler lambda_function.handler \
    --runtime python3.9 \
    --timeout 300 \
    --memory-size 256 \
    --environment "Variables={RDS_CLUSTER_ARN=$(aws rds describe-db-clusters --db-cluster-identifier aurora-dev-core-v2 --query 'DBClusters[0].DBClusterArn' --output text),RDS_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id aurora-dev-admin-secret --query 'ARN' --output text),RDS_DATABASE=cloudable,TENANT_LIST=\"[\\\"acme\\\",\\\"globex\\\"]\",INDEX_TYPE=hnsw,ENVIRONMENT=dev}"
else
  # Create new Lambda
  aws lambda create-function \
    --function-name pgvector-setup-eu-west-1 \
    --runtime python3.9 \
    --role "$LAMBDA_ROLE" \
    --handler lambda_function.handler \
    --zip-file "fileb://${TEMP_DIR}/pgvector_setup.zip" \
    --timeout 300 \
    --memory-size 256 \
    --environment "Variables={RDS_CLUSTER_ARN=$(aws rds describe-db-clusters --db-cluster-identifier aurora-dev-core-v2 --query 'DBClusters[0].DBClusterArn' --output text),RDS_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id aurora-dev-admin-secret --query 'ARN' --output text),RDS_DATABASE=cloudable,TENANT_LIST=\"[\\\"acme\\\",\\\"globex\\\"]\",INDEX_TYPE=hnsw,ENVIRONMENT=dev}"
fi

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Created/updated pgvector setup Lambda function${NC}"
else
  echo -e "${RED}✗ Failed to create/update pgvector setup Lambda function${NC}"
fi

# Step 4: Reboot the RDS cluster to apply parameter group changes
echo -e "${YELLOW}Step 4: Do you want to reboot the RDS cluster to enable pgvector? (y/n)${NC}"
read -p "Reboot? " -n 1 -r
echo    # move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}Rebooting RDS cluster...${NC}"
  aws rds reboot-db-instance \
    --db-instance-identifier aurora-dev-instance-1-v3
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ RDS cluster reboot initiated${NC}"
    echo -e "${YELLOW}Waiting for RDS cluster to become available...${NC}"
    aws rds wait db-instance-available --db-instance-identifier aurora-dev-instance-1-v3
    echo -e "${GREEN}✓ RDS cluster is available${NC}"
  else
    echo -e "${RED}✗ Failed to reboot RDS cluster${NC}"
  fi
else
  echo -e "${YELLOW}Skipping RDS cluster reboot${NC}"
  echo -e "${YELLOW}Note: pgvector extension may not be enabled until you reboot the cluster${NC}"
fi

echo -e "${YELLOW}Step 5: Invoking pgvector setup Lambda...${NC}"
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
echo -e "${GREEN}PGVECTOR SETUP COMPLETED!${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Make sure the KB Manager Lambda points to handler main.handler${NC}"
echo -e "2. Run tests with: ./test_e2e_pipeline.sh"
echo -e "${BLUE}==================================================${NC}"

# Clean up temporary files
rm -rf "$TEMP_DIR"
