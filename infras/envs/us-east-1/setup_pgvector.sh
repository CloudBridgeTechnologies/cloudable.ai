#!/bin/bash
# Wrapper script to run setup_pgvector.py with proper parameters

set -e

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load AWS environment variables if available
if [ -f "../../set_aws_env.sh" ]; then
  echo -e "${BLUE}Loading AWS environment variables...${NC}"
  source ../../set_aws_env.sh
fi

# Check for AWS CLI availability
echo -e "${BLUE}Checking AWS CLI...${NC}"
if ! command -v aws &> /dev/null; then
  echo "AWS CLI not found. Please install it before running this script."
  exit 1
fi

# Check AWS credentials
if [ -z "$AWS_PROFILE" ] && [ -z "$AWS_ACCESS_KEY_ID" ]; then
  echo "AWS credentials not found. Please set AWS_PROFILE or AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY."
  echo "You can source the set_aws_env.sh script to set these variables."
  exit 1
fi

# Set default values
REGION=${AWS_REGION:-"us-east-1"}
DATABASE="cloudable"
TENANTS=("acme" "globex" "t001")
INDEX_TYPE="hnsw"

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
    --tenants)
      # Convert comma-separated list to array
      IFS=',' read -r -a TENANTS <<< "$2"
      shift 2
      ;;
    --index-type)
      INDEX_TYPE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--region REGION] [--database DB_NAME] [--tenants tenant1,tenant2] [--index-type ivfflat|hnsw]"
      exit 1
      ;;
  esac
done

# Check if we're logged in to AWS properly
echo -e "${BLUE}Verifying AWS credentials...${NC}"
aws sts get-caller-identity &> /tmp/aws_identity.log
if [ $? -ne 0 ]; then
  echo "AWS authentication failed. Please check your credentials."
  cat /tmp/aws_identity.log
  exit 1
fi
echo -e "${GREEN}AWS credentials verified successfully!${NC}"

# Get RDS cluster ARN
echo -e "${BLUE}Retrieving RDS cluster ARN...${NC}"
CLUSTER_ARN=$(aws rds describe-db-clusters --region $REGION --query "DBClusters[?contains(DBClusterIdentifier,'cloudable')].DBClusterArn | [0]" --output text)
if [ -z "$CLUSTER_ARN" ] || [ "$CLUSTER_ARN" == "None" ]; then
  echo "Could not find RDS cluster with 'cloudable' in the name. Please provide it manually."
  read -p "Enter RDS cluster ARN: " CLUSTER_ARN
fi
echo -e "${GREEN}Using RDS cluster: $CLUSTER_ARN${NC}"

# Get Secrets Manager ARN
echo -e "${BLUE}Retrieving RDS secret ARN...${NC}"
SECRET_ARN=$(aws secretsmanager list-secrets --region $REGION --query "SecretList[?contains(Name,'cloudable') && contains(Name,'rds')].ARN | [0]" --output text)
if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" == "None" ]; then
  echo "Could not find Secrets Manager secret with 'cloudable' and 'rds' in the name. Please provide it manually."
  read -p "Enter Secrets Manager ARN for RDS credentials: " SECRET_ARN
fi
echo -e "${GREEN}Using secret ARN: $SECRET_ARN${NC}"

# Format tenants for Python command
TENANTS_STR=$(IFS=' '; echo "${TENANTS[*]}")

# Run the setup script
echo -e "${YELLOW}Running pgvector setup with the following configuration:${NC}"
echo "  - Region: $REGION"
echo "  - Database: $DATABASE"
echo "  - Cluster ARN: $CLUSTER_ARN"
echo "  - Secret ARN: $SECRET_ARN" 
echo "  - Tenants: ${TENANTS[*]}"
echo "  - Index Type: $INDEX_TYPE"

echo -e "${BLUE}Starting setup...${NC}"
python3 setup_pgvector.py \
  --region "$REGION" \
  --database "$DATABASE" \
  --cluster-arn "$CLUSTER_ARN" \
  --secret-arn "$SECRET_ARN" \
  --tenants $TENANTS_STR \
  --index-type "$INDEX_TYPE"

SETUP_STATUS=$?
if [ $SETUP_STATUS -ne 0 ]; then
  echo -e "${RED}Setup failed with exit code $SETUP_STATUS${NC}"
  exit $SETUP_STATUS
fi

echo -e "${GREEN}Setup completed successfully!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Verify tables by querying the database"
echo "  2. Test vector storage and retrieval with the KB Manager Lambda"
echo "  3. Run the e2e_rds_pgvector_test.sh script to validate the full pipeline"
