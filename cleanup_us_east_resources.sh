#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   CLEANING UP US-EAST-1 RESOURCES               ${NC}"
echo -e "${BLUE}   KEEPING ALL RESOURCES IN EU-WEST-1 (IRELAND)  ${NC}"
echo -e "${BLUE}==================================================${NC}"

export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1

# 1. Delete API Gateway in us-east-1
echo -e "\n${YELLOW}Step 1: Deleting API Gateway in us-east-1...${NC}"
API_ID=$(aws apigatewayv2 get-apis --query "Items[?Name=='cloudable-kb-api-core'].ApiId" --output text 2>/dev/null)
if [ -n "$API_ID" ] && [ "$API_ID" != "None" ]; then
    echo -e "${YELLOW}Found API Gateway: $API_ID${NC}"
    aws apigatewayv2 delete-api --api-id "$API_ID" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Deleted API Gateway: $API_ID${NC}"
    else
        echo -e "${RED}✗ Failed to delete API Gateway: $API_ID${NC}"
    fi
else
    echo -e "${GREEN}✓ No API Gateway found in us-east-1${NC}"
fi

# 2. Delete Secrets Manager secret in us-east-1
echo -e "\n${YELLOW}Step 2: Deleting Secrets Manager secret in us-east-1...${NC}"
SECRET_ARN=$(aws secretsmanager list-secrets --query "SecretList[?Name=='aurora-dev-admin-secret'].ARN" --output text 2>/dev/null | grep "us-east-1" | head -1)
if [ -n "$SECRET_ARN" ] && [ "$SECRET_ARN" != "None" ]; then
    echo -e "${YELLOW}Found Secret: $SECRET_ARN${NC}"
    aws secretsmanager delete-secret --secret-id "$SECRET_ARN" --force-delete-without-recovery 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Deleted Secret: $SECRET_ARN${NC}"
    else
        echo -e "${RED}✗ Failed to delete Secret: $SECRET_ARN${NC}"
    fi
else
    echo -e "${GREEN}✓ No Secrets Manager secret found in us-east-1${NC}"
fi

# 3. Delete Security Groups in us-east-1
echo -e "\n${YELLOW}Step 3: Deleting Security Groups in us-east-1...${NC}"
SG_IDS=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=*aurora*" --query "SecurityGroups[*].GroupId" --output text 2>/dev/null)
if [ -n "$SG_IDS" ] && [ "$SG_IDS" != "None" ]; then
    for SG_ID in $SG_IDS; do
        echo -e "${YELLOW}Deleting Security Group: $SG_ID${NC}"
        aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Deleted Security Group: $SG_ID${NC}"
        else
            echo -e "${YELLOW}⚠ Security Group $SG_ID may have dependencies, skipping...${NC}"
        fi
    done
else
    echo -e "${GREEN}✓ No Security Groups found in us-east-1${NC}"
fi

# 4. Check for Lambda functions in us-east-1
echo -e "\n${YELLOW}Step 4: Checking for Lambda functions in us-east-1...${NC}"
LAMBDA_FUNCTIONS=$(aws lambda list-functions --query "Functions[?contains(FunctionName, 'kb-manager') || contains(FunctionName, 'cloudable')].FunctionName" --output text 2>/dev/null)
if [ -n "$LAMBDA_FUNCTIONS" ] && [ "$LAMBDA_FUNCTIONS" != "None" ]; then
    for FUNC_NAME in $LAMBDA_FUNCTIONS; do
        echo -e "${YELLOW}Deleting Lambda function: $FUNC_NAME${NC}"
        aws lambda delete-function --function-name "$FUNC_NAME" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Deleted Lambda function: $FUNC_NAME${NC}"
        else
            echo -e "${RED}✗ Failed to delete Lambda function: $FUNC_NAME${NC}"
        fi
    done
else
    echo -e "${GREEN}✓ No Lambda functions found in us-east-1${NC}"
fi

# 5. Check for RDS clusters in us-east-1
echo -e "\n${YELLOW}Step 5: Checking for RDS clusters in us-east-1...${NC}"
RDS_CLUSTERS=$(aws rds describe-db-clusters --query "DBClusters[*].DBClusterIdentifier" --output text 2>/dev/null)
if [ -n "$RDS_CLUSTERS" ] && [ "$RDS_CLUSTERS" != "None" ]; then
    for CLUSTER_ID in $RDS_CLUSTERS; do
        echo -e "${YELLOW}Found RDS cluster: $CLUSTER_ID${NC}"
        echo -e "${RED}WARNING: RDS cluster found in us-east-1. This requires manual deletion.${NC}"
        echo -e "${YELLOW}To delete, run: aws rds delete-db-cluster --db-cluster-identifier $CLUSTER_ID --skip-final-snapshot${NC}"
    done
else
    echo -e "${GREEN}✓ No RDS clusters found in us-east-1${NC}"
fi

# Note about IAM roles (they are global)
echo -e "\n${YELLOW}Note: IAM roles are global and shared across regions.${NC}"
echo -e "${YELLOW}The 'kb-manager-role-core' role will remain as it's used by Lambda in eu-west-1.${NC}"

echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${BLUE}==================================================${NC}"

echo -e "\n${YELLOW}Summary:${NC}"
echo -e "All us-east-1 resources have been cleaned up (or marked for cleanup)."
echo -e "All resources in eu-west-1 (Ireland) have been preserved."

exit 0
