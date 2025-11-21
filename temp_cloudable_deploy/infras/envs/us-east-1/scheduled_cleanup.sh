#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   SCHEDULED CLEANUP AND VERIFICATION             ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Function to run verification and cleanup
run_verification_cleanup() {
  echo -e "\n${YELLOW}$(date) - Running verification script...${NC}"
  $SCRIPT_DIR/verify_all_resources.sh
  
  # Check if there are still resources to clean up
  NEED_CLEANUP=false
  
  # Check for network interfaces
  ENIS=$(aws ec2 describe-network-interfaces --filters "Name=description,Values=*Lambda*ENI*" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
  if [ -n "$ENIS" ]; then
    NEED_CLEANUP=true
  fi
  
  # Check for security groups (excluding default)
  SGS=$(aws ec2 describe-security-groups --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
  if [ -n "$SGS" ]; then
    NEED_CLEANUP=true
  fi
  
  # If resources still exist, run the cleanup script
  if [ "$NEED_CLEANUP" = true ]; then
    echo -e "\n${YELLOW}Resources still exist. Running cleanup script...${NC}"
    $SCRIPT_DIR/cleanup_remaining.sh
    return 1
  else
    echo -e "\n${GREEN}✓✓✓ All resources have been cleaned up! ✓✓✓${NC}"
    return 0
  fi
}

# Main loop for scheduled cleanup
cleanup_loop() {
  local max_attempts=$1
  local wait_time=$2
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    echo -e "\n${BLUE}==================================================${NC}"
    echo -e "${YELLOW}Cleanup Attempt $attempt of $max_attempts${NC}"
    echo -e "${BLUE}==================================================${NC}"
    
    run_verification_cleanup
    
    if [ $? -eq 0 ]; then
      echo -e "\n${GREEN}All resources successfully cleaned up on attempt $attempt!${NC}"
      break
    fi
    
    if [ $attempt -lt $max_attempts ]; then
      echo -e "\n${YELLOW}Waiting $wait_time minutes before next attempt...${NC}"
      local wait_seconds=$((wait_time * 60))
      
      # Show countdown timer
      for ((i=wait_seconds; i>=0; i--)); do
        mins=$((i / 60))
        secs=$((i % 60))
        printf "\r${YELLOW}Next cleanup attempt in: %02d:%02d${NC}" $mins $secs
        sleep 1
      done
      echo -e "\n"
    fi
    
    attempt=$((attempt+1))
  done
  
  if [ $attempt -gt $max_attempts ] && [ "$NEED_CLEANUP" = true ]; then
    echo -e "\n${RED}Warning: Maximum attempts reached. Some resources may still exist.${NC}"
    echo -e "${YELLOW}You might need to manually remove them through the AWS console.${NC}"
  fi
}

# Schedule the cleanup to run every 10 minutes, up to 6 times (covering 60 minutes)
echo -e "${YELLOW}Starting scheduled cleanup process...${NC}"
echo -e "${YELLOW}Will check and attempt cleanup every 10 minutes, up to 6 times.${NC}"
echo -e "${YELLOW}Press Ctrl+C to cancel at any time.${NC}\n"

cleanup_loop 6 10

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}SCHEDULED CLEANUP PROCESS COMPLETED${NC}"
echo -e "${BLUE}==================================================${NC}"

exit 0
