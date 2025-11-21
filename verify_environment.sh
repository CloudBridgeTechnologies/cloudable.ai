#!/bin/bash
# Verify AWS Environment for Cloudable.AI Testing

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}       CLOUDABLE.AI ENVIRONMENT VERIFICATION      ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check for AWS CLI
echo -e "\n${YELLOW}1. Checking for AWS CLI...${NC}"
if command_exists aws; then
  aws_version=$(aws --version)
  echo -e "${GREEN}✓ AWS CLI is installed: ${aws_version}${NC}"
else
  echo -e "${RED}✗ AWS CLI is not installed. Please install it before running tests.${NC}"
  echo -e "  Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  exit 1
fi

# Check for jq
echo -e "\n${YELLOW}2. Checking for jq...${NC}"
if command_exists jq; then
  jq_version=$(jq --version)
  echo -e "${GREEN}✓ jq is installed: ${jq_version}${NC}"
else
  echo -e "${RED}✗ jq is not installed. Please install it before running tests.${NC}"
  echo -e "  On macOS: brew install jq"
  echo -e "  On Linux: apt-get install jq or yum install jq"
  exit 1
fi

# Check for Python
echo -e "\n${YELLOW}3. Checking for Python...${NC}"
if command_exists python3; then
  python_version=$(python3 --version)
  echo -e "${GREEN}✓ Python is installed: ${python_version}${NC}"
else
  echo -e "${RED}✗ Python 3 is not installed. Please install it before running tests.${NC}"
  exit 1
fi

# Check for curl
echo -e "\n${YELLOW}4. Checking for curl...${NC}"
if command_exists curl; then
  curl_version=$(curl --version | head -n 1)
  echo -e "${GREEN}✓ curl is installed: ${curl_version}${NC}"
else
  echo -e "${RED}✗ curl is not installed. Please install it before running tests.${NC}"
  exit 1
fi

# Check AWS credentials
echo -e "\n${YELLOW}5. Checking AWS credentials...${NC}"
if aws sts get-caller-identity &>/dev/null; then
  caller_identity=$(aws sts get-caller-identity --output json)
  account_id=$(echo $caller_identity | jq -r .Account)
  user_id=$(echo $caller_identity | jq -r .UserId)
  arn=$(echo $caller_identity | jq -r .Arn)
  echo -e "${GREEN}✓ AWS credentials are configured${NC}"
  echo -e "  Account ID: $account_id"
  echo -e "  User ID: $user_id"
  echo -e "  ARN: $arn"
else
  echo -e "${RED}✗ AWS credentials are not configured or invalid.${NC}"
  echo -e "  Please run 'aws configure' to set up your credentials."
  exit 1
fi

# Check AWS region
echo -e "\n${YELLOW}6. Checking AWS region...${NC}"
current_region=$(aws configure get region)
if [ -z "$current_region" ]; then
  echo -e "${YELLOW}⚠ AWS region is not set. Defaulting to us-east-1.${NC}"
  export AWS_REGION="us-east-1"
else
  echo -e "${GREEN}✓ AWS region is set to: $current_region${NC}"
  export AWS_REGION="$current_region"
fi

# Check Lambda functions
echo -e "\n${YELLOW}7. Checking Lambda functions...${NC}"

# Check kb-manager Lambda
kb_manager_exists=$(aws lambda list-functions --region $AWS_REGION --query "Functions[?FunctionName=='kb-manager-dev'].FunctionName" --output text)
if [ -n "$kb_manager_exists" ]; then
  echo -e "${GREEN}✓ kb-manager-dev Lambda function exists${NC}"
  kb_manager_config=$(aws lambda get-function-configuration --function-name kb-manager-dev --region $AWS_REGION)
  kb_manager_runtime=$(echo $kb_manager_config | jq -r .Runtime)
  kb_manager_handler=$(echo $kb_manager_config | jq -r .Handler)
  echo -e "  Runtime: $kb_manager_runtime"
  echo -e "  Handler: $kb_manager_handler"
else
  echo -e "${RED}✗ kb-manager-dev Lambda function does not exist.${NC}"
  echo -e "  You need to deploy the Lambda function before running tests."
  exit 1
fi

# Check orchestrator Lambda
orchestrator_exists=$(aws lambda list-functions --region $AWS_REGION --query "Functions[?FunctionName=='orchestrator-dev'].FunctionName" --output text)
if [ -n "$orchestrator_exists" ]; then
  echo -e "${GREEN}✓ orchestrator-dev Lambda function exists${NC}"
else
  echo -e "${YELLOW}⚠ orchestrator-dev Lambda function does not exist.${NC}"
  echo -e "  Some tests might fail without this function."
fi

# Check RDS cluster
echo -e "\n${YELLOW}8. Checking RDS cluster...${NC}"
rds_cluster=$(aws rds describe-db-clusters --region $AWS_REGION --query "DBClusters[?contains(DBClusterIdentifier,'aurora')].DBClusterIdentifier" --output text)
if [ -n "$rds_cluster" ]; then
  echo -e "${GREEN}✓ RDS cluster exists: $rds_cluster${NC}"
  rds_status=$(aws rds describe-db-clusters --region $AWS_REGION --db-cluster-identifier $rds_cluster --query "DBClusters[0].Status" --output text)
  echo -e "  Status: $rds_status"
else
  echo -e "${RED}✗ No Aurora RDS cluster found.${NC}"
  echo -e "  You need to deploy the RDS cluster before running tests."
  exit 1
fi

# Check S3 buckets
echo -e "\n${YELLOW}9. Checking S3 buckets...${NC}"
buckets=$(aws s3api list-buckets --query "Buckets[?contains(Name,'cloudable')].Name" --output text)
if [ -n "$buckets" ]; then
  echo -e "${GREEN}✓ Found Cloudable.AI S3 buckets:${NC}"
  for bucket in $buckets; do
    echo -e "  - $bucket"
  done
else
  echo -e "${YELLOW}⚠ No Cloudable.AI S3 buckets found.${NC}"
  echo -e "  You might need to deploy S3 buckets before running tests."
fi

# Check required Python packages
echo -e "\n${YELLOW}10. Checking required Python packages...${NC}"
required_packages=("boto3" "requests" "numpy")
missing_packages=()

for package in "${required_packages[@]}"; do
  if ! python3 -c "import $package" &>/dev/null; then
    missing_packages+=("$package")
  fi
done

if [ ${#missing_packages[@]} -eq 0 ]; then
  echo -e "${GREEN}✓ All required Python packages are installed${NC}"
else
  echo -e "${YELLOW}⚠ Missing Python packages: ${missing_packages[*]}${NC}"
  echo -e "  Installing missing packages..."
  pip3 install ${missing_packages[*]} --quiet
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully installed missing packages${NC}"
  else
    echo -e "${RED}✗ Failed to install missing packages.${NC}"
    echo -e "  Please install them manually: pip3 install ${missing_packages[*]}"
  fi
fi

# Summary
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${BLUE}                VERIFICATION SUMMARY               ${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}✓ Environment verification completed${NC}"
echo -e "AWS CLI:          Installed"
echo -e "jq:               Installed"
echo -e "Python:           Installed"
echo -e "curl:             Installed"
echo -e "AWS Credentials:  Valid"
echo -e "AWS Region:       $AWS_REGION"
echo -e "Lambda Functions: kb-manager-dev found"
echo -e "RDS Cluster:      $rds_cluster ($rds_status)"
echo -e "S3 Buckets:       $(echo $buckets | wc -w) found"
echo -e "${BLUE}==================================================${NC}"
echo -e "\n${GREEN}✓ Environment is ready for testing!${NC}"
