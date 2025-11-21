#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}  SEQUENTIAL CLEANUP: LAMBDAS → ENIs → SGs         ${NC}"
echo -e "${BLUE}==================================================${NC}"

# STEP 1: Find and delete all Lambda functions
echo -e "\n${YELLOW}STEP 1: Finding all Lambda functions related to the application...${NC}"
LAMBDA_FUNCTIONS=$(aws lambda list-functions --output json | jq -r '.Functions[].FunctionName' | grep -E 'cloudable|kb-|db-|aurora')

if [ -n "$LAMBDA_FUNCTIONS" ]; then
  echo -e "${YELLOW}Found the following Lambda functions:${NC}"
  echo "$LAMBDA_FUNCTIONS"
  
  echo -e "\n${YELLOW}Deleting all Lambda functions...${NC}"
  for func in $LAMBDA_FUNCTIONS; do
    echo -e "${YELLOW}Deleting Lambda function: $func${NC}"
    aws lambda delete-function --function-name "$func"
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✓ Successfully deleted Lambda function: $func${NC}"
    else
      echo -e "${RED}Failed to delete Lambda function: $func${NC}"
    fi
  done
else
  echo -e "${GREEN}No Lambda functions found.${NC}"
fi

# STEP 2: Wait for Lambda ENIs to be cleaned up
echo -e "\n${YELLOW}STEP 2: Waiting for Lambda network interfaces to be released (120 seconds)...${NC}"
sleep 120

# STEP 3: Find and force detach/delete ENIs
echo -e "\n${YELLOW}STEP 3: Finding and deleting network interfaces...${NC}"
ENI_IDS=$(aws ec2 describe-network-interfaces --filters "Name=description,Values=*Lambda*ENI*" --query "NetworkInterfaces[].NetworkInterfaceId" --output text)

if [ -n "$ENI_IDS" ]; then
  echo -e "${YELLOW}Found network interfaces: $ENI_IDS${NC}"
  
  for eni in $ENI_IDS; do
    # Try to force detach if attached
    ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --network-interface-ids $eni --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text)
    if [ "$ATTACHMENT_ID" != "None" ] && [ -n "$ATTACHMENT_ID" ]; then
      echo -e "${YELLOW}Force detaching $eni (attachment: $ATTACHMENT_ID)...${NC}"
      aws ec2 detach-network-interface --attachment-id $ATTACHMENT_ID --force || true
      echo -e "${YELLOW}Waiting 30 seconds for detachment to complete...${NC}"
      sleep 30
    fi
    
    # Try to delete the ENI
    echo -e "${YELLOW}Deleting network interface: $eni${NC}"
    aws ec2 delete-network-interface --network-interface-id $eni
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✓ Successfully deleted network interface: $eni${NC}"
    else
      echo -e "${RED}Failed to delete network interface: $eni${NC}"
    fi
  done
else
  echo -e "${GREEN}No Lambda network interfaces found.${NC}"
fi

# STEP 4: Find and delete security groups
echo -e "\n${YELLOW}STEP 4: Finding and deleting security groups...${NC}"
SG_IDS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=*aurora*,*lambda*,*cloudable*" --query "SecurityGroups[].GroupId" --output text)

if [ -n "$SG_IDS" ]; then
  echo -e "${YELLOW}Found security groups: $SG_IDS${NC}"
  
  for sg in $SG_IDS; do
    echo -e "${YELLOW}Checking if security group $sg has dependencies...${NC}"
    DEPENDENCIES=$(aws ec2 describe-network-interfaces --filters "Name=group-id,Values=$sg" --query "NetworkInterfaces" --output text)
    
    if [ -z "$DEPENDENCIES" ]; then
      echo -e "${YELLOW}Deleting security group: $sg${NC}"
      aws ec2 delete-security-group --group-id $sg
      if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully deleted security group: $sg${NC}"
      else
        echo -e "${RED}Failed to delete security group: $sg${NC}"
      fi
    else
      echo -e "${RED}Security group $sg still has dependencies and cannot be deleted yet.${NC}"
    fi
  done
else
  echo -e "${GREEN}No matching security groups found.${NC}"
fi

# STEP 5: Verify everything is gone
echo -e "\n${YELLOW}STEP 5: Verifying resources are deleted...${NC}"

# Check for Lambda functions
REMAINING_LAMBDAS=$(aws lambda list-functions --output json | jq -r '.Functions[].FunctionName' | grep -E 'cloudable|kb-|db-|aurora')
if [ -z "$REMAINING_LAMBDAS" ]; then
  echo -e "${GREEN}✓ All Lambda functions successfully deleted.${NC}"
else
  echo -e "${RED}! Some Lambda functions remain: $REMAINING_LAMBDAS${NC}"
fi

# Check for ENIs
REMAINING_ENIS=$(aws ec2 describe-network-interfaces --filters "Name=description,Values=*Lambda*ENI*" --query "NetworkInterfaces[].NetworkInterfaceId" --output text)
if [ -z "$REMAINING_ENIS" ]; then
  echo -e "${GREEN}✓ All Lambda network interfaces successfully deleted.${NC}"
else
  echo -e "${RED}! Some network interfaces remain: $REMAINING_ENIS${NC}"
fi

# Check for security groups
REMAINING_SGS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=*aurora*,*lambda*,*cloudable*" --query "SecurityGroups[].GroupId" --output text)
if [ -z "$REMAINING_SGS" ]; then
  echo -e "${GREEN}✓ All security groups successfully deleted.${NC}"
else
  echo -e "${RED}! Some security groups remain: $REMAINING_SGS${NC}"
fi

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}CLEANUP PROCESS COMPLETED${NC}"
echo -e "${BLUE}==================================================${NC}"

exit 0
