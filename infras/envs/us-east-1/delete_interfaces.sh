#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   NETWORK INTERFACES & SECURITY GROUP CLEANUP    ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Define the interfaces to delete
INTERFACE_IDS="eni-0a750f128d4ec4c19 eni-0e8d3739a35243ec5"

# First try to detach the interfaces
for eni in $INTERFACE_IDS; do
    echo -e "${YELLOW}Attempting to detach interface ${eni}...${NC}"
    ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --network-interface-ids $eni --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text)
    
    if [ "$ATTACHMENT_ID" != "None" ] && [ -n "$ATTACHMENT_ID" ]; then
        echo -e "Found attachment: $ATTACHMENT_ID"
        aws ec2 detach-network-interface --attachment-id $ATTACHMENT_ID --force
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Successfully detached interface ${eni}${NC}"
            # Wait for the detachment to complete
            echo -e "${YELLOW}Waiting for detachment to complete...${NC}"
            sleep 10
        else
            echo -e "${RED}Failed to detach interface ${eni}${NC}"
        fi
    else
        echo -e "${YELLOW}No attachment found for ${eni}${NC}"
    fi
    
    # Now try to delete the interface
    echo -e "${YELLOW}Attempting to delete interface ${eni}...${NC}"
    aws ec2 delete-network-interface --network-interface-id $eni
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully deleted interface ${eni}${NC}"
    else
        echo -e "${RED}Failed to delete interface ${eni}${NC}"
        echo -e "${YELLOW}Checking interface status...${NC}"
        aws ec2 describe-network-interfaces --network-interface-ids $eni || echo "Interface not found - may have been deleted"
    fi
done

# Now try to delete the security group
echo -e "\n${YELLOW}Attempting to delete security group aurora-dev-sg...${NC}"
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=aurora-dev-sg" --query "SecurityGroups[0].GroupId" --output text)

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
  echo -e "${GREEN}Security group 'aurora-dev-sg' not found - likely already deleted.${NC}"
  exit 0
fi

aws ec2 delete-security-group --group-id $SG_ID

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully deleted security group ${SG_ID}${NC}"
else
    echo -e "${RED}Failed to delete security group ${SG_ID}${NC}"
    echo -e "${YELLOW}There may still be dependencies. Waiting a bit longer and trying again...${NC}"
    sleep 30
    
    # Try again after waiting
    aws ec2 delete-security-group --group-id $SG_ID
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully deleted security group on second attempt${NC}"
    else
        echo -e "${RED}Still unable to delete security group. You may need to delete it manually from the AWS console.${NC}"
    fi
fi

# Final verification
echo -e "\n${YELLOW}Performing final verification...${NC}"

# Check if any of our interfaces still exist
REMAINING_INTERFACES=""
for eni in $INTERFACE_IDS; do
    STATUS=$(aws ec2 describe-network-interfaces --network-interface-ids $eni --query "NetworkInterfaces[0].Status" --output text 2>/dev/null || echo "deleted")
    
    if [ "$STATUS" != "deleted" ] && [ "$STATUS" != "None" ]; then
        REMAINING_INTERFACES="${REMAINING_INTERFACES} ${eni}"
    fi
done

if [ -n "$REMAINING_INTERFACES" ]; then
    echo -e "${RED}Some network interfaces still exist: ${REMAINING_INTERFACES}${NC}"
else
    echo -e "${GREEN}✓ All network interfaces successfully deleted${NC}"
fi

# Check if security group still exists
SG_EXISTS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=aurora-dev-sg" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")

if [ -z "$SG_EXISTS" ] || [ "$SG_EXISTS" == "None" ]; then
  echo -e "${GREEN}✓ Security group 'aurora-dev-sg' has been successfully deleted!${NC}"
else
  echo -e "${RED}! Security group 'aurora-dev-sg' still exists with ID: ${SG_EXISTS}${NC}"
fi

exit 0
