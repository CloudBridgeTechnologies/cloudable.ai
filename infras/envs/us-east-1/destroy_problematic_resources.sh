#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Destroying problematic resources ===${NC}"

# Check if we have AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}Error: AWS credentials not configured. Please run aws configure first.${NC}"
    exit 1
fi

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"

# 1. Delete Bedrock Agent Knowledge Base Associations
echo -e "${YELLOW}Deleting Bedrock Agent Knowledge Base Associations...${NC}"
for AGENT_ID in $(aws bedrock-agent list-agents --query "agentSummaries[?contains(agentName, 'agent-dev')].agentId" --output text); do
    AGENT_NAME=$(aws bedrock-agent get-agent --agent-id $AGENT_ID --query agent.agentName --output text)
    echo "Checking associations for agent: $AGENT_NAME ($AGENT_ID)"
    
    for ASSOCIATION in $(aws bedrock-agent list-agent-knowledge-bases --agent-id $AGENT_ID --agent-version DRAFT --query "knowledgeBaseSummaries[].knowledgeBaseId" --output text); do
        echo "Deleting association between $AGENT_NAME and knowledge base $ASSOCIATION"
        aws bedrock-agent disassociate-agent-knowledge-base --agent-id $AGENT_ID --agent-version DRAFT --knowledge-base-id $ASSOCIATION || true
    done
done

# 2. Delete Bedrock Agent Aliases
echo -e "${YELLOW}Deleting Bedrock Agent Aliases...${NC}"
for AGENT_ID in $(aws bedrock-agent list-agents --query "agentSummaries[?contains(agentName, 'agent-dev')].agentId" --output text); do
    AGENT_NAME=$(aws bedrock-agent get-agent --agent-id $AGENT_ID --query agent.agentName --output text)
    echo "Deleting aliases for agent: $AGENT_NAME ($AGENT_ID)"
    
    for ALIAS in $(aws bedrock-agent list-agent-aliases --agent-id $AGENT_ID --query "agentAliasSummaries[].agentAliasId" --output text); do
        echo "Deleting alias $ALIAS for agent $AGENT_NAME"
        aws bedrock-agent delete-agent-alias --agent-id $AGENT_ID --agent-alias-id $ALIAS || true
    done
done

# 3. Delete Bedrock Agent Action Groups
echo -e "${YELLOW}Deleting Bedrock Agent Action Groups...${NC}"
for AGENT_ID in $(aws bedrock-agent list-agents --query "agentSummaries[?contains(agentName, 'agent-dev')].agentId" --output text); do
    AGENT_NAME=$(aws bedrock-agent get-agent --agent-id $AGENT_ID --query agent.agentName --output text)
    echo "Deleting action groups for agent: $AGENT_NAME ($AGENT_ID)"
    
    for ACTION_GROUP in $(aws bedrock-agent list-agent-action-groups --agent-id $AGENT_ID --agent-version DRAFT --query "actionGroupSummaries[].actionGroupId" --output text); do
        echo "Deleting action group $ACTION_GROUP for agent $AGENT_NAME"
        aws bedrock-agent delete-agent-action-group --agent-id $AGENT_ID --agent-version DRAFT --action-group-id $ACTION_GROUP || true
    done
done

# 4. Delete Bedrock Agents
echo -e "${YELLOW}Deleting Bedrock Agents...${NC}"
for AGENT_ID in $(aws bedrock-agent list-agents --query "agentSummaries[?contains(agentName, 'agent-dev')].agentId" --output text); do
    AGENT_NAME=$(aws bedrock-agent get-agent --agent-id $AGENT_ID --query agent.agentName --output text)
    echo "Deleting agent: $AGENT_NAME ($AGENT_ID)"
    aws bedrock-agent delete-agent --agent-id $AGENT_ID || true
done

# 5. Delete Bedrock Knowledge Bases
echo -e "${YELLOW}Deleting Bedrock Knowledge Bases...${NC}"
for KB_ID in $(aws bedrock-agent list-knowledge-bases --query "knowledgeBaseSummaries[?contains(name, 'kb-dev')].knowledgeBaseId" --output text); do
    KB_NAME=$(aws bedrock-agent get-knowledge-base --knowledge-base-id $KB_ID --query knowledgeBase.name --output text)
    echo "Deleting knowledge base: $KB_NAME ($KB_ID)"
    aws bedrock-agent delete-knowledge-base --knowledge-base-id $KB_ID || true
done

# 6. Delete Bedrock Guardrails
echo -e "${YELLOW}Deleting Bedrock Guardrails...${NC}"
for GUARDRAIL_ID in $(aws bedrock list-guardrails --query "guardrails[?contains(name, 'gr-dev')].id" --output text); do
    GUARDRAIL_NAME=$(aws bedrock get-guardrail --guardrail-id $GUARDRAIL_ID --query guardrail.name --output text)
    echo "Deleting guardrail: $GUARDRAIL_NAME ($GUARDRAIL_ID)"
    aws bedrock delete-guardrail --guardrail-id $GUARDRAIL_ID || true
done

# 7. Delete WAF Web ACL
echo -e "${YELLOW}Deleting WAF Web ACL...${NC}"
for WAF_ID in $(aws wafv2 list-web-acls --scope REGIONAL --query "WebACLs[?contains(Name, 'api-protection-dev')].Id" --output text); do
    WAF_NAME="api-protection-dev"
    echo "Deleting WAF Web ACL: $WAF_NAME ($WAF_ID)"
    
    # First, check for any associations and remove them
    ASSOCIATIONS=$(aws wafv2 list-resources-for-web-acl --web-acl-arn "arn:aws:wafv2:us-east-1:${ACCOUNT_ID}:regional/webacl/$WAF_NAME/$WAF_ID" --resource-type API_GATEWAY --query "ResourceArns" --output text || echo "")
    
    for ASSOC in $ASSOCIATIONS; do
        echo "Removing WAF association for $ASSOC"
        aws wafv2 disassociate-web-acl --resource-arn "$ASSOC" || true
    done
    
    # Now delete the Web ACL
    LOCK_TOKEN=$(aws wafv2 get-web-acl --name "$WAF_NAME" --scope REGIONAL --id "$WAF_ID" --query "LockToken" --output text)
    aws wafv2 delete-web-acl --name "$WAF_NAME" --scope REGIONAL --id "$WAF_ID" --lock-token "$LOCK_TOKEN" || true
done

# 8. Delete CloudWatch Log Groups that cause issues
echo -e "${YELLOW}Deleting problematic CloudWatch Log Groups...${NC}"
aws logs delete-log-group --log-group-name "/aws/lambda/summary-retriever-dev" || true

# 9. Delete problematic IAM policies
echo -e "${YELLOW}Deleting problematic IAM policies...${NC}"
for POLICY_NAME in "document-summarizer-logs-dev-us-east-1" "document-summarizer-s3-read-dev-us-east-1" "document-summarizer-s3-write-dev-us-east-1" "document-summarizer-bedrock-dev-us-east-1" "document-summarizer-kms-dev-us-east-1" "document-summarizer-sqs-dev-us-east-1"; do
    echo "Checking for policy: $POLICY_NAME"
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    # Check if policy exists
    if aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
        echo "Deleting policy: $POLICY_NAME"
        
        # Detach policy from all roles
        for ROLE in $(aws iam list-entities-for-policy --policy-arn "$POLICY_ARN" --entity-filter Role --query "PolicyRoles[].RoleName" --output text); do
            echo "Detaching policy from role: $ROLE"
            aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$POLICY_ARN" || true
        done
        
        # Delete policy versions (except default)
        for VERSION in $(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query "Versions[?IsDefaultVersion==\`false\`].VersionId" --output text); do
            echo "Deleting policy version: $VERSION"
            aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$VERSION" || true
        done
        
        # Delete policy
        aws iam delete-policy --policy-arn "$POLICY_ARN" || true
    else
        echo "Policy $POLICY_NAME not found, skipping"
    fi
done

# 10. Delete budget
echo -e "${YELLOW}Deleting budget...${NC}"
aws budgets delete-budget --account-id "$ACCOUNT_ID" --budget-name "cloudable-budget-dev-us-east-1" || true

echo -e "${GREEN}Resource deletion completed.${NC}"
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Destroying problematic resources ===${NC}"

# Check if we have AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}Error: AWS credentials not configured. Please run aws configure first.${NC}"
    exit 1
fi

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"

# 1. Delete Bedrock Agent Knowledge Base Associations
echo -e "${YELLOW}Deleting Bedrock Agent Knowledge Base Associations...${NC}"
for AGENT_ID in $(aws bedrock-agent list-agents --query "agentSummaries[?contains(agentName, 'agent-dev')].agentId" --output text); do
    AGENT_NAME=$(aws bedrock-agent get-agent --agent-id $AGENT_ID --query agent.agentName --output text)
    echo "Checking associations for agent: $AGENT_NAME ($AGENT_ID)"
    
    for ASSOCIATION in $(aws bedrock-agent list-agent-knowledge-bases --agent-id $AGENT_ID --agent-version DRAFT --query "knowledgeBaseSummaries[].knowledgeBaseId" --output text); do
        echo "Deleting association between $AGENT_NAME and knowledge base $ASSOCIATION"
        aws bedrock-agent disassociate-agent-knowledge-base --agent-id $AGENT_ID --agent-version DRAFT --knowledge-base-id $ASSOCIATION || true
    done
done

# 2. Delete Bedrock Agent Aliases
echo -e "${YELLOW}Deleting Bedrock Agent Aliases...${NC}"
for AGENT_ID in $(aws bedrock-agent list-agents --query "agentSummaries[?contains(agentName, 'agent-dev')].agentId" --output text); do
    AGENT_NAME=$(aws bedrock-agent get-agent --agent-id $AGENT_ID --query agent.agentName --output text)
    echo "Deleting aliases for agent: $AGENT_NAME ($AGENT_ID)"
    
    for ALIAS in $(aws bedrock-agent list-agent-aliases --agent-id $AGENT_ID --query "agentAliasSummaries[].agentAliasId" --output text); do
        echo "Deleting alias $ALIAS for agent $AGENT_NAME"
        aws bedrock-agent delete-agent-alias --agent-id $AGENT_ID --agent-alias-id $ALIAS || true
    done
done

# 3. Delete Bedrock Agent Action Groups
echo -e "${YELLOW}Deleting Bedrock Agent Action Groups...${NC}"
for AGENT_ID in $(aws bedrock-agent list-agents --query "agentSummaries[?contains(agentName, 'agent-dev')].agentId" --output text); do
    AGENT_NAME=$(aws bedrock-agent get-agent --agent-id $AGENT_ID --query agent.agentName --output text)
    echo "Deleting action groups for agent: $AGENT_NAME ($AGENT_ID)"
    
    for ACTION_GROUP in $(aws bedrock-agent list-agent-action-groups --agent-id $AGENT_ID --agent-version DRAFT --query "actionGroupSummaries[].actionGroupId" --output text); do
        echo "Deleting action group $ACTION_GROUP for agent $AGENT_NAME"
        aws bedrock-agent delete-agent-action-group --agent-id $AGENT_ID --agent-version DRAFT --action-group-id $ACTION_GROUP || true
    done
done

# 4. Delete Bedrock Agents
echo -e "${YELLOW}Deleting Bedrock Agents...${NC}"
for AGENT_ID in $(aws bedrock-agent list-agents --query "agentSummaries[?contains(agentName, 'agent-dev')].agentId" --output text); do
    AGENT_NAME=$(aws bedrock-agent get-agent --agent-id $AGENT_ID --query agent.agentName --output text)
    echo "Deleting agent: $AGENT_NAME ($AGENT_ID)"
    aws bedrock-agent delete-agent --agent-id $AGENT_ID || true
done

# 5. Delete Bedrock Knowledge Bases
echo -e "${YELLOW}Deleting Bedrock Knowledge Bases...${NC}"
for KB_ID in $(aws bedrock-agent list-knowledge-bases --query "knowledgeBaseSummaries[?contains(name, 'kb-dev')].knowledgeBaseId" --output text); do
    KB_NAME=$(aws bedrock-agent get-knowledge-base --knowledge-base-id $KB_ID --query knowledgeBase.name --output text)
    echo "Deleting knowledge base: $KB_NAME ($KB_ID)"
    aws bedrock-agent delete-knowledge-base --knowledge-base-id $KB_ID || true
done

# 6. Delete Bedrock Guardrails
echo -e "${YELLOW}Deleting Bedrock Guardrails...${NC}"
for GUARDRAIL_ID in $(aws bedrock list-guardrails --query "guardrails[?contains(name, 'gr-dev')].id" --output text); do
    GUARDRAIL_NAME=$(aws bedrock get-guardrail --guardrail-id $GUARDRAIL_ID --query guardrail.name --output text)
    echo "Deleting guardrail: $GUARDRAIL_NAME ($GUARDRAIL_ID)"
    aws bedrock delete-guardrail --guardrail-id $GUARDRAIL_ID || true
done

# 7. Delete WAF Web ACL
echo -e "${YELLOW}Deleting WAF Web ACL...${NC}"
for WAF_ID in $(aws wafv2 list-web-acls --scope REGIONAL --query "WebACLs[?contains(Name, 'api-protection-dev')].Id" --output text); do
    WAF_NAME="api-protection-dev"
    echo "Deleting WAF Web ACL: $WAF_NAME ($WAF_ID)"
    
    # First, check for any associations and remove them
    ASSOCIATIONS=$(aws wafv2 list-resources-for-web-acl --web-acl-arn "arn:aws:wafv2:us-east-1:${ACCOUNT_ID}:regional/webacl/$WAF_NAME/$WAF_ID" --resource-type API_GATEWAY --query "ResourceArns" --output text || echo "")
    
    for ASSOC in $ASSOCIATIONS; do
        echo "Removing WAF association for $ASSOC"
        aws wafv2 disassociate-web-acl --resource-arn "$ASSOC" || true
    done
    
    # Now delete the Web ACL
    LOCK_TOKEN=$(aws wafv2 get-web-acl --name "$WAF_NAME" --scope REGIONAL --id "$WAF_ID" --query "LockToken" --output text)
    aws wafv2 delete-web-acl --name "$WAF_NAME" --scope REGIONAL --id "$WAF_ID" --lock-token "$LOCK_TOKEN" || true
done

# 8. Delete CloudWatch Log Groups that cause issues
echo -e "${YELLOW}Deleting problematic CloudWatch Log Groups...${NC}"
aws logs delete-log-group --log-group-name "/aws/lambda/summary-retriever-dev" || true

# 9. Delete problematic IAM policies
echo -e "${YELLOW}Deleting problematic IAM policies...${NC}"
for POLICY_NAME in "document-summarizer-logs-dev-us-east-1" "document-summarizer-s3-read-dev-us-east-1" "document-summarizer-s3-write-dev-us-east-1" "document-summarizer-bedrock-dev-us-east-1" "document-summarizer-kms-dev-us-east-1" "document-summarizer-sqs-dev-us-east-1"; do
    echo "Checking for policy: $POLICY_NAME"
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    # Check if policy exists
    if aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
        echo "Deleting policy: $POLICY_NAME"
        
        # Detach policy from all roles
        for ROLE in $(aws iam list-entities-for-policy --policy-arn "$POLICY_ARN" --entity-filter Role --query "PolicyRoles[].RoleName" --output text); do
            echo "Detaching policy from role: $ROLE"
            aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$POLICY_ARN" || true
        done
        
        # Delete policy versions (except default)
        for VERSION in $(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query "Versions[?IsDefaultVersion==\`false\`].VersionId" --output text); do
            echo "Deleting policy version: $VERSION"
            aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$VERSION" || true
        done
        
        # Delete policy
        aws iam delete-policy --policy-arn "$POLICY_ARN" || true
    else
        echo "Policy $POLICY_NAME not found, skipping"
    fi
done

# 10. Delete budget
echo -e "${YELLOW}Deleting budget...${NC}"
aws budgets delete-budget --account-id "$ACCOUNT_ID" --budget-name "cloudable-budget-dev-us-east-1" || true

echo -e "${GREEN}Resource deletion completed.${NC}"
