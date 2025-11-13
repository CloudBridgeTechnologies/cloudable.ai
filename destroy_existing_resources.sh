#!/bin/bash
# Script to destroy existing AWS resources that conflict with our deployment
set -e

# Color configuration
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ENV=${1:-dev}
REGION=${2:-us-east-1}

echo -e "${BLUE}=== Cloudable.AI Resource Cleanup Script ===${NC}"
echo -e "Environment: ${GREEN}$ENV${NC}"
echo -e "Region: ${GREEN}$REGION${NC}"

# Get AWS account ID
echo -e "${BLUE}Getting AWS account ID...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "AWS Account ID: ${GREEN}$AWS_ACCOUNT_ID${NC}"

# Function to check if resource exists and delete it
delete_if_exists() {
  RESOURCE_TYPE=$1
  RESOURCE_ID=$2
  DELETE_CMD=$3
  
  echo -e "${BLUE}Checking if $RESOURCE_TYPE '$RESOURCE_ID' exists...${NC}"
  
  if [ "$RESOURCE_TYPE" == "CloudWatch Log Group" ]; then
    aws logs describe-log-groups --log-group-name-prefix "$RESOURCE_ID" --query "logGroups[?logGroupName=='$RESOURCE_ID'].logGroupName" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "WAFv2 Web ACL" ]; then
    aws wafv2 list-web-acls --scope REGIONAL --query "WebACLs[?Name=='$RESOURCE_ID'].Name" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "Bedrock Agent" ]; then
    aws bedrock-agent list-agents --query "agentSummaries[?agentName=='$RESOURCE_ID'].agentName" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "Bedrock Guardrail" ]; then
    aws bedrock list-guardrails --query "guardrails[?name=='$RESOURCE_ID'].name" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "OpenSearch Collection" ]; then
    aws opensearchserverless list-collections --query "collectionSummaries[?name=='$RESOURCE_ID'].name" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "Secrets Manager Secret" ]; then
    aws secretsmanager list-secrets --query "SecretList[?Name=='$RESOURCE_ID'].Name" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "Budget" ]; then
    aws budgets describe-budgets --account-id $AWS_ACCOUNT_ID --query "Budgets[?BudgetName=='$RESOURCE_ID'].BudgetName" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "IAM Policy" ]; then
    aws iam list-policies --scope Local --query "Policies[?PolicyName=='$RESOURCE_ID'].PolicyName" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  else
    # Default to assuming resource doesn't exist
    EXISTS=1
  fi
  
  if [ $EXISTS -eq 0 ]; then
    echo -e "${YELLOW}Resource exists, deleting...${NC}"
    eval $DELETE_CMD || echo -e "${RED}Failed to delete resource. Continuing...${NC}"
  else
    echo -e "${GREEN}Resource does not exist, skipping...${NC}"
  fi
}

# Ask for confirmation
read -p "This script will delete existing AWS resources. Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Operation cancelled.${NC}"
    exit 1
fi

# Delete resources that often cause conflicts
echo -e "${BLUE}Deleting conflicting resources...${NC}"

# CloudWatch Log Groups
delete_if_exists "CloudWatch Log Group" "/aws/apigateway/secure-api-$ENV" "aws logs delete-log-group --log-group-name \"/aws/apigateway/secure-api-$ENV\""
delete_if_exists "CloudWatch Log Group" "/aws/apigateway/kb-api-$ENV" "aws logs delete-log-group --log-group-name \"/aws/apigateway/kb-api-$ENV\""

# WAFv2 Web ACL
delete_if_exists "WAFv2 Web ACL" "api-protection-$ENV" "aws wafv2 delete-web-acl --name api-protection-$ENV --scope REGIONAL --lock-token \$(aws wafv2 list-web-acls --scope REGIONAL --query \"WebACLs[?Name=='api-protection-$ENV'].LockToken\" --output text)"

# Bedrock Agents
delete_if_exists "Bedrock Agent" "agent-$ENV-acme" "aws bedrock-agent delete-agent --agent-id \$(aws bedrock-agent list-agents --query \"agentSummaries[?agentName=='agent-$ENV-acme'].agentId\" --output text) --skip-resource-in-use-check"
delete_if_exists "Bedrock Agent" "agent-$ENV-globex" "aws bedrock-agent delete-agent --agent-id \$(aws bedrock-agent list-agents --query \"agentSummaries[?agentName=='agent-$ENV-globex'].agentId\" --output text) --skip-resource-in-use-check"

# Bedrock Guardrails
delete_if_exists "Bedrock Guardrail" "gr-$ENV-acme" "aws bedrock delete-guardrail --guardrail-id \$(aws bedrock list-guardrails --query \"guardrails[?name=='gr-$ENV-acme'].guardrailId\" --output text)"
delete_if_exists "Bedrock Guardrail" "gr-$ENV-globex" "aws bedrock delete-guardrail --guardrail-id \$(aws bedrock list-guardrails --query \"guardrails[?name=='gr-$ENV-globex'].guardrailId\" --output text)"

# OpenSearch Collections
delete_if_exists "OpenSearch Collection" "kb-$ENV-acme" "aws opensearchserverless delete-collection --name kb-$ENV-acme"
delete_if_exists "OpenSearch Collection" "kb-$ENV-globex" "aws opensearchserverless delete-collection --name kb-$ENV-globex"

# Secrets Manager Secrets
delete_if_exists "Secrets Manager Secret" "aurora-$ENV-admin-new" "aws secretsmanager delete-secret --secret-id aurora-$ENV-admin-new --force-delete-without-recovery"

# Budgets
delete_if_exists "Budget" "cloudable-budget-$ENV-$REGION" "aws budgets delete-budget --account-id $AWS_ACCOUNT_ID --budget-name cloudable-budget-$ENV-$REGION"

# IAM Policies
delete_if_exists "IAM Policy" "document-summarizer-logs-$ENV-$REGION" "aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/document-summarizer-logs-$ENV-$REGION"
delete_if_exists "IAM Policy" "document-summarizer-s3-read-$ENV-$REGION" "aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/document-summarizer-s3-read-$ENV-$REGION"
delete_if_exists "IAM Policy" "document-summarizer-s3-write-$ENV-$REGION" "aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/document-summarizer-s3-write-$ENV-$REGION"
delete_if_exists "IAM Policy" "document-summarizer-bedrock-$ENV-$REGION" "aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/document-summarizer-bedrock-$ENV-$REGION"
delete_if_exists "IAM Policy" "document-summarizer-kms-$ENV-$REGION" "aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/document-summarizer-kms-$ENV-$REGION"
delete_if_exists "IAM Policy" "document-summarizer-sqs-$ENV-$REGION" "aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/document-summarizer-sqs-$ENV-$REGION"

echo -e "${GREEN}Cleanup completed.${NC}"
echo -e "${BLUE}Now you can run the deployment script again.${NC}"
# Script to destroy existing AWS resources that conflict with our deployment
set -e

# Color configuration
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ENV=${1:-dev}
REGION=${2:-us-east-1}

echo -e "${BLUE}=== Cloudable.AI Resource Cleanup Script ===${NC}"
echo -e "Environment: ${GREEN}$ENV${NC}"
echo -e "Region: ${GREEN}$REGION${NC}"

# Get AWS account ID
echo -e "${BLUE}Getting AWS account ID...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "AWS Account ID: ${GREEN}$AWS_ACCOUNT_ID${NC}"

# Function to check if resource exists and delete it
delete_if_exists() {
  RESOURCE_TYPE=$1
  RESOURCE_ID=$2
  DELETE_CMD=$3
  
  echo -e "${BLUE}Checking if $RESOURCE_TYPE '$RESOURCE_ID' exists...${NC}"
  
  if [ "$RESOURCE_TYPE" == "CloudWatch Log Group" ]; then
    aws logs describe-log-groups --log-group-name-prefix "$RESOURCE_ID" --query "logGroups[?logGroupName=='$RESOURCE_ID'].logGroupName" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "WAFv2 Web ACL" ]; then
    aws wafv2 list-web-acls --scope REGIONAL --query "WebACLs[?Name=='$RESOURCE_ID'].Name" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "Bedrock Agent" ]; then
    aws bedrock-agent list-agents --query "agentSummaries[?agentName=='$RESOURCE_ID'].agentName" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "Bedrock Guardrail" ]; then
    aws bedrock list-guardrails --query "guardrails[?name=='$RESOURCE_ID'].name" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "OpenSearch Collection" ]; then
    aws opensearchserverless list-collections --query "collectionSummaries[?name=='$RESOURCE_ID'].name" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "Secrets Manager Secret" ]; then
    aws secretsmanager list-secrets --query "SecretList[?Name=='$RESOURCE_ID'].Name" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "Budget" ]; then
    aws budgets describe-budgets --account-id $AWS_ACCOUNT_ID --query "Budgets[?BudgetName=='$RESOURCE_ID'].BudgetName" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "IAM Policy" ]; then
    aws iam list-policies --scope Local --query "Policies[?PolicyName=='$RESOURCE_ID'].PolicyName" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  else
    # Default to assuming resource doesn't exist
    EXISTS=1
  fi
  
  if [ $EXISTS -eq 0 ]; then
    echo -e "${YELLOW}Resource exists, deleting...${NC}"
    eval $DELETE_CMD || echo -e "${RED}Failed to delete resource. Continuing...${NC}"
  else
    echo -e "${GREEN}Resource does not exist, skipping...${NC}"
  fi
}

# Ask for confirmation
read -p "This script will delete existing AWS resources. Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Operation cancelled.${NC}"
    exit 1
fi

# Delete resources that often cause conflicts
echo -e "${BLUE}Deleting conflicting resources...${NC}"

# CloudWatch Log Groups
delete_if_exists "CloudWatch Log Group" "/aws/apigateway/secure-api-$ENV" "aws logs delete-log-group --log-group-name \"/aws/apigateway/secure-api-$ENV\""
delete_if_exists "CloudWatch Log Group" "/aws/apigateway/kb-api-$ENV" "aws logs delete-log-group --log-group-name \"/aws/apigateway/kb-api-$ENV\""

# WAFv2 Web ACL
delete_if_exists "WAFv2 Web ACL" "api-protection-$ENV" "aws wafv2 delete-web-acl --name api-protection-$ENV --scope REGIONAL --lock-token \$(aws wafv2 list-web-acls --scope REGIONAL --query \"WebACLs[?Name=='api-protection-$ENV'].LockToken\" --output text)"

# Bedrock Agents
delete_if_exists "Bedrock Agent" "agent-$ENV-acme" "aws bedrock-agent delete-agent --agent-id \$(aws bedrock-agent list-agents --query \"agentSummaries[?agentName=='agent-$ENV-acme'].agentId\" --output text) --skip-resource-in-use-check"
delete_if_exists "Bedrock Agent" "agent-$ENV-globex" "aws bedrock-agent delete-agent --agent-id \$(aws bedrock-agent list-agents --query \"agentSummaries[?agentName=='agent-$ENV-globex'].agentId\" --output text) --skip-resource-in-use-check"

# Bedrock Guardrails
delete_if_exists "Bedrock Guardrail" "gr-$ENV-acme" "aws bedrock delete-guardrail --guardrail-id \$(aws bedrock list-guardrails --query \"guardrails[?name=='gr-$ENV-acme'].guardrailId\" --output text)"
delete_if_exists "Bedrock Guardrail" "gr-$ENV-globex" "aws bedrock delete-guardrail --guardrail-id \$(aws bedrock list-guardrails --query \"guardrails[?name=='gr-$ENV-globex'].guardrailId\" --output text)"

# OpenSearch Collections
delete_if_exists "OpenSearch Collection" "kb-$ENV-acme" "aws opensearchserverless delete-collection --name kb-$ENV-acme"
delete_if_exists "OpenSearch Collection" "kb-$ENV-globex" "aws opensearchserverless delete-collection --name kb-$ENV-globex"

# Secrets Manager Secrets
delete_if_exists "Secrets Manager Secret" "aurora-$ENV-admin-new" "aws secretsmanager delete-secret --secret-id aurora-$ENV-admin-new --force-delete-without-recovery"

# Budgets
delete_if_exists "Budget" "cloudable-budget-$ENV-$REGION" "aws budgets delete-budget --account-id $AWS_ACCOUNT_ID --budget-name cloudable-budget-$ENV-$REGION"

# IAM Policies
delete_if_exists "IAM Policy" "document-summarizer-logs-$ENV-$REGION" "aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/document-summarizer-logs-$ENV-$REGION"
delete_if_exists "IAM Policy" "document-summarizer-s3-read-$ENV-$REGION" "aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/document-summarizer-s3-read-$ENV-$REGION"
delete_if_exists "IAM Policy" "document-summarizer-s3-write-$ENV-$REGION" "aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/document-summarizer-s3-write-$ENV-$REGION"
delete_if_exists "IAM Policy" "document-summarizer-bedrock-$ENV-$REGION" "aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/document-summarizer-bedrock-$ENV-$REGION"
delete_if_exists "IAM Policy" "document-summarizer-kms-$ENV-$REGION" "aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/document-summarizer-kms-$ENV-$REGION"
delete_if_exists "IAM Policy" "document-summarizer-sqs-$ENV-$REGION" "aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/document-summarizer-sqs-$ENV-$REGION"

echo -e "${GREEN}Cleanup completed.${NC}"
echo -e "${BLUE}Now you can run the deployment script again.${NC}"
