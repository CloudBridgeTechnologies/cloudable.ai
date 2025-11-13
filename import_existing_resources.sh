#!/bin/bash
# Script to import existing AWS resources into Terraform state
set -e

# Color configuration
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ENV=${1:-dev}
REGION=${2:-us-east-1}
WORKING_DIR="infras/envs/us-east-1"

echo -e "${BLUE}=== Cloudable.AI Terraform Import Script ===${NC}"
echo -e "Environment: ${GREEN}$ENV${NC}"
echo -e "Region: ${GREEN}$REGION${NC}"

# Navigate to Terraform directory
cd $WORKING_DIR

# Initialize terraform
echo -e "${BLUE}Initializing Terraform...${NC}"
terraform init -reconfigure

# Get AWS account ID
echo -e "${BLUE}Getting AWS account ID...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "AWS Account ID: ${GREEN}$AWS_ACCOUNT_ID${NC}"

# Function to import resource if it exists
import_if_exists() {
  RESOURCE_TYPE=$1
  RESOURCE_ID=$2
  TF_RESOURCE=$3
  
  echo -e "${BLUE}Checking if $RESOURCE_TYPE '$RESOURCE_ID' exists...${NC}"
  
  if [ "$RESOURCE_TYPE" == "aws_cloudwatch_log_group" ]; then
    aws logs describe-log-groups --log-group-name-prefix "$RESOURCE_ID" --query "logGroups[?logGroupName=='$RESOURCE_ID'].logGroupName" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_wafv2_web_acl" ]; then
    aws wafv2 list-web-acls --scope REGIONAL --query "WebACLs[?Name=='api-protection-$ENV'].Name" --output text | grep -q "api-protection-$ENV"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_bedrockagent_agent" ]; then
    NAME=$(echo $RESOURCE_ID | cut -d':' -f2)
    aws bedrock-agent list-agents --query "agentSummaries[?agentName=='$NAME'].agentName" --output text | grep -q "$NAME"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_bedrock_guardrail" ]; then
    NAME=$(echo $RESOURCE_ID | cut -d':' -f2)
    aws bedrock list-guardrails --query "guardrails[?name=='$NAME'].name" --output text | grep -q "$NAME"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_opensearchserverless_collection" ]; then
    NAME=$RESOURCE_ID
    aws opensearchserverless list-collections --query "collectionSummaries[?name=='$NAME'].name" --output text | grep -q "$NAME"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_opensearchserverless_security_policy" ]; then
    NAME=$RESOURCE_ID
    aws opensearchserverless list-security-policies --type encryption --query "securityPolicySummaries[?name=='$NAME'].name" --output text | grep -q "$NAME"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_secretsmanager_secret" ]; then
    aws secretsmanager list-secrets --query "SecretList[?Name=='$RESOURCE_ID'].Name" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_budgets_budget" ]; then
    aws budgets describe-budgets --account-id $AWS_ACCOUNT_ID --query "Budgets[?BudgetName=='$RESOURCE_ID'].BudgetName" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_iam_policy" ]; then
    aws iam list-policies --scope Local --query "Policies[?PolicyName=='$RESOURCE_ID'].PolicyName" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  else
    # Default to assuming resource exists
    EXISTS=0
  fi
  
  if [ $EXISTS -eq 0 ]; then
    echo -e "${GREEN}Resource exists, importing...${NC}"
    terraform import $TF_RESOURCE $RESOURCE_ID || echo -e "${YELLOW}Import failed or already in state. Continuing...${NC}"
  else
    echo -e "${YELLOW}Resource does not exist, skipping...${NC}"
  fi
}

# Import existing resources
echo -e "${BLUE}Importing existing resources...${NC}"

# CloudWatch Log Groups
import_if_exists "aws_cloudwatch_log_group" "/aws/apigateway/secure-api-$ENV" "aws_cloudwatch_log_group.api_gateway_logs"
import_if_exists "aws_cloudwatch_log_group" "/aws/apigateway/kb-api-$ENV" "aws_cloudwatch_log_group.kb_api_logs"
import_if_exists "aws_cloudwatch_log_group" "/aws/lambda/db-actions-$ENV" "aws_cloudwatch_log_group.db_actions"
import_if_exists "aws_cloudwatch_log_group" "/aws/lambda/orchestrator-$ENV" "aws_cloudwatch_log_group.orchestrator"
import_if_exists "aws_cloudwatch_log_group" "/aws/bedrock/agent-core-telemetry-$ENV" "aws_cloudwatch_log_group.agent_telemetry"
import_if_exists "aws_cloudwatch_log_group" "/aws/bedrock/agent-core-tracing-$ENV" "aws_cloudwatch_log_group.agent_tracing"

# WAFv2 Web ACL
import_if_exists "aws_wafv2_web_acl" "api-protection-$ENV" "aws_wafv2_web_acl.api_protection"

# Bedrock Agents
import_if_exists "aws_bedrockagent_agent" "t001:agent-$ENV-acme" 'aws_bedrockagent_agent.tenant["t001"]'
import_if_exists "aws_bedrockagent_agent" "t002:agent-$ENV-globex" 'aws_bedrockagent_agent.tenant["t002"]'

# Bedrock Guardrails
import_if_exists "aws_bedrock_guardrail" "t001:gr-$ENV-acme" 'aws_bedrock_guardrail.tenant["t001"]'
import_if_exists "aws_bedrock_guardrail" "t002:gr-$ENV-globex" 'aws_bedrock_guardrail.tenant["t002"]'

# OpenSearch Serverless Collections
import_if_exists "aws_opensearchserverless_collection" "kb-$ENV-acme" 'aws_opensearchserverless_collection.kb["t001"]'
import_if_exists "aws_opensearchserverless_collection" "kb-$ENV-globex" 'aws_opensearchserverless_collection.kb["t002"]'

# OpenSearch Security Policies
import_if_exists "aws_opensearchserverless_security_policy" "policy-$ENV-acme" 'aws_opensearchserverless_security_policy.kb["t001"]'
import_if_exists "aws_opensearchserverless_security_policy" "policy-$ENV-globex" 'aws_opensearchserverless_security_policy.kb["t002"]'

# Secrets Manager Secrets
import_if_exists "aws_secretsmanager_secret" "aurora-$ENV-admin-new" "aws_secretsmanager_secret.db"

# Budgets
import_if_exists "aws_budgets_budget" "cloudable-budget-$ENV-$REGION" "aws_budgets_budget.monthly"

# IAM Policies
import_if_exists "aws_iam_policy" "document-summarizer-logs-$ENV-$REGION" "aws_iam_policy.document_summarizer_logs"
import_if_exists "aws_iam_policy" "document-summarizer-s3-read-$ENV-$REGION" "aws_iam_policy.document_summarizer_s3_read"
import_if_exists "aws_iam_policy" "document-summarizer-s3-write-$ENV-$REGION" "aws_iam_policy.document_summarizer_s3_write"
import_if_exists "aws_iam_policy" "document-summarizer-bedrock-$ENV-$REGION" "aws_iam_policy.document_summarizer_bedrock"
import_if_exists "aws_iam_policy" "document-summarizer-kms-$ENV-$REGION" "aws_iam_policy.document_summarizer_kms"
import_if_exists "aws_iam_policy" "document-summarizer-sqs-$ENV-$REGION" "aws_iam_policy.document_summarizer_sqs"

echo -e "${GREEN}Import completed.${NC}"
echo -e "${BLUE}Now you can run the deployment script again.${NC}"
# Script to import existing AWS resources into Terraform state
set -e

# Color configuration
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ENV=${1:-dev}
REGION=${2:-us-east-1}
WORKING_DIR="infras/envs/us-east-1"

echo -e "${BLUE}=== Cloudable.AI Terraform Import Script ===${NC}"
echo -e "Environment: ${GREEN}$ENV${NC}"
echo -e "Region: ${GREEN}$REGION${NC}"

# Navigate to Terraform directory
cd $WORKING_DIR

# Initialize terraform
echo -e "${BLUE}Initializing Terraform...${NC}"
terraform init -reconfigure

# Get AWS account ID
echo -e "${BLUE}Getting AWS account ID...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "AWS Account ID: ${GREEN}$AWS_ACCOUNT_ID${NC}"

# Function to import resource if it exists
import_if_exists() {
  RESOURCE_TYPE=$1
  RESOURCE_ID=$2
  TF_RESOURCE=$3
  
  echo -e "${BLUE}Checking if $RESOURCE_TYPE '$RESOURCE_ID' exists...${NC}"
  
  if [ "$RESOURCE_TYPE" == "aws_cloudwatch_log_group" ]; then
    aws logs describe-log-groups --log-group-name-prefix "$RESOURCE_ID" --query "logGroups[?logGroupName=='$RESOURCE_ID'].logGroupName" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_wafv2_web_acl" ]; then
    aws wafv2 list-web-acls --scope REGIONAL --query "WebACLs[?Name=='api-protection-$ENV'].Name" --output text | grep -q "api-protection-$ENV"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_bedrockagent_agent" ]; then
    NAME=$(echo $RESOURCE_ID | cut -d':' -f2)
    aws bedrock-agent list-agents --query "agentSummaries[?agentName=='$NAME'].agentName" --output text | grep -q "$NAME"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_bedrock_guardrail" ]; then
    NAME=$(echo $RESOURCE_ID | cut -d':' -f2)
    aws bedrock list-guardrails --query "guardrails[?name=='$NAME'].name" --output text | grep -q "$NAME"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_opensearchserverless_collection" ]; then
    NAME=$RESOURCE_ID
    aws opensearchserverless list-collections --query "collectionSummaries[?name=='$NAME'].name" --output text | grep -q "$NAME"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_opensearchserverless_security_policy" ]; then
    NAME=$RESOURCE_ID
    aws opensearchserverless list-security-policies --type encryption --query "securityPolicySummaries[?name=='$NAME'].name" --output text | grep -q "$NAME"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_secretsmanager_secret" ]; then
    aws secretsmanager list-secrets --query "SecretList[?Name=='$RESOURCE_ID'].Name" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_budgets_budget" ]; then
    aws budgets describe-budgets --account-id $AWS_ACCOUNT_ID --query "Budgets[?BudgetName=='$RESOURCE_ID'].BudgetName" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  elif [ "$RESOURCE_TYPE" == "aws_iam_policy" ]; then
    aws iam list-policies --scope Local --query "Policies[?PolicyName=='$RESOURCE_ID'].PolicyName" --output text | grep -q "$RESOURCE_ID"
    EXISTS=$?
  else
    # Default to assuming resource exists
    EXISTS=0
  fi
  
  if [ $EXISTS -eq 0 ]; then
    echo -e "${GREEN}Resource exists, importing...${NC}"
    terraform import $TF_RESOURCE $RESOURCE_ID || echo -e "${YELLOW}Import failed or already in state. Continuing...${NC}"
  else
    echo -e "${YELLOW}Resource does not exist, skipping...${NC}"
  fi
}

# Import existing resources
echo -e "${BLUE}Importing existing resources...${NC}"

# CloudWatch Log Groups
import_if_exists "aws_cloudwatch_log_group" "/aws/apigateway/secure-api-$ENV" "aws_cloudwatch_log_group.api_gateway_logs"
import_if_exists "aws_cloudwatch_log_group" "/aws/apigateway/kb-api-$ENV" "aws_cloudwatch_log_group.kb_api_logs"
import_if_exists "aws_cloudwatch_log_group" "/aws/lambda/db-actions-$ENV" "aws_cloudwatch_log_group.db_actions"
import_if_exists "aws_cloudwatch_log_group" "/aws/lambda/orchestrator-$ENV" "aws_cloudwatch_log_group.orchestrator"
import_if_exists "aws_cloudwatch_log_group" "/aws/bedrock/agent-core-telemetry-$ENV" "aws_cloudwatch_log_group.agent_telemetry"
import_if_exists "aws_cloudwatch_log_group" "/aws/bedrock/agent-core-tracing-$ENV" "aws_cloudwatch_log_group.agent_tracing"

# WAFv2 Web ACL
import_if_exists "aws_wafv2_web_acl" "api-protection-$ENV" "aws_wafv2_web_acl.api_protection"

# Bedrock Agents
import_if_exists "aws_bedrockagent_agent" "t001:agent-$ENV-acme" 'aws_bedrockagent_agent.tenant["t001"]'
import_if_exists "aws_bedrockagent_agent" "t002:agent-$ENV-globex" 'aws_bedrockagent_agent.tenant["t002"]'

# Bedrock Guardrails
import_if_exists "aws_bedrock_guardrail" "t001:gr-$ENV-acme" 'aws_bedrock_guardrail.tenant["t001"]'
import_if_exists "aws_bedrock_guardrail" "t002:gr-$ENV-globex" 'aws_bedrock_guardrail.tenant["t002"]'

# OpenSearch Serverless Collections
import_if_exists "aws_opensearchserverless_collection" "kb-$ENV-acme" 'aws_opensearchserverless_collection.kb["t001"]'
import_if_exists "aws_opensearchserverless_collection" "kb-$ENV-globex" 'aws_opensearchserverless_collection.kb["t002"]'

# OpenSearch Security Policies
import_if_exists "aws_opensearchserverless_security_policy" "policy-$ENV-acme" 'aws_opensearchserverless_security_policy.kb["t001"]'
import_if_exists "aws_opensearchserverless_security_policy" "policy-$ENV-globex" 'aws_opensearchserverless_security_policy.kb["t002"]'

# Secrets Manager Secrets
import_if_exists "aws_secretsmanager_secret" "aurora-$ENV-admin-new" "aws_secretsmanager_secret.db"

# Budgets
import_if_exists "aws_budgets_budget" "cloudable-budget-$ENV-$REGION" "aws_budgets_budget.monthly"

# IAM Policies
import_if_exists "aws_iam_policy" "document-summarizer-logs-$ENV-$REGION" "aws_iam_policy.document_summarizer_logs"
import_if_exists "aws_iam_policy" "document-summarizer-s3-read-$ENV-$REGION" "aws_iam_policy.document_summarizer_s3_read"
import_if_exists "aws_iam_policy" "document-summarizer-s3-write-$ENV-$REGION" "aws_iam_policy.document_summarizer_s3_write"
import_if_exists "aws_iam_policy" "document-summarizer-bedrock-$ENV-$REGION" "aws_iam_policy.document_summarizer_bedrock"
import_if_exists "aws_iam_policy" "document-summarizer-kms-$ENV-$REGION" "aws_iam_policy.document_summarizer_kms"
import_if_exists "aws_iam_policy" "document-summarizer-sqs-$ENV-$REGION" "aws_iam_policy.document_summarizer_sqs"

echo -e "${GREEN}Import completed.${NC}"
echo -e "${BLUE}Now you can run the deployment script again.${NC}"
