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
echo -e "${BLUE}   CLOUDABLE.AI CORE INFRASTRUCTURE DEPLOYMENT    ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Initialize Terraform
echo -e "\n${YELLOW}Initializing Terraform...${NC}"
cd "$SCRIPT_DIR"
terraform init

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform initialization failed.${NC}"
    exit 1
fi

# Plan the deployment
echo -e "\n${YELLOW}Planning Terraform deployment...${NC}"
terraform plan -out=core_deploy.tfplan

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform plan failed.${NC}"
    exit 1
fi

# Apply the Terraform plan
echo -e "\n${YELLOW}Deploying core infrastructure...${NC}"
terraform apply "core_deploy.tfplan"

if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform apply failed.${NC}"
    exit 1
fi

# Extract outputs
echo -e "\n${YELLOW}Extracting deployment outputs...${NC}"
RDS_CLUSTER_ARN=$(terraform output -raw rds_cluster_arn)
RDS_CLUSTER_ENDPOINT=$(terraform output -raw rds_cluster_endpoint)
API_ENDPOINT=$(terraform output -raw api_endpoint)

# Save outputs for future reference
echo -e "\n${YELLOW}Saving deployment information...${NC}"
cat > "$SCRIPT_DIR/deployment_info.json" << EOF
{
  "rds_cluster_arn": "$RDS_CLUSTER_ARN",
  "rds_cluster_endpoint": "$RDS_CLUSTER_ENDPOINT",
  "api_endpoint": "$API_ENDPOINT"
}
EOF

echo -e "\n${GREEN}Core infrastructure deployed successfully!${NC}"
echo -e "${YELLOW}RDS Cluster ARN: ${RDS_CLUSTER_ARN}${NC}"
echo -e "${YELLOW}RDS Cluster Endpoint: ${RDS_CLUSTER_ENDPOINT}${NC}"
echo -e "${YELLOW}API Gateway Endpoint: ${API_ENDPOINT}${NC}"

# Wait for RDS to be fully available
echo -e "\n${YELLOW}Waiting for RDS to be fully available (2 minutes)...${NC}"
sleep 120

# Setup pgvector
echo -e "\n${YELLOW}Setting up pgvector in RDS...${NC}"
SECRET_ARN=$(aws secretsmanager list-secrets --query "SecretList[?Name=='aurora-dev-admin-secret'].ARN" --output text)

SETUP_PGVECTOR_PATH="$PARENT_DIR/envs/us-east-1/setup_pgvector.py"

if [ -f "$SETUP_PGVECTOR_PATH" ]; then
    if [ -n "$SECRET_ARN" ]; then
        python3 "$SETUP_PGVECTOR_PATH" --cluster-arn "$RDS_CLUSTER_ARN" --secret-arn "$SECRET_ARN" --database cloudable --tenant acme,globex --index-type hnsw
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Warning: pgvector setup had issues.${NC}"
        else
            echo -e "${GREEN}✓ Successfully set up pgvector${NC}"
        fi
    else
        echo -e "${RED}Error: Could not find Secret ARN for 'aurora-dev-admin-secret'.${NC}"
    fi
else
    echo -e "${RED}Error: setup_pgvector.py not found at $SETUP_PGVECTOR_PATH${NC}"
fi

# Test API endpoint
echo -e "\n${YELLOW}Testing API endpoint...${NC}"
curl -s "${API_ENDPOINT}/api/health"

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}DEPLOYMENT COMPLETE!${NC}"
echo -e "${BLUE}==================================================${NC}"

echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "1. Update Lambda code for full functionality"
echo -e "2. Test knowledge base operations with the uploaded test document"

exit 0
