#!/bin/bash

# Script to destroy all Cloudable.AI resources managed by Terraform

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================="
echo "  DESTROYING ALL CLOUDABLE.AI TERRAFORM RESOURCES"
echo -e "==========================================================${NC}"

# Set AWS region for this session
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1
echo -e "Using AWS Region: ${GREEN}$AWS_DEFAULT_REGION${NC}"

# Check for required tools
which terraform > /dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}Terraform not found. Please install Terraform to continue.${NC}"
    exit 1
fi

# Change to Terraform directory
TERRAFORM_DIR="/Users/adrian/Projects/Cloudable.AI/infras/terraform"
if [ -d "$TERRAFORM_DIR" ]; then
    cd "$TERRAFORM_DIR"
    echo -e "Changed directory to ${GREEN}$TERRAFORM_DIR${NC}"
else
    echo -e "${YELLOW}Terraform directory not found at $TERRAFORM_DIR. Using current directory.${NC}"
    # Create directory if it doesn't exist
    mkdir -p infras/terraform
    cd infras/terraform
fi

# Remove existing backend.tf if it exists
if [ -f "backend.tf" ]; then
  echo -e "${YELLOW}Removing existing backend.tf to avoid conflicts...${NC}"
  rm backend.tf
fi

echo -e "\n${YELLOW}Initializing Terraform...${NC}"
terraform init -reconfigure

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to initialize Terraform. Please check the error messages above.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Planning destruction of resources...${NC}"
terraform plan -destroy -out=destroy.tfplan

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create destruction plan. Please check the error messages above.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Are you sure you want to destroy all resources? This cannot be undone.${NC}"
echo -e "${RED}Type 'yes-destroy-all' to confirm:${NC}"
read -r confirmation

if [ "$confirmation" != "yes-destroy-all" ]; then
    echo -e "${BLUE}Destruction cancelled.${NC}"
    exit 0
fi

echo -e "\n${YELLOW}Destroying resources...${NC}"
terraform apply destroy.tfplan

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to destroy resources. Please check the error messages above.${NC}"
    exit 1
fi

echo -e "\n${GREEN}All Terraform-managed resources have been destroyed.${NC}"

# Clean up additional resources that might not be covered by Terraform

echo -e "\n${YELLOW}Cleaning up additional resources...${NC}"

# Clean up Lambda functions
echo -e "\n${YELLOW}Cleaning up Lambda functions...${NC}"
lambda_functions=$(aws lambda list-functions --query "Functions[?contains(FunctionName, 'kb-manager') || contains(FunctionName, 'cloudable')].FunctionName" --output text)
for func in $lambda_functions; do
    echo -e "Deleting Lambda function: ${YELLOW}$func${NC}"
    aws lambda delete-function --function-name "$func" || true
done

# Clean up CloudWatch log groups
echo -e "\n${YELLOW}Cleaning up CloudWatch log groups...${NC}"
log_groups=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, 'kb-manager') || contains(logGroupName, 'cloudable') || contains(logGroupName, '/aws/lambda/kb-manager')].logGroupName" --output text)
for log_group in $log_groups; do
    echo -e "Deleting log group: ${YELLOW}$log_group${NC}"
    aws logs delete-log-group --log-group-name "$log_group" || true
done

# Clean up S3 buckets
echo -e "\n${YELLOW}Cleaning up S3 buckets...${NC}"
buckets=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'cloudable')].Name" --output text)
for bucket in $buckets; do
    echo -e "Emptying and deleting S3 bucket: ${YELLOW}$bucket${NC}"
    aws s3 rm s3://$bucket --recursive || true
    aws s3api delete-bucket --bucket $bucket || true
done

# Clean up API Gateway
echo -e "\n${YELLOW}Cleaning up API Gateway...${NC}"
# HTTP APIs
apis=$(aws apigatewayv2 get-apis --query "Items[?contains(Name, 'cloudable')].ApiId" --output text)
for api in $apis; do
    echo -e "Deleting API Gateway: ${YELLOW}$api${NC}"
    aws apigatewayv2 delete-api --api-id "$api" || true
done

# REST APIs
rest_apis=$(aws apigateway get-rest-apis --query "items[?contains(name, 'cloudable')].id" --output text)
for api in $rest_apis; do
    echo -e "Deleting REST API Gateway: ${YELLOW}$api${NC}"
    aws apigateway delete-rest-api --rest-api-id "$api" || true
done

# Clean up RDS instances and clusters
echo -e "\n${YELLOW}Cleaning up RDS resources...${NC}"
# Disable deletion protection on clusters
clusters=$(aws rds describe-db-clusters --query "DBClusters[?contains(DBClusterIdentifier, 'aurora-dev') || contains(DBClusterIdentifier, 'cloudable')].DBClusterIdentifier" --output text)
for cluster in $clusters; do
    echo -e "Disabling deletion protection on RDS cluster: ${YELLOW}$cluster${NC}"
    aws rds modify-db-cluster --db-cluster-identifier "$cluster" --no-deletion-protection --apply-immediately || true
    
    echo -e "Deleting RDS cluster: ${YELLOW}$cluster${NC}"
    aws rds delete-db-cluster --db-cluster-identifier "$cluster" --skip-final-snapshot || true
done

# Clean up network interfaces
echo -e "\n${YELLOW}Cleaning up network interfaces...${NC}"
# List ENIs associated with Lambda functions or RDS
enis=$(aws ec2 describe-network-interfaces --filters "Name=description,Values=*Lambda*,*RDS*,*cloudable*" --query "NetworkInterfaces[].NetworkInterfaceId" --output text)
for eni in $enis; do
    echo -e "Deleting network interface: ${YELLOW}$eni${NC}"
    aws ec2 delete-network-interface --network-interface-id "$eni" || true
done

# Clean up security groups
echo -e "\n${YELLOW}Cleaning up security groups...${NC}"
sgs=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=*lambda*,*rds*,*cloudable*" --query "SecurityGroups[].GroupId" --output text)
for sg in $sgs; do
    echo -e "Deleting security group: ${YELLOW}$sg${NC}"
    aws ec2 delete-security-group --group-id "$sg" || true
done

echo -e "\n${BLUE}=========================================================="
echo "  ALL RESOURCES CLEANED UP"
echo -e "==========================================================${NC}"
echo -e "\n${GREEN}Cloudable.AI resources have been successfully destroyed.${NC}"
echo -e "You can now safely restart your work on Monday."
