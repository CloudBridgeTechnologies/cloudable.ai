#!/bin/bash
# Simple wrapper script to run simple_test_pgvector.py

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

# Check required Python packages
echo -e "${BLUE}Checking required Python packages...${NC}"
python3 -c "import sys; sys.exit(0 if all(x in sys.modules or __import__(x) for x in ['boto3', 'numpy']) else 1)" 2>/dev/null
if [ $? -ne 0 ]; then
  echo -e "${YELLOW}Installing required Python packages in a virtual environment...${NC}"
  cd "$(dirname "$0")/../../.."
  if [ ! -d "venv" ]; then
    python3 -m venv venv
  fi
  source venv/bin/activate
  pip install boto3 numpy
fi

# Load AWS environment variables if available
if [ -f "$(dirname "$0")/../../set_aws_env.sh" ]; then
  echo -e "${BLUE}Loading AWS environment variables...${NC}"
  source "$(dirname "$0")/../../set_aws_env.sh"
fi

# Check for AWS credentials
AWS_IDENTITY=$(aws sts get-caller-identity 2>/dev/null)
if [ $? -ne 0 ]; then
  echo -e "${RED}AWS authentication failed. Please check your credentials.${NC}"
  exit 1
fi
echo -e "${GREEN}AWS credentials verified successfully!${NC}"

# Set default values
REGION=${AWS_REGION:-"us-east-1"}
DATABASE="cloudable"

# Get RDS cluster ARN
echo -e "${BLUE}Retrieving RDS cluster ARN...${NC}"
CLUSTER_ARN=$(aws rds describe-db-clusters --region $REGION --query "DBClusters[?contains(DBClusterIdentifier,'aurora')].DBClusterArn | [0]" --output text)
if [ -z "$CLUSTER_ARN" ] || [ "$CLUSTER_ARN" == "None" ]; then
  echo -e "${YELLOW}Could not find RDS cluster with 'aurora' in the name. Please provide it manually.${NC}"
  read -p "Enter RDS cluster ARN: " CLUSTER_ARN
fi
echo -e "${GREEN}Using RDS cluster: $CLUSTER_ARN${NC}"

# Get Secrets Manager ARN
echo -e "${BLUE}Retrieving RDS secret ARN...${NC}"
SECRET_ARN=$(aws secretsmanager list-secrets --region $REGION --query "SecretList[?contains(Name,'aurora') || contains(Name,'rds')].ARN | [0]" --output text)
if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" == "None" ]; then
  echo -e "${YELLOW}Could not find Secrets Manager secret for RDS. Please provide it manually.${NC}"
  read -p "Enter Secrets Manager ARN for RDS credentials: " SECRET_ARN
fi
echo -e "${GREEN}Using secret ARN: $SECRET_ARN${NC}"

# Run the test script
echo -e "${YELLOW}Running simple pgvector tests with the following configuration:${NC}"
echo "  - Region: $REGION"
echo "  - Database: $DATABASE"
echo "  - Cluster ARN: $CLUSTER_ARN"
echo "  - Secret ARN: $SECRET_ARN"

echo -e "${BLUE}Starting tests...${NC}"
cd "$(dirname "$0")"
# Activate virtual environment if it exists
if [ -d "../../../venv" ]; then
  source ../../../venv/bin/activate
fi

python3 simple_test_pgvector.py \
  --region "$REGION" \
  --database "$DATABASE" \
  --cluster-arn "$CLUSTER_ARN" \
  --secret-arn "$SECRET_ARN"

TEST_STATUS=$?
if [ $TEST_STATUS -ne 0 ]; then
  echo -e "${RED}Tests failed with exit code $TEST_STATUS${NC}"
  exit $TEST_STATUS
fi

echo -e "\n${GREEN}Tests completed successfully!${NC}"
