#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   COMPREHENSIVE AWS RESOURCE VERIFICATION         ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Check for all Lambda functions
echo -e "\n${YELLOW}1. Checking all Lambda functions...${NC}"
LAMBDAS=$(aws lambda list-functions --query "Functions[*].FunctionName" --output text)

if [ -z "$LAMBDAS" ]; then
  echo -e "${GREEN}✓ No Lambda functions found${NC}"
else
  echo -e "${YELLOW}Found Lambda functions: ${NC}"
  aws lambda list-functions --query "Functions[*].{Name:FunctionName,Runtime:Runtime,MemorySize:MemorySize}" --output table
  
  # Filter out AWS system functions
  USER_LAMBDAS=$(echo "$LAMBDAS" | grep -v "aws-controltower")
  if [ -z "$USER_LAMBDAS" ]; then
    echo -e "${GREEN}✓ Only AWS system Lambda functions exist, no user functions found${NC}"
  else
    echo -e "${RED}! Found user Lambda functions: ${USER_LAMBDAS}${NC}"
  fi
fi

# Check for all ENIs that might be Lambda-related
echo -e "\n${YELLOW}2. Checking all network interfaces related to Lambda...${NC}"
LAMBDA_ENIS=$(aws ec2 describe-network-interfaces --filters "Name=description,Values=*Lambda*" --query "NetworkInterfaces[].{ID:NetworkInterfaceId,Description:Description,Status:Status}" --output table)

if [ -z "$LAMBDA_ENIS" ] || [ "$LAMBDA_ENIS" == "None" ]; then
  echo -e "${GREEN}✓ No Lambda-related network interfaces found${NC}"
else
  echo -e "${YELLOW}Found Lambda-related network interfaces: ${NC}"
  echo "$LAMBDA_ENIS"
fi

# Check for all security groups
echo -e "\n${YELLOW}3. Checking all security groups...${NC}"
SG_COUNT=$(aws ec2 describe-security-groups --query "length(SecurityGroups)" --output text)
DEFAULT_SG_COUNT=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=default" --query "length(SecurityGroups)" --output text)

if [ "$SG_COUNT" -eq "$DEFAULT_SG_COUNT" ]; then
  echo -e "${GREEN}✓ Only default security groups found (${DEFAULT_SG_COUNT})${NC}"
else
  echo -e "${YELLOW}Found ${SG_COUNT} security groups (including ${DEFAULT_SG_COUNT} default groups): ${NC}"
  aws ec2 describe-security-groups --query "SecurityGroups[*].{ID:GroupId,Name:GroupName,Description:Description}" --output table
  
  # Check for non-default security groups
  echo -e "\n${YELLOW}Non-default security groups:${NC}"
  aws ec2 describe-security-groups --query "SecurityGroups[?GroupName!='default'].{ID:GroupId,Name:GroupName,VpcId:VpcId}" --output table
fi

# Check for all RDS instances and clusters
echo -e "\n${YELLOW}4. Checking all RDS resources...${NC}"
RDS_INSTANCES=$(aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier" --output text 2>/dev/null || echo "")
RDS_CLUSTERS=$(aws rds describe-db-clusters --query "DBClusters[*].DBClusterIdentifier" --output text 2>/dev/null || echo "")

if [ -z "$RDS_INSTANCES" ] && [ -z "$RDS_CLUSTERS" ]; then
  echo -e "${GREEN}✓ No RDS resources found${NC}"
else
  [ -n "$RDS_INSTANCES" ] && echo -e "${RED}! Found RDS instances: ${RDS_INSTANCES}${NC}"
  [ -n "$RDS_CLUSTERS" ] && echo -e "${RED}! Found RDS clusters: ${RDS_CLUSTERS}${NC}"
fi

# Check for all S3 buckets
echo -e "\n${YELLOW}5. Checking all S3 buckets...${NC}"
S3_BUCKETS=$(aws s3api list-buckets --query "Buckets[*].Name" --output text)

if [ -z "$S3_BUCKETS" ]; then
  echo -e "${GREEN}✓ No S3 buckets found${NC}"
else
  echo -e "${YELLOW}Found S3 buckets:${NC}"
  echo "$S3_BUCKETS" | tr '\t' '\n'
  
  # Check if any of them seem related to your application
  APP_BUCKETS=$(echo "$S3_BUCKETS" | grep -E "cloudable|kb-|aurora")
  if [ -z "$APP_BUCKETS" ]; then
    echo -e "${GREEN}✓ No S3 buckets related to your application found${NC}"
  else
    echo -e "${RED}! Found S3 buckets potentially related to your application: ${APP_BUCKETS}${NC}"
  fi
fi

# Check for all CloudWatch log groups
echo -e "\n${YELLOW}6. Checking all CloudWatch log groups...${NC}"
CW_LOGS=$(aws logs describe-log-groups --query "logGroups[*].logGroupName" --output text)

if [ -z "$CW_LOGS" ]; then
  echo -e "${GREEN}✓ No CloudWatch log groups found${NC}"
else
  echo -e "${YELLOW}Found CloudWatch log groups:${NC}"
  echo "$CW_LOGS" | tr '\t' '\n'
  
  # Check for application-related log groups
  APP_LOGS=$(echo "$CW_LOGS" | grep -E "cloudable|kb-|aurora|lambda")
  if [ -z "$APP_LOGS" ]; then
    echo -e "${GREEN}✓ No CloudWatch log groups related to your application found${NC}"
  else
    echo -e "${RED}! Found CloudWatch log groups potentially related to your application: ${APP_LOGS}${NC}"
  fi
fi

# Check for IAM roles
echo -e "\n${YELLOW}7. Checking for IAM roles related to your application...${NC}"
IAM_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'cloudable') || contains(RoleName, 'kb-') || contains(RoleName, 'aurora') || contains(RoleName, 'lambda')].RoleName" --output text)

if [ -z "$IAM_ROLES" ]; then
  echo -e "${GREEN}✓ No IAM roles related to your application found${NC}"
else
  echo -e "${RED}! Found IAM roles potentially related to your application: ${IAM_ROLES}${NC}"
fi

# Check for Bedrock resources
echo -e "\n${YELLOW}8. Checking for Bedrock resources...${NC}"
BEDROCK_KBS=$(aws bedrock list-knowledge-bases --query "knowledgeBases[*].name" --output text 2>/dev/null || echo "")

if [ -z "$BEDROCK_KBS" ]; then
  echo -e "${GREEN}✓ No Bedrock knowledge bases found${NC}"
else
  echo -e "${RED}! Found Bedrock knowledge bases: ${BEDROCK_KBS}${NC}"
fi

# Check for API Gateway APIs
echo -e "\n${YELLOW}9. Checking for API Gateway APIs...${NC}"
API_GATEWAY=$(aws apigateway get-rest-apis --query "items[*].{Name:name,ID:id}" --output table 2>/dev/null || echo "")

if [ -z "$API_GATEWAY" ] || [ "$API_GATEWAY" == "[]" ]; then
  echo -e "${GREEN}✓ No API Gateway APIs found${NC}"
else
  echo -e "${YELLOW}Found API Gateway APIs:${NC}"
  echo "$API_GATEWAY"
fi

# Summary
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${BLUE}                  SUMMARY                         ${NC}"
echo -e "${BLUE}==================================================${NC}"

ISSUES=0
[ -n "$USER_LAMBDAS" ] && ISSUES=$((ISSUES+1))
[ -n "$LAMBDA_ENIS" ] && [ "$LAMBDA_ENIS" != "None" ] && ISSUES=$((ISSUES+1))
[ "$SG_COUNT" -ne "$DEFAULT_SG_COUNT" ] && ISSUES=$((ISSUES+1))
[ -n "$RDS_INSTANCES" ] || [ -n "$RDS_CLUSTERS" ] && ISSUES=$((ISSUES+1))
[ -n "$APP_BUCKETS" ] && ISSUES=$((ISSUES+1))
[ -n "$APP_LOGS" ] && ISSUES=$((ISSUES+1))
[ -n "$IAM_ROLES" ] && ISSUES=$((ISSUES+1))
[ -n "$BEDROCK_KBS" ] && ISSUES=$((ISSUES+1))
[ -n "$API_GATEWAY" ] && [ "$API_GATEWAY" != "[]" ] && ISSUES=$((ISSUES+1))

if [ $ISSUES -eq 0 ]; then
  echo -e "${GREEN}✓✓✓ ALL CLOUDABLE.AI RESOURCES HAVE BEEN SUCCESSFULLY REMOVED! ✓✓✓${NC}"
  echo -e "${GREEN}The AWS environment is clean and ready for a fresh deployment.${NC}"
else
  echo -e "${YELLOW}Found ${ISSUES} potential issues that may need attention.${NC}"
  echo -e "${YELLOW}Review the details above for resources that may need manual cleanup.${NC}"
  echo -e "${YELLOW}Note: Some resources like Lambda ENIs may automatically be deleted by AWS after some time.${NC}"
fi

exit 0
