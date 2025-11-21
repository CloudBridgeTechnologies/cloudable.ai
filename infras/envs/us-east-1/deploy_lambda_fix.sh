#!/bin/bash
# Deploy fixes to Lambda functions for pgvector compatibility

set -e

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check for AWS CLI availability
echo -e "${BLUE}Checking AWS CLI...${NC}"
if ! command -v aws &> /dev/null; then
  echo -e "${RED}AWS CLI not found. Please install it before running this script.${NC}"
  exit 1
fi

# Load AWS environment variables if available
if [ -f "../../set_aws_env.sh" ]; then
  echo -e "${BLUE}Loading AWS environment variables...${NC}"
  source ../../set_aws_env.sh
fi

# Check AWS credentials
AWS_IDENTITY=$(aws sts get-caller-identity 2>/dev/null)
if [ $? -ne 0 ]; then
  echo -e "${RED}AWS authentication failed. Please check your credentials.${NC}"
  exit 1
fi
echo -e "${GREEN}AWS credentials verified!${NC}"

# Set region
REGION=${AWS_REGION:-"us-east-1"}

# Get Lambda functions
echo -e "\n${YELLOW}Finding Lambda functions...${NC}"
KB_MANAGER=$(aws lambda list-functions --region $REGION --query "Functions[?contains(FunctionName,'kb-manager')].FunctionName" --output text)
if [ -z "$KB_MANAGER" ]; then
  echo -e "${RED}KB Manager Lambda function not found${NC}"
  exit 1
fi
echo -e "${GREEN}Found KB Manager Lambda: $KB_MANAGER${NC}"

# Create a temp directory for packaging
echo -e "\n${YELLOW}Creating deployment package...${NC}"
TEMP_DIR=$(mktemp -d)
echo -e "Using temp directory: $TEMP_DIR"

# Copy Lambda files to temp directory
REPO_ROOT=/Users/adrian/Projects/Cloudable.AI
cp $REPO_ROOT/infras/lambdas/kb_manager/main.py $TEMP_DIR/
cp $REPO_ROOT/infras/lambdas/kb_manager/rest_adapter.py $TEMP_DIR/

# Add a file to show the deployment was updated
cat > $TEMP_DIR/pgvector_fix.py << EOF
"""
This file indicates that the pgvector fix has been applied to the Lambda function.
Fix applied: $(date)

Changes made:
1. Updated vector format for pgvector compatibility (using brackets instead of braces)
2. Fixed JSON parsing in rest_adapter to handle both string and dict formats
3. Changed vector parameter format for RDS Data API compatibility
"""

# Version of the fix
PGVECTOR_FIX_VERSION = '1.0.0'
EOF

# Create a ZIP file
cd $TEMP_DIR
zip -r function.zip .
cd -

# Update the Lambda function
echo -e "\n${YELLOW}Updating Lambda function $KB_MANAGER...${NC}"
aws lambda update-function-code \
  --function-name $KB_MANAGER \
  --zip-file fileb://$TEMP_DIR/function.zip \
  --region $REGION

if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to update Lambda function${NC}"
  exit 1
fi

echo -e "${GREEN}Lambda function updated successfully!${NC}"

# Clean up
echo -e "\n${YELLOW}Cleaning up...${NC}"
rm -rf $TEMP_DIR
echo -e "${GREEN}Temporary files removed${NC}"

# Update Lambda environment variables
echo -e "\n${YELLOW}Checking Lambda environment variables...${NC}"
LAMBDA_CONFIG=$(aws lambda get-function-configuration --function-name $KB_MANAGER --region $REGION)
if [ $? -ne 0 ]; then
  echo -e "${RED}Failed to get Lambda configuration${NC}"
  exit 1
fi

# Check if the necessary environment variables are set
RDS_CLUSTER_ARN=$(echo $LAMBDA_CONFIG | jq -r '.Environment.Variables.RDS_CLUSTER_ARN // ""')
RDS_SECRET_ARN=$(echo $LAMBDA_CONFIG | jq -r '.Environment.Variables.RDS_SECRET_ARN // ""')

if [ -z "$RDS_CLUSTER_ARN" ] || [ -z "$RDS_SECRET_ARN" ]; then
  echo -e "${YELLOW}RDS environment variables not properly set. Would you like to update them? (y/N)${NC}"
  read -p "Enter choice: " UPDATE_ENV
  
  if [[ $UPDATE_ENV =~ ^[Yy]$ ]]; then
    # Get RDS cluster ARN
    CLUSTER_ARN=$(aws rds describe-db-clusters --region $REGION --query "DBClusters[?contains(DBClusterIdentifier,'aurora')].DBClusterArn | [0]" --output text)
    if [ -z "$CLUSTER_ARN" ] || [ "$CLUSTER_ARN" == "None" ]; then
      echo -e "${YELLOW}Could not find RDS cluster automatically. Please provide it manually.${NC}"
      read -p "Enter RDS cluster ARN: " CLUSTER_ARN
    fi
    
    # Get Secrets Manager ARN
    SECRET_ARN=$(aws secretsmanager list-secrets --region $REGION --query "SecretList[?contains(Name,'aurora') || contains(Name,'rds')].ARN | [0]" --output text)
    if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" == "None" ]; then
      echo -e "${YELLOW}Could not find RDS secret automatically. Please provide it manually.${NC}"
      read -p "Enter RDS secret ARN: " SECRET_ARN
    fi
    
    # Update the Lambda environment variables
    echo -e "\n${YELLOW}Updating Lambda environment variables...${NC}"
    aws lambda update-function-configuration \
      --function-name $KB_MANAGER \
      --environment "Variables={RDS_CLUSTER_ARN=$CLUSTER_ARN,RDS_SECRET_ARN=$SECRET_ARN,RDS_DATABASE=cloudable}" \
      --region $REGION
      
    if [ $? -ne 0 ]; then
      echo -e "${RED}Failed to update Lambda environment variables${NC}"
      exit 1
    fi
    echo -e "${GREEN}Lambda environment variables updated successfully!${NC}"
  fi
else
  echo -e "${GREEN}Lambda environment variables are already set:${NC}"
  echo -e "  RDS_CLUSTER_ARN: ${RDS_CLUSTER_ARN}"
  echo -e "  RDS_SECRET_ARN: ${RDS_SECRET_ARN}"
fi

echo -e "\n${GREEN}=====================================${NC}"
echo -e "${GREEN} LAMBDA FUNCTION UPDATE COMPLETED ${NC}"
echo -e "${GREEN}=====================================${NC}"
echo -e "\nYou can now test the Lambda functions with the end-to-end test script:"
echo -e "${BLUE}  ./e2e_rds_pgvector_test.sh${NC}"
