#!/bin/bash

# Make sure the Python script is executable
chmod +x create_opensearch_index.py

# Install required Python packages
pip3 install --user boto3 requests requests-aws4auth

# Get collection IDs from Terraform state
echo "Getting collection IDs from Terraform state..."

# Make the script run in the correct directory
cd "$(dirname "$0")"

# Extract collection IDs
ACME_COLLECTION_ID=$(terraform state show 'aws_opensearchserverless_collection.kb["t001"]' | grep "id" | head -n 1 | awk -F '= ' '{print $2}' | tr -d '"')
GLOBEX_COLLECTION_ID=$(terraform state show 'aws_opensearchserverless_collection.kb["t002"]' | grep "id" | head -n 1 | awk -F '= ' '{print $2}' | tr -d '"')

echo "ACME Collection ID: $ACME_COLLECTION_ID"
echo "GLOBEX Collection ID: $GLOBEX_COLLECTION_ID"

# Create indexes
echo "Creating indexes..."
python3 create_opensearch_index.py --collection-id "$ACME_COLLECTION_ID" --index-name "default-index"
python3 create_opensearch_index.py --collection-id "$GLOBEX_COLLECTION_ID" --index-name "default-index"

echo "Setup complete!"
