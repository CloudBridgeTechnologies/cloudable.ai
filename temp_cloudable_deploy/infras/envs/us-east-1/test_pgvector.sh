#!/bin/bash
# Wrapper script to run test_pgvector.py with proper parameters

set -e

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Load AWS environment variables if available
if [ -f "../../set_aws_env.sh" ]; then
  echo -e "${BLUE}Loading AWS environment variables...${NC}"
  source ../../set_aws_env.sh
fi

# Check for AWS CLI availability
echo -e "${BLUE}Checking AWS CLI...${NC}"
if ! command -v aws &> /dev/null; then
  echo -e "${RED}AWS CLI not found. Please install it before running this script.${NC}"
  exit 1
fi

# Check required Python packages
echo -e "${BLUE}Checking required Python packages...${NC}"
python3 -c "import boto3, numpy" &> /dev/null
if [ $? -ne 0 ]; then
  echo -e "${YELLOW}Installing required Python packages...${NC}"
  pip3 install boto3 numpy
  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to install required packages. Please install manually:${NC}"
    echo "pip3 install boto3 numpy"
    exit 1
  fi
fi

# Check AWS credentials
if [ -z "$AWS_PROFILE" ] && [ -z "$AWS_ACCESS_KEY_ID" ]; then
  echo -e "${RED}AWS credentials not found. Please set AWS_PROFILE or AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY.${NC}"
  echo "You can source the set_aws_env.sh script to set these variables."
  exit 1
fi

# Set default values
REGION=${AWS_REGION:-"us-east-1"}
DATABASE="cloudable"
TENANT="acme"
INSERT_FLAG=""
COUNT=10
SEARCH_TERM="random"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --region)
      REGION="$2"
      shift 2
      ;;
    --database)
      DATABASE="$2"
      shift 2
      ;;
    --tenant)
      TENANT="$2"
      shift 2
      ;;
    --insert)
      INSERT_FLAG="--insert"
      shift
      ;;
    --count)
      COUNT="$2"
      shift 2
      ;;
    --search-term)
      SEARCH_TERM="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [--region REGION] [--database DB_NAME] [--tenant TENANT_NAME] [--insert] [--count NUM_VECTORS] [--search-term TERM]"
      echo ""
      echo "Options:"
      echo "  --region REGION      AWS region (default: us-east-1 or \$AWS_REGION)"
      echo "  --database DB_NAME   Database name (default: cloudable)"
      echo "  --tenant TENANT_NAME Tenant name to test with (default: acme)"
      echo "  --insert             Insert test vectors (default: false)"
      echo "  --count NUM_VECTORS  Number of test vectors to insert (default: 10)"
      echo "  --search-term TERM   Text search term for hybrid search (default: random)"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      echo "Use --help to see available options."
      exit 1
      ;;
  esac
done

# Check if we're logged in to AWS properly
echo -e "${BLUE}Verifying AWS credentials...${NC}"
aws sts get-caller-identity &> /tmp/aws_identity.log
if [ $? -ne 0 ]; then
  echo -e "${RED}AWS authentication failed. Please check your credentials.${NC}"
  cat /tmp/aws_identity.log
  exit 1
fi
echo -e "${GREEN}AWS credentials verified successfully!${NC}"

# Get RDS cluster ARN
echo -e "${BLUE}Retrieving RDS cluster ARN...${NC}"
CLUSTER_ARN=$(aws rds describe-db-clusters --region $REGION --query "DBClusters[?contains(DBClusterIdentifier,'cloudable')].DBClusterArn | [0]" --output text)
if [ -z "$CLUSTER_ARN" ] || [ "$CLUSTER_ARN" == "None" ]; then
  echo -e "${YELLOW}Could not find RDS cluster with 'cloudable' in the name. Please provide it manually.${NC}"
  read -p "Enter RDS cluster ARN: " CLUSTER_ARN
fi
echo -e "${GREEN}Using RDS cluster: $CLUSTER_ARN${NC}"

# Get Secrets Manager ARN
echo -e "${BLUE}Retrieving RDS secret ARN...${NC}"
SECRET_ARN=$(aws secretsmanager list-secrets --region $REGION --query "SecretList[?contains(Name,'cloudable') && contains(Name,'rds')].ARN | [0]" --output text)
if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" == "None" ]; then
  echo -e "${YELLOW}Could not find Secrets Manager secret with 'cloudable' and 'rds' in the name. Please provide it manually.${NC}"
  read -p "Enter Secrets Manager ARN for RDS credentials: " SECRET_ARN
fi
echo -e "${GREEN}Using secret ARN: $SECRET_ARN${NC}"

# Run the test script
echo -e "${YELLOW}Running pgvector tests with the following configuration:${NC}"
echo "  - Region: $REGION"
echo "  - Database: $DATABASE"
echo "  - Tenant: $TENANT"
if [ -n "$INSERT_FLAG" ]; then
  echo "  - Inserting $COUNT test vectors"
fi
echo "  - Search term: $SEARCH_TERM"

echo -e "${BLUE}Starting tests...${NC}"
python3 test_pgvector.py \
  --region "$REGION" \
  --database "$DATABASE" \
  --cluster-arn "$CLUSTER_ARN" \
  --secret-arn "$SECRET_ARN" \
  --tenant "$TENANT" \
  $INSERT_FLAG \
  --count "$COUNT" \
  --search-term "$SEARCH_TERM"

TEST_STATUS=$?
if [ $TEST_STATUS -ne 0 ]; then
  echo -e "${RED}Tests failed with exit code $TEST_STATUS${NC}"
  exit $TEST_STATUS
fi

echo -e "\n${GREEN}Tests completed successfully!${NC}"
