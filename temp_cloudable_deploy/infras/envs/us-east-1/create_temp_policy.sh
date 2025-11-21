#!/bin/bash

# Create a temporary data access policy for the current user
aws opensearchserverless create-access-policy \
  --name temp-admin-access \
  --type data \
  --policy "[{\"Rules\":[{\"ResourceType\":\"index\",\"Resource\":[\"index/*/*\"],\"Permission\":[\"aoss:*\"]},{\"ResourceType\":\"collection\",\"Resource\":[\"collection/*\"],\"Permission\":[\"aoss:*\"]}],\"Principal\":[\"arn:aws:iam::975049969923:user/araj-cbsbx8-iam\"]}]"

# Wait a bit for the policy to propagate
echo "Waiting for the policy to propagate..."
sleep 30

# Run the Python script to create the index
source ./venv/bin/activate
python create_index.py onpedz3l4jkjfzmkc9r0 default-index us-east-1
python create_index.py 8tlncae5m94p8q9e944e default-index us-east-1

# Delete the temporary access policy
aws opensearchserverless delete-access-policy \
  --name temp-admin-access \
  --type data
