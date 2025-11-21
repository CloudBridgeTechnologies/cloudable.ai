#!/bin/bash
# Script to complete the cleanup of remaining AWS resources

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE} FINAL CLOUDABLE.AI AWS RESOURCES CLEANUP         ${NC}"
echo -e "${BLUE}==================================================${NC}"

# 1. First, delete RDS instances (required before deleting the cluster)
echo -e "\n${YELLOW}1. Deleting RDS instances...${NC}"
INSTANCES=$(aws rds describe-db-instances --query "DBInstances[?contains(DBClusterIdentifier, 'aurora-dev')].DBInstanceIdentifier" --output text)

if [ -n "$INSTANCES" ]; then
  echo -e "${YELLOW}Found RDS instances to delete:${NC}"
  echo "$INSTANCES"
  
  for instance in $INSTANCES; do
    echo -e "${YELLOW}Deleting instance: ${instance}${NC}"
    aws rds delete-db-instance --db-instance-identifier ${instance} --skip-final-snapshot
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✓ Successfully initiated deletion of instance: ${instance}${NC}"
      echo -e "${YELLOW}Waiting for instance deletion to complete (this may take a few minutes)...${NC}"
      aws rds wait db-instance-deleted --db-instance-identifier ${instance}
    else
      echo -e "${RED}Failed to delete instance: ${instance}${NC}"
    fi
  done
else
  echo -e "${GREEN}No RDS instances found${NC}"
fi

# 2. Now delete the RDS cluster
echo -e "\n${YELLOW}2. Deleting RDS cluster...${NC}"
CLUSTERS=$(aws rds describe-db-clusters --query "DBClusters[?contains(DBClusterIdentifier, 'aurora-dev')].DBClusterIdentifier" --output text)

if [ -n "$CLUSTERS" ]; then
  echo -e "${YELLOW}Found RDS clusters to delete:${NC}"
  echo "$CLUSTERS"
  
  for cluster in $CLUSTERS; do
    echo -e "${YELLOW}Deleting cluster: ${cluster}${NC}"
    aws rds delete-db-cluster --db-cluster-identifier ${cluster} --skip-final-snapshot
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✓ Successfully initiated deletion of cluster: ${cluster}${NC}"
    else
      echo -e "${RED}Failed to delete cluster: ${cluster}${NC}"
    fi
  done
else
  echo -e "${GREEN}No RDS clusters found${NC}"
fi

# 3. Clean up S3 buckets with versions
echo -e "\n${YELLOW}3. Removing all versions from S3 buckets...${NC}"
BUCKETS="cloudable-kb-dev-us-east-1-20251024142435-acme cloudable-tfstate-dev-951296734820 cloudable-tfstate-dev-us-east-1"

for bucket in $BUCKETS; do
  echo -e "${YELLOW}Processing bucket: ${bucket}${NC}"
  
  # List all versions and delete markers
  VERSIONS=$(aws s3api list-object-versions --bucket ${bucket} --output json --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')
  DELETE_MARKERS=$(aws s3api list-object-versions --bucket ${bucket} --output json --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')
  
  # Delete all object versions
  if [ "$VERSIONS" != "{}" ] && [ "$VERSIONS" != "" ]; then
    echo -e "${YELLOW}Deleting all object versions...${NC}"
    aws s3api delete-objects --bucket ${bucket} --delete "$VERSIONS" || true
  fi
  
  # Delete all delete markers
  if [ "$DELETE_MARKERS" != "{}" ] && [ "$DELETE_MARKERS" != "" ]; then
    echo -e "${YELLOW}Deleting all delete markers...${NC}"
    aws s3api delete-objects --bucket ${bucket} --delete "$DELETE_MARKERS" || true
  fi
  
  # Force remove any remaining objects
  echo -e "${YELLOW}Force removing any remaining objects...${NC}"
  aws s3 rm s3://${bucket} --recursive --force || true
  
  # Delete the bucket
  echo -e "${YELLOW}Deleting bucket: ${bucket}${NC}"
  aws s3api delete-bucket --bucket ${bucket}
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully deleted bucket: ${bucket}${NC}"
  else
    echo -e "${RED}Failed to delete bucket: ${bucket}${NC}"
  fi
done

# 4. Clean up remaining AWS resources
echo -e "\n${YELLOW}4. Checking for remaining CloudWatch logs...${NC}"
LOG_GROUPS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '/aws/lambda/kb') || contains(logGroupName, 'cloudable')].logGroupName" --output text)

if [ -n "$LOG_GROUPS" ]; then
  echo -e "${YELLOW}Found CloudWatch log groups:${NC}"
  echo "$LOG_GROUPS"
  
  for log_group in $LOG_GROUPS; do
    echo -e "${YELLOW}Deleting log group: ${log_group}${NC}"
    aws logs delete-log-group --log-group-name ${log_group}
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✓ Successfully deleted log group: ${log_group}${NC}"
    else
      echo -e "${RED}Failed to delete log group: ${log_group}${NC}"
    fi
  done
else
  echo -e "${GREEN}No CloudWatch log groups found${NC}"
fi

# 5. Check for any remaining IAM roles
echo -e "\n${YELLOW}5. Checking for remaining IAM roles...${NC}"
IAM_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'cloudable') || contains(RoleName, 'kb-manager')].RoleName" --output text)

if [ -n "$IAM_ROLES" ]; then
  echo -e "${YELLOW}Found IAM roles:${NC}"
  echo "$IAM_ROLES"
  
  for role in $IAM_ROLES; do
    # First detach all policies
    echo -e "${YELLOW}Detaching policies from role: ${role}${NC}"
    POLICIES=$(aws iam list-attached-role-policies --role-name ${role} --query "AttachedPolicies[].PolicyArn" --output text)
    
    for policy in $POLICIES; do
      echo -e "${YELLOW}Detaching policy: ${policy}${NC}"
      aws iam detach-role-policy --role-name ${role} --policy-arn ${policy}
    done
    
    # Delete inline policies
    INLINE_POLICIES=$(aws iam list-role-policies --role-name ${role} --query "PolicyNames" --output text)
    
    for policy in $INLINE_POLICIES; do
      echo -e "${YELLOW}Deleting inline policy: ${policy}${NC}"
      aws iam delete-role-policy --role-name ${role} --policy-name ${policy}
    done
    
    # Delete the role
    echo -e "${YELLOW}Deleting role: ${role}${NC}"
    aws iam delete-role --role-name ${role}
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✓ Successfully deleted role: ${role}${NC}"
    else
      echo -e "${RED}Failed to delete role: ${role}${NC}"
    fi
  done
else
  echo -e "${GREEN}No IAM roles found${NC}"
fi

# 6. Check for KMS keys
echo -e "\n${YELLOW}6. Checking for KMS keys...${NC}"
KMS_KEYS=$(aws kms list-keys --query "Keys[].KeyId" --output text)

if [ -n "$KMS_KEYS" ]; then
  echo -e "${YELLOW}Found KMS keys, checking for Cloudable-related keys...${NC}"
  
  for key_id in $KMS_KEYS; do
    KEY_INFO=$(aws kms describe-key --key-id ${key_id})
    KEY_DESC=$(echo $KEY_INFO | jq -r '.KeyMetadata.Description')
    
    if [[ "$KEY_DESC" == *"cloudable"* || "$KEY_DESC" == *"Cloudable"* ]]; then
      echo -e "${YELLOW}Found Cloudable KMS key: ${key_id} - ${KEY_DESC}${NC}"
      
      # Check if key is scheduled for deletion
      KEY_STATE=$(echo $KEY_INFO | jq -r '.KeyMetadata.KeyState')
      if [ "$KEY_STATE" != "PendingDeletion" ]; then
        echo -e "${YELLOW}Scheduling key for deletion: ${key_id}${NC}"
        aws kms schedule-key-deletion --key-id ${key_id} --pending-window-in-days 7
        
        if [ $? -eq 0 ]; then
          echo -e "${GREEN}✓ Successfully scheduled key for deletion: ${key_id}${NC}"
        else
          echo -e "${RED}Failed to schedule key for deletion: ${key_id}${NC}"
        fi
      else
        echo -e "${GREEN}Key is already scheduled for deletion: ${key_id}${NC}"
      fi
    fi
  done
else
  echo -e "${GREEN}No KMS keys found${NC}"
fi

# Final summary
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${GREEN}AWS resource final cleanup completed!${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "All AWS resources have been cleaned up or scheduled for deletion.\n"
echo -e "${YELLOW}Note: Some resources may take a few minutes to be fully deleted.${NC}"
echo -e "${YELLOW}You can check the AWS Management Console to verify.${NC}"

exit 0
