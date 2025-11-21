#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLEANUP REMAINING AWS RESOURCES                ${NC}"
echo -e "${BLUE}==================================================${NC}"

# STEP 1: Delete CloudWatch Log Groups
echo -e "\n${YELLOW}STEP 1: Deleting CloudWatch Log Groups...${NC}"

# List of log groups to delete (excluding AWS system log groups)
LOG_GROUPS=$(aws logs describe-log-groups --query "logGroups[?!contains(logGroupName, 'aws-controltower')].logGroupName" --output text)

if [ -n "$LOG_GROUPS" ]; then
  echo -e "${YELLOW}Found the following log groups to delete:${NC}"
  echo "$LOG_GROUPS" | tr '\t' '\n'
  
  for log_group in $(echo "$LOG_GROUPS"); do
    echo -e "${YELLOW}Deleting log group: $log_group${NC}"
    aws logs delete-log-group --log-group-name "$log_group"
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✓ Successfully deleted log group: $log_group${NC}"
    else
      echo -e "${RED}Failed to delete log group: $log_group${NC}"
    fi
  done
else
  echo -e "${GREEN}No CloudWatch log groups to delete.${NC}"
fi

# STEP 2: Delete IAM Roles
echo -e "\n${YELLOW}STEP 2: Deleting IAM Roles...${NC}"

# List of IAM roles to delete related to the application
IAM_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'kb-') || contains(RoleName, 'cloudable')].RoleName" --output text)

if [ -n "$IAM_ROLES" ]; then
  echo -e "${YELLOW}Found the following IAM roles to delete:${NC}"
  echo "$IAM_ROLES" | tr '\t' '\n'
  
  for role in $(echo "$IAM_ROLES"); do
    echo -e "${YELLOW}Processing role: $role${NC}"
    
    # List and detach managed policies
    MANAGED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query "AttachedPolicies[*].PolicyArn" --output text)
    if [ -n "$MANAGED_POLICIES" ]; then
      for policy in $(echo "$MANAGED_POLICIES"); do
        echo -e "${YELLOW}Detaching managed policy: $policy${NC}"
        aws iam detach-role-policy --role-name "$role" --policy-arn "$policy"
      done
    fi
    
    # List and delete inline policies
    INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" --query "PolicyNames" --output text)
    if [ -n "$INLINE_POLICIES" ]; then
      for policy in $(echo "$INLINE_POLICIES"); do
        echo -e "${YELLOW}Deleting inline policy: $policy${NC}"
        aws iam delete-role-policy --role-name "$role" --policy-name "$policy"
      done
    fi
    
    # Delete the role
    echo -e "${YELLOW}Deleting role: $role${NC}"
    aws iam delete-role --role-name "$role"
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✓ Successfully deleted role: $role${NC}"
    else
      echo -e "${RED}Failed to delete role: $role${NC}"
    fi
  done
else
  echo -e "${GREEN}No IAM roles to delete.${NC}"
fi

# STEP 3: Delete API Gateway APIs
echo -e "\n${YELLOW}STEP 3: Deleting API Gateway APIs...${NC}"

# List of API Gateway APIs
API_IDS=$(aws apigateway get-rest-apis --query "items[*].id" --output text)

if [ -n "$API_IDS" ]; then
  echo -e "${YELLOW}Found the following API Gateway APIs to delete:${NC}"
  aws apigateway get-rest-apis --query "items[*].{ID:id,Name:name}" --output table
  
  for api_id in $(echo "$API_IDS"); do
    echo -e "${YELLOW}Deleting API: $api_id${NC}"
    aws apigateway delete-rest-api --rest-api-id "$api_id"
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✓ Successfully deleted API Gateway API: $api_id${NC}"
    else
      echo -e "${RED}Failed to delete API Gateway API: $api_id${NC}"
    fi
  done
else
  echo -e "${GREEN}No API Gateway APIs to delete.${NC}"
fi

# Wait for AWS to update resources
echo -e "\n${YELLOW}Waiting for AWS to update resource states (30 seconds)...${NC}"
sleep 30

# STEP 4: Delete Network Interfaces and Security Groups
echo -e "\n${YELLOW}STEP 4: Deleting Network Interfaces and Security Groups...${NC}"

# List of Lambda ENIs
LAMBDA_ENIS=$(aws ec2 describe-network-interfaces --filters "Name=description,Values=*Lambda*" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)

if [ -n "$LAMBDA_ENIS" ]; then
  echo -e "${YELLOW}Found the following Lambda network interfaces:${NC}"
  aws ec2 describe-network-interfaces --filters "Name=description,Values=*Lambda*" --query "NetworkInterfaces[*].{ID:NetworkInterfaceId,Description:Description,Status:Status}" --output table
  
  echo -e "${YELLOW}Lambda ENIs are typically managed by AWS and will be automatically deleted.${NC}"
  echo -e "${YELLOW}We'll try to force delete them, but this may not work immediately.${NC}"
  
  for eni in $(echo "$LAMBDA_ENIS"); do
    echo -e "${YELLOW}Attempting to delete network interface: $eni${NC}"
    
    # Try to force detach if attached
    ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --network-interface-ids "$eni" --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text 2>/dev/null)
    if [ "$ATTACHMENT_ID" != "None" ] && [ -n "$ATTACHMENT_ID" ]; then
      echo -e "${YELLOW}Attempting to detach: $ATTACHMENT_ID${NC}"
      aws ec2 detach-network-interface --attachment-id "$ATTACHMENT_ID" --force 2>/dev/null || true
    fi
    
    # Try to delete the ENI
    aws ec2 delete-network-interface --network-interface-id "$eni" 2>/dev/null
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✓ Successfully deleted network interface: $eni${NC}"
    else
      echo -e "${YELLOW}Could not delete network interface: $eni${NC}"
      echo -e "${YELLOW}This interface is likely still in use and will be automatically cleaned up by AWS.${NC}"
    fi
  done
else
  echo -e "${GREEN}No Lambda network interfaces found.${NC}"
fi

# List of security groups (excluding default)
SG_IDS=$(aws ec2 describe-security-groups --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)

if [ -n "$SG_IDS" ]; then
  echo -e "${YELLOW}Found the following security groups to delete:${NC}"
  aws ec2 describe-security-groups --query "SecurityGroups[?GroupName!='default'].{ID:GroupId,Name:GroupName,Description:Description}" --output table
  
  for sg in $(echo "$SG_IDS"); do
    echo -e "${YELLOW}Checking if security group $sg has dependencies...${NC}"
    DEPENDENCIES=$(aws ec2 describe-network-interfaces --filters "Name=group-id,Values=$sg" --query "NetworkInterfaces" --output text)
    
    if [ -z "$DEPENDENCIES" ]; then
      echo -e "${YELLOW}Deleting security group: $sg${NC}"
      aws ec2 delete-security-group --group-id "$sg"
      
      if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully deleted security group: $sg${NC}"
      else
        echo -e "${RED}Failed to delete security group: $sg${NC}"
      fi
    else
      echo -e "${YELLOW}Security group $sg still has dependencies and cannot be deleted yet.${NC}"
      echo -e "${YELLOW}It will be automatically deleted after the network interfaces are removed.${NC}"
    fi
  done
else
  echo -e "${GREEN}No non-default security groups found.${NC}"
fi

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}CLEANUP PROCESS COMPLETED${NC}"
echo -e "${BLUE}==================================================${NC}"

echo -e "${YELLOW}Note: Some network interfaces may still be in use by AWS services.${NC}"
echo -e "${YELLOW}These will typically be deleted automatically within 30-60 minutes.${NC}"
echo -e "${YELLOW}Security groups with dependencies will be deleted once those dependencies are removed.${NC}"
echo -e "\n${YELLOW}Run the verification script after 30-60 minutes to confirm all resources are removed:${NC}"
echo -e "${YELLOW}./verify_all_resources.sh${NC}"

exit 0
