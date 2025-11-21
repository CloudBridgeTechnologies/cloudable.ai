#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   FINAL CLEANUP AND VERIFICATION                 ${NC}"
echo -e "${BLUE}==================================================${NC}"

echo -e "${YELLOW}Waiting for AWS to clean up Lambda resources (this may take a few minutes)...${NC}"

# Perform multiple attempts to delete the security group with waiting periods
MAX_ATTEMPTS=5
ATTEMPT=1

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    echo -e "\n${YELLOW}Attempt $ATTEMPT of $MAX_ATTEMPTS: Checking for network interfaces...${NC}"
    
    # Check if network interfaces still exist
    INTERFACES=$(aws ec2 describe-network-interfaces --filters "Name=description,Values=*Lambda*VPC*ENI*db-actions*" --query "NetworkInterfaces[].NetworkInterfaceId" --output text)
    
    if [ -z "$INTERFACES" ]; then
        echo -e "${GREEN}No Lambda network interfaces found. Proceeding to delete security group.${NC}"
        
        # Try to delete security group
        SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=aurora-dev-sg" --query "SecurityGroups[0].GroupId" --output text)
        
        if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
            echo -e "${GREEN}Security group 'aurora-dev-sg' not found - already deleted.${NC}"
            break
        else
            echo -e "${YELLOW}Attempting to delete security group ${SG_ID}...${NC}"
            aws ec2 delete-security-group --group-id $SG_ID
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Successfully deleted security group ${SG_ID}${NC}"
                break
            else
                echo -e "${RED}Failed to delete security group. Will try again after waiting.${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}Network interfaces still exist: ${INTERFACES}${NC}"
        echo -e "${YELLOW}These interfaces should be automatically deleted by AWS soon.${NC}"
    fi
    
    # Wait longer with each attempt
    WAIT_TIME=$((30 + ATTEMPT * 30))
    echo -e "${YELLOW}Waiting ${WAIT_TIME} seconds before next attempt...${NC}"
    sleep $WAIT_TIME
    
    ATTEMPT=$((ATTEMPT + 1))
done

# Final comprehensive verification
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${BLUE}   COMPREHENSIVE VERIFICATION                     ${NC}"
echo -e "${BLUE}==================================================${NC}"

# 1. Check for S3 buckets
echo -e "\n${YELLOW}1. Checking for remaining S3 buckets...${NC}"
BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'cloudable')].Name" --output text)

if [ -z "$BUCKETS" ]; then
  echo -e "${GREEN}✓ No S3 buckets with 'cloudable' found${NC}"
else
  echo -e "${RED}! Found S3 buckets: ${BUCKETS}${NC}"
fi

# 2. Check for Lambda functions
echo -e "\n${YELLOW}2. Checking for remaining Lambda functions...${NC}"
LAMBDAS=$(aws lambda list-functions --query "Functions[?contains(FunctionName, 'kb') || contains(FunctionName, 'cloudable') || contains(FunctionName, 'db-') || contains(FunctionName, 'aurora')].FunctionName" --output text)

if [ -z "$LAMBDAS" ]; then
  echo -e "${GREEN}✓ No Lambda functions found${NC}"
else
  echo -e "${RED}! Found Lambda functions: ${LAMBDAS}${NC}"
fi

# 3. Check for RDS instances and clusters
echo -e "\n${YELLOW}3. Checking for remaining RDS resources...${NC}"
INSTANCES=$(aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, 'aurora') || contains(DBInstanceIdentifier, 'cloudable')].DBInstanceIdentifier" --output text)
CLUSTERS=$(aws rds describe-db-clusters --query "DBClusters[?contains(DBClusterIdentifier, 'aurora') || contains(DBClusterIdentifier, 'cloudable')].DBClusterIdentifier" --output text)

if [ -z "$INSTANCES" ] && [ -z "$CLUSTERS" ]; then
  echo -e "${GREEN}✓ No RDS resources found${NC}"
else
  [ -n "$INSTANCES" ] && echo -e "${RED}! Found RDS instances: ${INSTANCES}${NC}"
  [ -n "$CLUSTERS" ] && echo -e "${RED}! Found RDS clusters: ${CLUSTERS}${NC}"
fi

# 4. Check for CloudWatch log groups
echo -e "\n${YELLOW}4. Checking for remaining CloudWatch logs...${NC}"
LOG_GROUPS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '/aws/lambda/') || contains(logGroupName, 'cloudable')].logGroupName" --output text)

if [ -z "$LOG_GROUPS" ]; then
  echo -e "${GREEN}✓ No CloudWatch log groups found${NC}"
else
  echo -e "${RED}! Found CloudWatch log groups: ${LOG_GROUPS}${NC}"
fi

# 5. Check for IAM roles
echo -e "\n${YELLOW}5. Checking for remaining IAM roles...${NC}"
IAM_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'cloudable') || contains(RoleName, 'kb-') || contains(RoleName, 'aurora')].RoleName" --output text)

if [ -z "$IAM_ROLES" ]; then
  echo -e "${GREEN}✓ No related IAM roles found${NC}"
else
  echo -e "${RED}! Found IAM roles: ${IAM_ROLES}${NC}"
fi

# 6. Check for Security Groups
echo -e "\n${YELLOW}6. Checking for remaining security groups...${NC}"
SG_EXISTS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=aurora-dev-sg" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")
OTHER_SG=$(aws ec2 describe-security-groups --query "SecurityGroups[?contains(GroupName, 'cloudable') || contains(GroupName, 'aurora') || contains(GroupName, 'lambda')].GroupName" --output text)

if [ -z "$SG_EXISTS" ] && [ -z "$OTHER_SG" ]; then
  echo -e "${GREEN}✓ No related security groups found${NC}"
else
  [ -n "$SG_EXISTS" ] && echo -e "${RED}! Security group 'aurora-dev-sg' still exists: ${SG_EXISTS}${NC}"
  [ -n "$OTHER_SG" ] && echo -e "${RED}! Found other related security groups: ${OTHER_SG}${NC}"
fi

# 7. Check for network interfaces
echo -e "\n${YELLOW}7. Checking for Lambda network interfaces...${NC}"
INTERFACES=$(aws ec2 describe-network-interfaces --filters "Name=description,Values=*Lambda*VPC*ENI*" --query "NetworkInterfaces[].{ID:NetworkInterfaceId,Description:Description}" --output text)

if [ -z "$INTERFACES" ]; then
  echo -e "${GREEN}✓ No Lambda network interfaces found${NC}"
else
  echo -e "${RED}! Found Lambda network interfaces: ${INTERFACES}${NC}"
  echo -e "${YELLOW}These interfaces may be in the process of being deleted by AWS.${NC}"
fi

# Summary
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}CLEANUP VERIFICATION COMPLETE${NC}"
echo -e "${BLUE}==================================================${NC}"

# Check if we have any remaining resources
if [ -z "$BUCKETS" ] && [ -z "$LAMBDAS" ] && [ -z "$INSTANCES" ] && [ -z "$CLUSTERS" ] && \
   [ -z "$LOG_GROUPS" ] && [ -z "$IAM_ROLES" ] && [ -z "$SG_EXISTS" ] && [ -z "$OTHER_SG" ] && [ -z "$INTERFACES" ]; then
  echo -e "${GREEN}✓✓✓ ALL CLOUDABLE.AI RESOURCES HAVE BEEN SUCCESSFULLY REMOVED! ✓✓✓${NC}"
  echo -e "${GREEN}The AWS environment is now clean and ready for a fresh deployment.${NC}"
else
  echo -e "${YELLOW}Some resources still exist or are in the process of being deleted.${NC}"
  echo -e "${YELLOW}For some resources like network interfaces, AWS may take some time to clean them up automatically.${NC}"
  echo -e "${YELLOW}You may need to wait a bit longer or perform manual cleanup for any remaining resources.${NC}"
fi

exit 0
