#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   SECURITY GROUP FINAL CLEANUP                   ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Get security group ID for aurora-dev-sg
echo -e "\n${YELLOW}Finding security group ID for aurora-dev-sg...${NC}"
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=aurora-dev-sg" --query "SecurityGroups[0].GroupId" --output text)

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
  echo -e "${YELLOW}Security group 'aurora-dev-sg' not found.${NC}"
  exit 0
fi

echo -e "${GREEN}Found security group: ${SG_ID}${NC}"

# First, try to delete directly
echo -e "\n${YELLOW}Attempting to delete security group...${NC}"
aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Successfully deleted security group ${SG_ID}${NC}"
  exit 0
fi

echo -e "${YELLOW}Could not delete security group directly. It may have dependencies.${NC}"
echo -e "${YELLOW}Checking for inbound rules to remove...${NC}"

# Remove all inbound rules
RULES=$(aws ec2 describe-security-group-rules --filter "Name=group-id,Values=$SG_ID" --query "SecurityGroupRules[?IsEgress==\`false\`].SecurityGroupRuleId" --output text)

if [ -n "$RULES" ]; then
  echo -e "${YELLOW}Removing inbound rules...${NC}"
  for rule in $RULES; do
    echo -e "Removing rule $rule..."
    aws ec2 revoke-security-group-ingress --group-id "$SG_ID" --security-group-rule-ids "$rule"
  done
fi

echo -e "${YELLOW}Checking for outbound rules to remove...${NC}"

# Remove all outbound rules
RULES=$(aws ec2 describe-security-group-rules --filter "Name=group-id,Values=$SG_ID" --query "SecurityGroupRules[?IsEgress==\`true\`].SecurityGroupRuleId" --output text)

if [ -n "$RULES" ]; then
  echo -e "${YELLOW}Removing outbound rules...${NC}"
  for rule in $RULES; do
    echo -e "Removing rule $rule..."
    aws ec2 revoke-security-group-egress --group-id "$SG_ID" --security-group-rule-ids "$rule"
  done
fi

# Try to delete again
echo -e "\n${YELLOW}Attempting to delete security group again...${NC}"
aws ec2 delete-security-group --group-id "$SG_ID"

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Successfully deleted security group ${SG_ID}${NC}"
else
  echo -e "${RED}Could not delete security group. It may still have dependencies.${NC}"
  echo -e "${YELLOW}Looking for network interfaces attached to this security group...${NC}"
  
  # Check for network interfaces using this security group
  NI_IDS=$(aws ec2 describe-network-interfaces --filters "Name=group-id,Values=$SG_ID" --query "NetworkInterfaces[].NetworkInterfaceId" --output text)
  
  if [ -n "$NI_IDS" ]; then
    echo -e "${RED}Found network interfaces using this security group: ${NI_IDS}${NC}"
    echo -e "${YELLOW}These interfaces must be deleted before the security group can be removed.${NC}"
    echo -e "${YELLOW}Note: This may require deleting other resources that own these interfaces.${NC}"
    
    # Show details about these network interfaces
    for ni in $NI_IDS; do
      echo -e "${YELLOW}Details for network interface ${ni}:${NC}"
      aws ec2 describe-network-interfaces --network-interface-ids "$ni" --query "NetworkInterfaces[0].{Description:Description,Status:Status,InstanceId:Attachment.InstanceId,DeleteOnTermination:Attachment.DeleteOnTermination}" --output json
    done
  else
    echo -e "${YELLOW}No network interfaces found using this security group.${NC}"
    echo -e "${RED}The security group may be referenced by another resource.${NC}"
  fi
fi

# Final verification
echo -e "\n${YELLOW}Verifying if security group was deleted...${NC}"
SG_EXISTS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=aurora-dev-sg" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")

if [ -z "$SG_EXISTS" ] || [ "$SG_EXISTS" == "None" ]; then
  echo -e "${GREEN}✓ Security group 'aurora-dev-sg' has been successfully deleted!${NC}"
else
  echo -e "${RED}! Security group 'aurora-dev-sg' still exists with ID: ${SG_EXISTS}${NC}"
  echo -e "${YELLOW}You may need to investigate and remove it manually through the AWS Console.${NC}"
fi

exit 0
