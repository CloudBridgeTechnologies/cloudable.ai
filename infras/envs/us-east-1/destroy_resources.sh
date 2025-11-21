#!/bin/bash
# Script to destroy all AWS resources created by the Terraform template

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI AWS RESOURCES CLEANUP SCRIPT      ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
  echo -e "${RED}Error: Terraform is not installed. Please install it first.${NC}"
  exit 1
fi

# Check AWS credentials
echo -e "\n${YELLOW}Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
  echo -e "${RED}Error: AWS credentials not found or invalid. Please configure AWS CLI.${NC}"
  exit 1
fi

# Get AWS account ID and region for confirmation
AWS_ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text)
AWS_REGION=$(aws configure get region || echo "us-east-1")

# Confirm destruction
echo -e "\n${RED}WARNING: This script will destroy ALL resources created by Terraform in:${NC}"
echo -e "${RED}- AWS Account: ${AWS_ACCOUNT}${NC}"
echo -e "${RED}- Region: ${AWS_REGION}${NC}"
echo -e "${RED}This action is IRREVERSIBLE and will result in DATA LOSS.${NC}"

# Detailed warning about what will be deleted
echo -e "\n${YELLOW}Resources that will be destroyed include:${NC}"
echo -e "- RDS PostgreSQL clusters and instances"
echo -e "- Lambda functions and their configurations"
echo -e "- S3 buckets and their contents"
echo -e "- IAM roles and policies"
echo -e "- KMS encryption keys"
echo -e "- CloudWatch log groups"
echo -e "- Secrets Manager secrets"
echo -e "- API Gateway APIs"
echo -e "- All other resources created through Terraform"

echo -e "\n${YELLOW}Please type 'DESTROY' (all caps) to confirm:${NC}"
read confirmation

if [ "$confirmation" != "DESTROY" ]; then
  echo -e "${GREEN}Destruction cancelled.${NC}"
  exit 0
fi

# Check Terraform state
echo -e "\n${YELLOW}Checking Terraform state...${NC}"

# Navigate to the terraform directory
cd "$(dirname "$0")"

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ]; then
  echo -e "${YELLOW}Warning: terraform.tfstate not found in current directory.${NC}"
  
  # Try to find terraform state files
  STATE_FILES=$(find . -name "terraform.tfstate" | wc -l)
  if [ "$STATE_FILES" -eq "0" ]; then
    echo -e "${RED}Error: No terraform state files found. Cannot proceed with destruction.${NC}"
    echo -e "If resources were created without Terraform, you must delete them manually.${NC}"
    exit 1
  fi
  
  # If multiple state files found, ask user which one to use
  if [ "$STATE_FILES" -gt "1" ]; then
    echo -e "${YELLOW}Multiple terraform state files found:${NC}"
    find . -name "terraform.tfstate" | nl
    echo -e "${YELLOW}Enter the number of the state file to use:${NC}"
    read state_file_number
    
    STATE_FILE=$(find . -name "terraform.tfstate" | sed -n "${state_file_number}p")
    
    if [ -z "$STATE_FILE" ]; then
      echo -e "${RED}Invalid selection. Aborting.${NC}"
      exit 1
    fi
    
    echo -e "${YELLOW}Using state file: ${STATE_FILE}${NC}"
    cd "$(dirname "$STATE_FILE")"
  fi
fi

# Initialize Terraform
echo -e "\n${YELLOW}Initializing Terraform...${NC}"
terraform init

if [ $? -ne 0 ]; then
  echo -e "${RED}Error initializing Terraform. Please check the error message above.${NC}"
  exit 1
fi

# Show what will be destroyed
echo -e "\n${YELLOW}Generating destruction plan...${NC}"
terraform plan -destroy -out=destroy.tfplan

if [ $? -ne 0 ]; then
  echo -e "${RED}Error generating destruction plan. Please check the error message above.${NC}"
  exit 1
fi

# Final confirmation
echo -e "\n${RED}FINAL WARNING: This will destroy all resources in the Terraform state.${NC}"
echo -e "${YELLOW}Continue with destruction? (yes/no)${NC}"
read final_confirmation

if [ "$final_confirmation" != "yes" ]; then
  echo -e "${GREEN}Destruction cancelled.${NC}"
  rm -f destroy.tfplan
  exit 0
fi

# Perform destruction
echo -e "\n${YELLOW}Destroying all resources...${NC}"
terraform apply destroy.tfplan

if [ $? -ne 0 ]; then
  echo -e "${RED}Error destroying resources. Some resources may remain.${NC}"
  echo -e "${YELLOW}Check the error messages above and try again, or clean up manually.${NC}"
  exit 1
fi

# Clean up plan file
rm -f destroy.tfplan

# Optional: Clean S3 buckets forcefully if any remain
echo -e "\n${YELLOW}Checking for remaining S3 buckets with 'cloudable' in the name...${NC}"
BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'cloudable')].Name" --output text)

if [ -n "$BUCKETS" ]; then
  echo -e "${YELLOW}Found cloudable S3 buckets that still exist:${NC}"
  echo "$BUCKETS"
  
  echo -e "${YELLOW}Would you like to forcefully delete these buckets and their contents? (yes/no)${NC}"
  read delete_buckets
  
  if [ "$delete_buckets" = "yes" ]; then
    for bucket in $BUCKETS; do
      echo -e "${YELLOW}Emptying and deleting bucket: ${bucket}${NC}"
      aws s3 rm s3://${bucket} --recursive
      aws s3api delete-bucket --bucket ${bucket}
      
      if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully deleted bucket: ${bucket}${NC}"
      else
        echo -e "${RED}Failed to delete bucket: ${bucket}${NC}"
      fi
    done
  fi
else
  echo -e "${GREEN}No remaining cloudable S3 buckets found.${NC}"
fi

# Final summary
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}Resource destruction complete!${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "All Terraform-managed resources have been destroyed.\n"
echo -e "${YELLOW}Note: Some resources might still exist if:${NC}"
echo -e "- They were created outside of Terraform"
echo -e "- They had deletion protection enabled"
echo -e "- There were errors during the destruction process"
echo -e "\nCheck the AWS Management Console to verify all resources have been removed."
