#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   LAMBDA FUNCTION CLEANUP                        ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Delete the Lambda function
LAMBDA_NAME="db-actions-dev"
echo -e "${YELLOW}Checking if Lambda function ${LAMBDA_NAME} exists...${NC}"
LAMBDA_INFO=$(aws lambda get-function --function-name ${LAMBDA_NAME} 2>/dev/null || echo "")

if [ -z "$LAMBDA_INFO" ]; then
  echo -e "${YELLOW}Lambda function ${LAMBDA_NAME} not found. Checking similar names...${NC}"
  
  # List all Lambda functions that might be related
  RELATED_LAMBDAS=$(aws lambda list-functions --query "Functions[?contains(FunctionName, 'db-') || contains(FunctionName, '-actions-') || contains(FunctionName, 'lambda-db')].FunctionName" --output text)
  
  if [ -n "$RELATED_LAMBDAS" ]; then
    echo -e "${YELLOW}Found potentially related Lambda functions:${NC}"
    echo "$RELATED_LAMBDAS"
    
    # Try to delete each related Lambda function
    for lambda in $RELATED_LAMBDAS; do
      echo -e "${YELLOW}Attempting to delete Lambda function: ${lambda}${NC}"
      aws lambda delete-function --function-name $lambda
      
      if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully deleted Lambda function ${lambda}${NC}"
      else
        echo -e "${RED}Failed to delete Lambda function ${lambda}${NC}"
      fi
    done
  else
    echo -e "${YELLOW}No related Lambda functions found.${NC}"
  fi
else
  echo -e "${YELLOW}Attempting to delete Lambda function ${LAMBDA_NAME}...${NC}"
  aws lambda delete-function --function-name ${LAMBDA_NAME}
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully deleted Lambda function ${LAMBDA_NAME}${NC}"
  else
    echo -e "${RED}Failed to delete Lambda function ${LAMBDA_NAME}${NC}"
  fi
fi

# Wait for a moment to allow AWS to clean up network interfaces
echo -e "${YELLOW}Waiting for AWS to clean up resources (30 seconds)...${NC}"
sleep 30

# Now try to delete the security group
echo -e "\n${YELLOW}Attempting to delete security group aurora-dev-sg...${NC}"
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=aurora-dev-sg" --query "SecurityGroups[0].GroupId" --output text)

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
  echo -e "${GREEN}Security group 'aurora-dev-sg' not found - likely already deleted.${NC}"
else
  aws ec2 delete-security-group --group-id $SG_ID

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully deleted security group ${SG_ID}${NC}"
  else
    echo -e "${RED}Failed to delete security group ${SG_ID}${NC}"
    echo -e "${YELLOW}Checking for remaining dependencies...${NC}"
    
    # Check if network interfaces still exist
    INTERFACES=$(aws ec2 describe-network-interfaces --filters "Name=group-id,Values=$SG_ID" --query "NetworkInterfaces[].NetworkInterfaceId" --output text)
    
    if [ -n "$INTERFACES" ]; then
      echo -e "${RED}Network interfaces still using this security group: ${INTERFACES}${NC}"
      echo -e "${YELLOW}This security group will need to be deleted manually from the AWS console after these resources are removed.${NC}"
    else
      echo -e "${YELLOW}No dependencies found. Try deleting again later or from the AWS console.${NC}"
    fi
  fi
fi

# Final verification
echo -e "\n${YELLOW}Performing final verification...${NC}"

# Check if security group still exists
SG_EXISTS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=aurora-dev-sg" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")

if [ -z "$SG_EXISTS" ] || [ "$SG_EXISTS" == "None" ]; then
  echo -e "${GREEN}✓ Security group 'aurora-dev-sg' has been successfully deleted!${NC}"
else
  echo -e "${RED}! Security group 'aurora-dev-sg' still exists with ID: ${SG_EXISTS}${NC}"
fi

# Check if any Lambda functions still exist
LAMBDAS=$(aws lambda list-functions --query "Functions[?contains(FunctionName, 'db-') || contains(FunctionName, 'cloudable')].FunctionName" --output text)

if [ -z "$LAMBDAS" ]; then
  echo -e "${GREEN}✓ No related Lambda functions found${NC}"
else
  echo -e "${RED}! Some related Lambda functions still exist: ${LAMBDAS}${NC}"
fi

exit 0
