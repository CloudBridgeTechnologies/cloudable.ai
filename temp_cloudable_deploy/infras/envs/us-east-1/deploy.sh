#!/bin/bash
# Complete deployment script for Cloudable.AI with pgvector

set -e

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print steps
print_step() {
  echo -e "\n${YELLOW}STEP $1: $2${NC}"
}

# Function to print success message
print_success() {
  echo -e "${GREEN}$1${NC}"
}

# Function to print error message and exit
print_error() {
  echo -e "${RED}ERROR: $1${NC}"
  exit 1
}

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI COMPLETE TERRAFORM DEPLOYMENT ${NC}"
echo -e "${BLUE}==============================================${NC}"

# Check if terraform is installed
print_step "1" "Checking prerequisites"
if ! command -v terraform &> /dev/null; then
  print_error "Terraform is not installed. Please install it before running this script."
fi
print_success "✓ Terraform is installed"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
  print_error "AWS CLI is not installed. Please install it before running this script."
fi
print_success "✓ AWS CLI is installed"

# Check AWS credentials
aws sts get-caller-identity > /dev/null 2>&1
if [ $? -ne 0 ]; then
  print_error "AWS authentication failed. Please configure your AWS credentials."
fi
print_success "✓ AWS credentials verified"

# Get AWS account ID for confirmation
AWS_ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text)
AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
  AWS_REGION="us-east-1"
fi

# Get VPC details for deployment
print_step "2" "Getting VPC details"
VPC_ID=$(aws ec2 describe-vpcs --region $AWS_REGION --query "Vpcs[0].VpcId" --output text)
if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
  print_error "Could not find a VPC in region $AWS_REGION. Please create one before running this script."
fi
print_success "✓ Using VPC ID: $VPC_ID"

# Get subnet details
SUBNET_IDS=$(aws ec2 describe-subnets --region $AWS_REGION --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text | tr '\t' ',')
if [ -z "$SUBNET_IDS" ] || [ "$SUBNET_IDS" == "None" ]; then
  print_error "Could not find subnets in VPC $VPC_ID. Please create subnets before running this script."
fi
print_success "✓ Using subnet IDs: $SUBNET_IDS"

# Confirm deployment
print_step "3" "Confirming deployment"
echo -e "You are about to deploy Cloudable.AI with pgvector to:"
echo -e "  - AWS Account: ${BLUE}$AWS_ACCOUNT${NC}"
echo -e "  - Region: ${BLUE}$AWS_REGION${NC}"
echo -e "  - VPC: ${BLUE}$VPC_ID${NC}"
echo -e "  - Subnets: ${BLUE}$SUBNET_IDS${NC}"
echo -e "\nThis will deploy:"
echo -e "  - Aurora PostgreSQL cluster with pgvector extension"
echo -e "  - Lambda functions for KB management"
echo -e "  - S3 buckets for each tenant"
echo -e "  - Bedrock knowledge bases"
echo -e "  - IAM roles and policies"
echo -e "  - CloudWatch logs and metrics"
echo
read -p "Do you want to proceed with the deployment? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo -e "${BLUE}Deployment cancelled.${NC}"
  exit 0
fi

# Create terraform.tfvars file
print_step "4" "Creating terraform.tfvars file"
cat > terraform.tfvars << EOF
region     = "$AWS_REGION"
environment = "dev"
vpc_id     = "$VPC_ID"
subnet_ids = [${SUBNET_IDS//,/\",\"}]
tenant_ids = ["acme", "globex", "t001"]
db_name    = "cloudable"
EOF
print_success "✓ Created terraform.tfvars file"

# Initialize Terraform
print_step "5" "Initializing Terraform"
terraform init
if [ $? -ne 0 ]; then
  print_error "Terraform initialization failed."
fi
print_success "✓ Terraform initialized successfully"

# Validate Terraform configuration
print_step "6" "Validating Terraform configuration"
terraform validate
if [ $? -ne 0 ]; then
  print_error "Terraform validation failed. Please fix the errors before continuing."
fi
print_success "✓ Terraform configuration is valid"

# Plan Terraform deployment
print_step "7" "Planning Terraform deployment"
terraform plan -out=cloudable.tfplan
if [ $? -ne 0 ]; then
  print_error "Failed to create Terraform plan."
fi
print_success "✓ Terraform plan created successfully"

# Confirm plan
echo
read -p "Do you want to apply the Terraform plan? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo -e "${BLUE}Deployment cancelled.${NC}"
  exit 0
fi

# Apply Terraform plan
print_step "8" "Deploying infrastructure with Terraform"
terraform apply cloudable.tfplan
if [ $? -ne 0 ]; then
  print_error "Terraform apply failed."
fi
print_success "✓ Infrastructure deployed successfully"

# Test the deployment
print_step "9" "Testing the deployment"
echo -e "Testing the setup with e2e_rds_pgvector_test.sh..."
cd ../..
./e2e_rds_pgvector_test.sh
if [ $? -ne 0 ]; then
  echo -e "${RED}✗ End-to-end test failed. Please check the logs for details.${NC}"
else
  print_success "✓ End-to-end test passed successfully"
fi

# Get output values
print_step "10" "Getting deployment outputs"
cd infras/envs/us-east-1
RDS_ENDPOINT=$(terraform output -raw rds_cluster_endpoint)
RDS_ARN=$(terraform output -raw rds_cluster_arn)

echo -e "\n${GREEN}==============================================${NC}"
echo -e "${GREEN}   DEPLOYMENT COMPLETED SUCCESSFULLY ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "\nDeployment details:"
echo -e "  - RDS endpoint: ${BLUE}$RDS_ENDPOINT${NC}"
echo -e "  - RDS ARN: ${BLUE}$RDS_ARN${NC}"
echo -e "\nThe Cloudable.AI application is now fully deployed and ready to use."
echo -e "You can test the application with:"
echo -e "  ${BLUE}./e2e_rds_pgvector_test.sh${NC}"
echo -e "\nTo clean up the deployment:"
echo -e "  ${BLUE}terraform destroy${NC}"
