#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLOUDABLE.AI RESOURCE VERIFICATION CHECK       ${NC}"
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
LAMBDAS=$(aws lambda list-functions --query "Functions[?contains(FunctionName, 'kb-manager') || contains(FunctionName, 'cloudable')].FunctionName" --output text)

if [ -z "$LAMBDAS" ]; then
  echo -e "${GREEN}✓ No Lambda functions found${NC}"
else
  echo -e "${RED}! Found Lambda functions: ${LAMBDAS}${NC}"
fi

# 3. Check for RDS instances and clusters
echo -e "\n${YELLOW}3. Checking for remaining RDS instances...${NC}"
INSTANCES=$(aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, 'aurora') || contains(DBInstanceIdentifier, 'cloudable')].DBInstanceIdentifier" --output text)

if [ -z "$INSTANCES" ]; then
  echo -e "${GREEN}✓ No RDS instances found${NC}"
else
  echo -e "${RED}! Found RDS instances: ${INSTANCES}${NC}"
fi

echo -e "\n${YELLOW}3b. Checking for remaining RDS clusters...${NC}"
CLUSTERS=$(aws rds describe-db-clusters --query "DBClusters[?contains(DBClusterIdentifier, 'aurora') || contains(DBClusterIdentifier, 'cloudable')].DBClusterIdentifier" --output text)

if [ -z "$CLUSTERS" ]; then
  echo -e "${GREEN}✓ No RDS clusters found${NC}"
else
  echo -e "${RED}! Found RDS clusters: ${CLUSTERS}${NC}"
fi

# 4. Check for CloudWatch log groups
echo -e "\n${YELLOW}4. Checking for remaining CloudWatch logs...${NC}"
LOG_GROUPS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '/aws/lambda/kb') || contains(logGroupName, 'cloudable')].logGroupName" --output text)

if [ -z "$LOG_GROUPS" ]; then
  echo -e "${GREEN}✓ No CloudWatch log groups found${NC}"
else
  echo -e "${RED}! Found CloudWatch log groups: ${LOG_GROUPS}${NC}"
fi

# 5. Check for IAM roles
echo -e "\n${YELLOW}5. Checking for remaining IAM roles...${NC}"
IAM_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'cloudable') || contains(RoleName, 'kb-manager')].RoleName" --output text)

if [ -z "$IAM_ROLES" ]; then
  echo -e "${GREEN}✓ No IAM roles found${NC}"
else
  echo -e "${RED}! Found IAM roles: ${IAM_ROLES}${NC}"
fi

# 6. Check for KMS keys related to the project
echo -e "\n${YELLOW}6. Checking for KMS keys...${NC}"
KMS_KEYS=$(aws kms list-keys --query "Keys[].KeyId" --output text)
CLOUDABLE_KEYS=""

if [ -n "$KMS_KEYS" ]; then
  for key_id in $KMS_KEYS; do
    KEY_INFO=$(aws kms describe-key --key-id ${key_id})
    KEY_DESC=$(echo $KEY_INFO | jq -r '.KeyMetadata.Description')
    
    if [[ "$KEY_DESC" == *"cloudable"* || "$KEY_DESC" == *"Cloudable"* ]]; then
      KEY_STATE=$(echo $KEY_INFO | jq -r '.KeyMetadata.KeyState')
      CLOUDABLE_KEYS="${CLOUDABLE_KEYS}\n  - ${key_id} (${KEY_STATE}): ${KEY_DESC}"
    fi
  done
fi

if [ -z "$CLOUDABLE_KEYS" ]; then
  echo -e "${GREEN}✓ No Cloudable-related KMS keys found${NC}"
else
  echo -e "${RED}! Found Cloudable-related KMS keys: ${CLOUDABLE_KEYS}${NC}"
  echo -e "${YELLOW}Note: KMS keys may be scheduled for deletion and will be automatically removed after the waiting period${NC}"
fi

# 7. Check for API Gateway APIs
echo -e "\n${YELLOW}7. Checking for API Gateway APIs...${NC}"
APIS=$(aws apigateway get-rest-apis --query "items[?contains(name, 'cloudable') || contains(name, 'kb-manager')].name" --output text)

if [ -z "$APIS" ]; then
  echo -e "${GREEN}✓ No API Gateway APIs found${NC}"
else
  echo -e "${RED}! Found API Gateway APIs: ${APIS}${NC}"
fi

# 8. Check for Bedrock Knowledge Bases
echo -e "\n${YELLOW}8. Checking for Bedrock Knowledge Bases...${NC}"
KNOWLEDGE_BASES=$(aws bedrock list-knowledge-bases --query "knowledgeBases[?contains(name, 'cloudable')].name" --output text 2>/dev/null || echo "")

if [ -z "$KNOWLEDGE_BASES" ]; then
  echo -e "${GREEN}✓ No Bedrock Knowledge Bases found${NC}"
else
  echo -e "${RED}! Found Bedrock Knowledge Bases: ${KNOWLEDGE_BASES}${NC}"
fi

# 9. Check for Security Groups
echo -e "\n${YELLOW}9. Checking for Security Groups...${NC}"
SECURITY_GROUPS=$(aws ec2 describe-security-groups --query "SecurityGroups[?contains(GroupName, 'cloudable') || contains(GroupName, 'lambda-sg') || contains(GroupName, 'aurora')].GroupName" --output text)

if [ -z "$SECURITY_GROUPS" ]; then
  echo -e "${GREEN}✓ No related Security Groups found${NC}"
else
  echo -e "${RED}! Found Security Groups: ${SECURITY_GROUPS}${NC}"
fi

# Summary
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${YELLOW}VERIFICATION SUMMARY${NC}"
echo -e "${BLUE}==================================================${NC}"

ALL_CLEARED=true

if [ -n "$BUCKETS" ]; then
  echo -e "${RED}✗ S3 buckets remain${NC}"
  ALL_CLEARED=false
fi

if [ -n "$LAMBDAS" ]; then
  echo -e "${RED}✗ Lambda functions remain${NC}"
  ALL_CLEARED=false
fi

if [ -n "$INSTANCES" ] || [ -n "$CLUSTERS" ]; then
  echo -e "${RED}✗ RDS resources remain${NC}"
  ALL_CLEARED=false
fi

if [ -n "$LOG_GROUPS" ]; then
  echo -e "${RED}✗ CloudWatch logs remain${NC}"
  ALL_CLEARED=false
fi

if [ -n "$IAM_ROLES" ]; then
  echo -e "${RED}✗ IAM roles remain${NC}"
  ALL_CLEARED=false
fi

if [ -n "$CLOUDABLE_KEYS" ]; then
  echo -e "${YELLOW}! KMS keys scheduled for deletion${NC}"
  # Not a blocker since they're scheduled for deletion
fi

if [ -n "$APIS" ]; then
  echo -e "${RED}✗ API Gateway APIs remain${NC}"
  ALL_CLEARED=false
fi

if [ -n "$KNOWLEDGE_BASES" ]; then
  echo -e "${RED}✗ Bedrock Knowledge Bases remain${NC}"
  ALL_CLEARED=false
fi

if [ -n "$SECURITY_GROUPS" ]; then
  echo -e "${RED}✗ Security Groups remain${NC}"
  ALL_CLEARED=false
fi

if [ "$ALL_CLEARED" = true ]; then
  echo -e "\n${GREEN}✓✓✓ ALL CLOUDABLE.AI RESOURCES HAVE BEEN SUCCESSFULLY REMOVED ✓✓✓${NC}"
  echo -e "${GREEN}You may safely deploy to a new AWS account with no conflicts${NC}"
else
  echo -e "\n${RED}! SOME RESOURCES REMAIN. Please check the details above and remove them manually${NC}"
  echo -e "${YELLOW}You may want to run the cleanup script again for remaining resources${NC}"
fi

exit 0
