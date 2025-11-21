#!/bin/bash
set -e

echo "==== DELETING CONFLICTING RESOURCES ===="

# Delete OpenSearch Security Policies
echo "Deleting OpenSearch Security Policies..."
for policy in $(aws opensearchserverless list-security-policies --profile cloudable-ai --type encryption --query 'securityPolicyDetails[?starts_with(name, `policy-dev-`)].name' --output text); do
  echo "  Deleting security policy: $policy"
  aws opensearchserverless delete-security-policy --profile cloudable-ai --type encryption --name "$policy" || echo "  Failed to delete $policy"
done

# Delete OpenSearch Access Policies
echo "Deleting OpenSearch Access Policies..."
for policy in $(aws opensearchserverless list-access-policies --profile cloudable-ai --type data --query 'accessPolicyDetails[?starts_with(name, `access-dev-`)].name' --output text); do
  echo "  Deleting access policy: $policy"
  aws opensearchserverless delete-access-policy --profile cloudable-ai --type data --name "$policy" || echo "  Failed to delete $policy"
done

# Delete existing CloudWatch Log Groups that conflict
echo "Handling CloudWatch Log Groups..."
if aws logs describe-log-groups --profile cloudable-ai --log-group-name-prefix "/aws/lambda/orchestrator-dev" --query 'logGroups[].logGroupName' --output text | grep -q "/aws/lambda/orchestrator-dev"; then
  echo "  Deleting CloudWatch Log Group: /aws/lambda/orchestrator-dev"
  aws logs delete-log-group --profile cloudable-ai --log-group-name "/aws/lambda/orchestrator-dev" || echo "  Failed to delete log group"
fi

echo "Conflict resolution complete!"
