#!/bin/bash

# Install required Python packages
pip install boto3 requests requests_aws4auth

# Make the script executable
chmod +x create_index.py

# Get collection IDs from Terraform state
echo "Getting collection IDs from Terraform state..."
ACME_COLLECTION_ID=$(terraform state show 'aws_opensearchserverless_collection.kb["t001"]' | grep "id" | head -n 1 | awk -F '= ' '{print $2}' | tr -d '"')
GLOBEX_COLLECTION_ID=$(terraform state show 'aws_opensearchserverless_collection.kb["t002"]' | grep "id" | head -n 1 | awk -F '= ' '{print $2}' | tr -d '"')
REGION=$(terraform state show 'aws_opensearchserverless_collection.kb["t001"]' | grep "region" | head -n 1 | awk -F '= ' '{print $2}' | tr -d '"')

echo "ACME Collection ID: $ACME_COLLECTION_ID"
echo "GLOBEX Collection ID: $GLOBEX_COLLECTION_ID"
echo "Region: $REGION"

# Create indexes
echo "Creating indexes..."
python3 create_index.py "$ACME_COLLECTION_ID" "default-index" "$REGION"
python3 create_index.py "$GLOBEX_COLLECTION_ID" "default-index" "$REGION"

echo "Done creating indexes."
